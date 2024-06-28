#include "flserial.h"
#include "serial.h"

#define MAX_PORT_NAME_LEN 512

typedef struct _flserial_
{
    char portname [MAX_PORT_NAME_LEN + 1];
    int baudrate; 
    serial::Serial *serialport;
}flserial;

flserial *flserial_tab[128];
int flserial_count;
int current_port; 

FFI_PLUGIN_EXPORT int fl_init (int portCount) {
    flserial_count = portCount;
    current_port = -1;
    return 0;
} 

FFI_PLUGIN_EXPORT int fl_open (char *portname, int baudrate) {
    flserial_tab[++current_port] = new flserial();
    flserial *port = flserial_tab[current_port];
    strncpy(port->portname, portname, MAX_PORT_NAME_LEN);
    port->baudrate = baudrate;

    port->serialport = new serial::Serial(portname, baudrate);

    if(port->serialport->isOpen())
        return current_port; //ioh
    return -1;
}
FFI_PLUGIN_EXPORT int fl_read (int ioh, int len, char *buff) {
    flserial *port = flserial_tab[ioh];
    return port->serialport->read((uint8_t*)buff, len);
}

FFI_PLUGIN_EXPORT int fl_write (int ioh, int len, char *data) {
    flserial *port = flserial_tab[ioh];
    return port->serialport->write((uint8_t*)data, len);
}

FFI_PLUGIN_EXPORT int fl_close (int ioh) {
    flserial *port = flserial_tab[ioh];
    port->serialport->close();
    delete port->serialport;
    port->serialport = NULL;
    delete port;
    return 0;
}

FFI_PLUGIN_EXPORT int fl_ctrl(int ioh, int param, int value) {
    return 0;
}

FFI_PLUGIN_EXPORT int fl_free() {
    return 0;
}
