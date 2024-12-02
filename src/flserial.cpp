#include "flserial.h"
#include "serial/serial.h"
#include "tinycthread.h"
#include "fifo.h"
#include <iostream>

typedef struct _flserial_
{
    char portname[MAX_PORT_NAME_LEN + 1];
    int baudrate;
    serial::Serial *serialport;
    enum FlError lasterror;
    thrd_t cthread;
    int breakThread;
    fifo_t *cfifo;
    flcallback callback;
} FlSerial;

int SerialThread(void * aArg)
{
  FlSerial *serial = (FlSerial*)aArg;
  int res = 0;
  uint8_t buff[1024];
  size_t len = sizeof(buff);

  while(!serial->breakThread) {

    res = (int)serial->serialport->read((uint8_t *)buff, (size_t)len);
    if(res > 0) {
        fifo_write(serial->cfifo, (const char*)buff, res);
        serial->callback(0,res);
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
#if !defined(__linux__)
    port->serialport->setTimeout(serial::Timeout(0, 10, 0, 10, 0));
#endif // #if defined(__linux__)
    port->serialport->setPort(portname);
    port->serialport->setBaudrate(baudrate);

    // port->serialport->setParity(serial::parity_t::parity_none)

    try
    {
        port->serialport->open();
        port->cfifo = fifo_create(1024*50);
        thrd_create(&port->cthread, SerialThread, (void*)port);
    }
    catch (const std::exception &)
    {
        port->lasterror = FlError::FL_ERROR_PORT_ALLREADY_OPEN;
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

    read = fifo_read(port->cfifo, buff,  len);


    /*try
    {
        res = (int)port->serialport->read((uint8_t *)buff, (size_t)len);
    }
    catch (const std::exception &)
    {
        port->lasterror = FlError::FL_ERROR_PORT_ALLREADY_OPEN;
    }*/

    return read;
}

FFI_PLUGIN_EXPORT int fl_write(int flh, int len, char *data)
{
    FlSerial *port = flserial_tab[flh];
    int res = 0;
    try
    {
        res = (int)port->serialport->write((uint8_t *)data, (size_t)len);
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
        thrd_join(port->cthread, NULL);
        port->serialport->close();
        fifo_destroy(port->cfifo);
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

FFI_PLUGIN_EXPORT int fl_free()
{
    return 0;
}
