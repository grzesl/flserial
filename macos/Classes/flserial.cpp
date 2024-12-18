#include "flserial.h"
#include "native_libs/include/serial/serial.h"
#include "native_libs/include/tinycthread.h"
#include "native_libs/include/fifo.h"
#include <iostream>

#define FL_SERIAL_BUFF_LEN (32 * 1024)

typedef struct _flserial_
{
    char portname[MAX_PORT_NAME_LEN + 1];
    int baudrate;
    serial::Serial *serialport;
    enum FlError lasterror;
    char lasterrormsg[512];
    thrd_t cthread;
    int breakThread;
    fifo_t *cinfifo;
    fifo_t *coutfifo;
    mtx_t inFifo_mutex;
    mtx_t outFifo_mutex;
    flcallback callback;
} FlSerial;

int SerialThread(void *aArg)
{
    FlSerial *serial = (FlSerial *)aArg;
    int res = 0;
    uint8_t buff[FL_SERIAL_BUFF_LEN];
    size_t len = sizeof(buff);

    while (!serial->breakThread)
    {

        try
        {

            res = (int)serial->serialport->read((uint8_t *)buff, (size_t)len);
            if (res > 0)
            {
                mtx_lock(&serial->outFifo_mutex);
                fifo_write(serial->cinfifo, (const char *)buff, res);
                mtx_unlock(&serial->outFifo_mutex);
                serial->callback(0, res);
                // thrd_sleep(&duration, &rem);
                continue;
            }

            if (fifo_data_available(serial->coutfifo))
            {
                mtx_lock(&serial->outFifo_mutex);
                res = (size_t)fifo_read(serial->coutfifo, (char *)buff, (int)len);
                mtx_unlock(&serial->outFifo_mutex);
                res = (int)serial->serialport->write((uint8_t *)buff, (size_t)res);
            }
        }
        catch (const serial::IOException &ioe)
        {
            serial->lasterror = FL_ERROR_IO;
            strncpy(serial->lasterrormsg , ioe.what(), sizeof(serial->lasterrormsg) - 1);
        }
    }

    return 0;
}

FlSerial *flserial_tab[MAX_PORT_COUNT];
int flserial_count;
int current_port;

FFI_PLUGIN_EXPORT int fl_set_callback(int flh, flcallback cb)
{
    FlSerial *port = flserial_tab[flh];
    port->callback = cb;
    return 0;
}

FFI_PLUGIN_EXPORT int fl_init(int portCount)
{
    if (portCount > MAX_PORT_COUNT)
        return 1;

    flserial_count = portCount;
    current_port = -1;

    return 0;
}

FFI_PLUGIN_EXPORT int fl_open(int flh, char *portname, int baudrate)
{
    int porth = flh;

    if (porth < 0)
        porth = ++current_port;

    FlSerial *port = new FlSerial();
    port->breakThread = 0;

    flserial_tab[porth] = port;

    strncpy(port->portname, portname, MAX_PORT_NAME_LEN);

    port->baudrate = baudrate;
    port->lasterror = FL_ERROR_OK;

    port->serialport = new serial::Serial();
#if !defined(__linux__) && !defined(__APPLE__)
    port->serialport->setTimeout(serial::Timeout(FL_SERIAL_BUFF_LEN, 2, 0, 0, 0));
#endif // #if defined(__linux__)
    port->serialport->setPort(portname);
    port->serialport->setBaudrate(baudrate);

    try
    {
        port->serialport->open();
        port->cinfifo = fifo_create(MAX_PORT_FIFO_LEN);
        port->coutfifo = fifo_create(MAX_PORT_FIFO_LEN);
        port->serialport->setBytesize(serial::bytesize_t::eightbits);
        port->serialport->setParity(serial::parity_t::parity_none);
        port->serialport->setStopbits(serial::stopbits_one);
        thrd_create(&port->cthread, SerialThread, (void *)port);
        mtx_init(&port->inFifo_mutex, mtx_plain);
        mtx_init(&port->outFifo_mutex, mtx_plain);
    }
    catch (const serial::IOException &ioe)
    {
        strncpy(port->lasterrormsg, ioe.what(), sizeof(port->lasterrormsg) - 1);

        switch (ioe.getErrorNumber())
        {
        case 1:
            port->lasterror = FlError::FL_ERROR_PORT_NOT_EXIST;
            break;
        case 2:
            port->lasterror = FlError::FL_ERROR_PORT_ALLREADY_OPEN;
            break;
        default:
            port->lasterror = FlError::FL_ERROR_UNKNOW;
            break;
        }
    }
    catch (const std::exception)
    {
        port->lasterror = FlError::FL_ERROR_UNKNOW;
    }

    return porth;
}

FFI_PLUGIN_EXPORT int fl_ports(int index, int buffsize, char *buff)
{
    auto list = serial::list_ports();
    if (serial::list_ports().size() <= index)
    {
        return 0;
    }
    else
    {
        serial::PortInfo info = list[index];
        return snprintf(buff, buffsize, "%s - %s - %s", info.port.c_str(), info.description.c_str(), info.hardware_id.c_str());
    }
}

FFI_PLUGIN_EXPORT int fl_read(int flh, int len, char *buff)
{
    FlSerial *port = flserial_tab[flh];
    int res = 0;

    char *buf = NULL;
    size_t size = 0;
    int read = 0;

    mtx_lock(&port->inFifo_mutex);
    read = fifo_read(port->cinfifo, buff, len);
    mtx_unlock(&port->inFifo_mutex);

    return read;
}

FFI_PLUGIN_EXPORT int fl_write(int flh, int len, char *data)
{
    FlSerial *port = flserial_tab[flh];
    int res = 0;
    try
    {
        mtx_lock(&port->outFifo_mutex);
        res = fifo_write(port->coutfifo, data, len);
        mtx_unlock(&port->outFifo_mutex);
    }
    catch (const std::exception &)
    {
        port->lasterror = FlError::FL_ERROR_PORT_ALLREADY_OPEN;
    }

    return res;
}

FFI_PLUGIN_EXPORT int fl_close(int flh)
{
    FlSerial *port = flserial_tab[flh];

    try
    {
        port->breakThread = 1;

        if (port->cthread != 0)
            thrd_join(port->cthread, NULL);

        port->serialport->close();
        if (port->cinfifo != 0)
            fifo_destroy(port->cinfifo);
        if (port->coutfifo != 0)
            fifo_destroy(port->coutfifo);

        mtx_destroy(&port->inFifo_mutex);
        mtx_destroy(&port->outFifo_mutex);
    }
    catch (const std::exception &)
    {
    }

    delete port->serialport;
    port->serialport = NULL;
    delete port;
    return 0;
}

FFI_PLUGIN_EXPORT int fl_ctrl(int flh, FlCtrl param, int value)
{

    int result = -1;
    FlSerial *port = flserial_tab[flh];

    try
    {
        switch (param)
        {
        case FL_CTRL_IS_PORT_OPEN:
            result = port->serialport->isOpen() ? 1 : 0;
            break;
        case FL_CTRL_LAST_ERROR:
            result = port->lasterror;
            break;
        case FL_CTRL_BREAK:
            port->serialport->setBreak();
            result = FL_ERROR_OK;
            break;
        case FL_CTRL_SET_RTS:
            port->serialport->setRTS(value > 0 ? true : false);
            result = FL_ERROR_OK;
            break;
        case FL_CTRL_GET_CTS:
            result = port->serialport->getCTS() ? 1 : 0;
            break;
        case FL_CTRL_SET_DTR:
            port->serialport->setDTR(value > 0 ? true : false);
            result = FL_ERROR_OK;
            break;
        case FL_CTRL_GET_DSR:
            result = port->serialport->getDSR() ? 1 : 0;
            break;

        case FL_CTRL_SET_BYTESIZE_5:
            port->serialport->setBytesize(serial::bytesize_t::fivebits);
            result = 1;
            break;
        case FL_CTRL_SET_BYTESIZE_6:
            port->serialport->setBytesize(serial::bytesize_t::sixbits);
            result = 1;
            break;
        case FL_CTRL_SET_BYTESIZE_7:
            port->serialport->setBytesize(serial::bytesize_t::sevenbits);
            result = 1;
            break;
        case FL_CTRL_SET_BYTESIZE_8:
            port->serialport->setBytesize(serial::bytesize_t::eightbits);
            result = 1;
            break;
        case FL_CTRL_SET_PARITY_NONE:
            port->serialport->setParity(serial::parity_t::parity_none);
            result = 1;
            break;
        case FL_CTRL_SET_PARITY_ODD:
            port->serialport->setParity(serial::parity_t::parity_odd);
            result = 1;
            break;
        case FL_CTRL_SET_PARITY_EVEN:
            port->serialport->setParity(serial::parity_t::parity_even);
            result = 1;
            break;
        case FL_CTRL_SET_PARITY_MARK:
            port->serialport->setParity(serial::parity_t::parity_mark);
            result = 1;
            break;
        case FL_CTRL_SET_PARITY_SPACE:
            port->serialport->setParity(serial::parity_t::parity_space);
            result = 1;
            break;
        case FL_CTRL_SET_STOPBITS_ONE:
            port->serialport->setStopbits(serial::stopbits_t::stopbits_one);
            result = 1;
            break;
        case FL_CTRL_SET_STOPBITS_TWO:
            port->serialport->setStopbits(serial::stopbits_t::stopbits_two);
            result = 1;
            break;
        case FL_CTRL_SET_STOPBITS_ONE_POINT_FIVE:
            port->serialport->setStopbits(serial::stopbits_t::stopbits_one_point_five);
            result = 1;
            break;
        case FL_CTRL_SET_FLOWCONTROL_NONE:
            port->serialport->setFlowcontrol(serial::flowcontrol_t::flowcontrol_none);
            result = 1;
            break;
        case FL_CTRL_SET_FLOWCONTROL_HARDWARE:
            port->serialport->setFlowcontrol(serial::flowcontrol_t::flowcontrol_hardware);
            result = 1;
            break;
            port->serialport->setFlowcontrol(serial::flowcontrol_t::flowcontrol_software);
            result = 1;
        case FL_CTRL_SET_FLOWCONTROL_SOFTWARE:
            break;
        case FL_CTRL_GET_STATUS_CHANGE:
            port->serialport->waitForChange();
            result = 1;
            break;

        default:
            result = -1;
            break;
        }
    }
    catch (const std::exception &)
    {
        port->lasterror = FlError::FL_ERROR_PORT_ALLREADY_OPEN;
    }
    return result;
}

FFI_PLUGIN_EXPORT int fl_free(void)
{
    flserial_count = 0;
    return 0;
}
