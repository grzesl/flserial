#include "flserial.h"
#include "serial.h"
#include <iostream>



typedef struct _flserial_
{
    char portname [MAX_PORT_NAME_LEN + 1];
    int baudrate; 
    serial::Serial *serialport;
    enum flError lasterror;
}flserial;

flserial *flserial_tab[MAX_PORT_COUNT];
int flserial_count;
int current_port; 

FFI_PLUGIN_EXPORT int fl_init (int portCount) {
    flserial_count = portCount;
    current_port = -1;
    return 0;
} 

FFI_PLUGIN_EXPORT int fl_open (int flh, char *portname, int baudrate) {
    int porth = flh;

    if (porth < 0)
        porth = ++current_port;

    flserial *port = new flserial();
    flserial_tab[porth] = port;


    strncpy_s(port->portname, portname, MAX_PORT_NAME_LEN);
    port->baudrate = baudrate;
    port->lasterror = FL_ERROR_OK;


    port->serialport = new serial::Serial();
    port->serialport->setTimeout(serial::Timeout(0,1,0));
    port->serialport->setPort(portname);
    port->serialport->setBaudrate(baudrate);
   
    
    try
    {
       port->serialport->open();
    }
    catch(const std::exception&)
    {
        port->lasterror = flError::FL_ERROR_PORT_ALLREADY_OPEN;
    }

    return porth; 
}

FFI_PLUGIN_EXPORT int fl_read (int flh, int len, char *buff) {
    flserial *port = flserial_tab[flh];
    int res = 0;

    try
    {
       res = (int)port->serialport->read((uint8_t*)buff, (size_t)len);
    }
    catch(const std::exception&)
    {
        port->lasterror = flError::FL_ERROR_PORT_ALLREADY_OPEN;
    }

    return res;
}

FFI_PLUGIN_EXPORT int fl_write (int flh, int len, char *data) {
    flserial *port = flserial_tab[flh];
    return (int)port->serialport->write((uint8_t*)data, (size_t)len);
}

FFI_PLUGIN_EXPORT int fl_close (int flh) {
    flserial *port = flserial_tab[flh];
    port->serialport->close();
    delete port->serialport;
    port->serialport = NULL;
    delete port;
    return 0;
}

FFI_PLUGIN_EXPORT int fl_ctrl(int flh, enum flCtrl param, int value) {

    int result = -1;
    flserial *port = flserial_tab[flh];

    switch (param){
        case FL_CTRL_IS_PORT_OPEN:
            result = port->serialport->isOpen()?1:0;
            break;
        case FL_CTRL_LAST_ERROR:
            result = port->lasterror;
        break;
        case FL_CTRL_BREAK:
            port->serialport->setBreak();
            result = FL_ERROR_OK;
        break;
        case FL_CTRL_SET_RTS:
            port->serialport->setRTS(value>0?true:false);
            result = FL_ERROR_OK;
        break;
        case FL_CTRL_GET_CTS:
            result = port->serialport->getCTS()?1:0;
        break;
        case FL_CTRL_SET_DTR:
            port->serialport->setDTR(value>0?true:false);
            result = FL_ERROR_OK;
        break;
        case FL_CTRL_GET_DSR:
            result = port->serialport->getDSR()?1:0;
        break;
    }
    return result;
}

FFI_PLUGIN_EXPORT int fl_free() {
    return 0;
}
