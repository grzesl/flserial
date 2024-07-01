#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#define MAX_PORT_NAME_LEN 512
#define MAX_PORT_COUNT 128

enum flCtrl {
  FL_CTRL_LAST_ERROR,
  FL_CTRL_IS_PORT_OPEN,
  FL_CTRL_BREAK,
  FL_CTRL_SET_RTS,
  FL_CTRL_GET_CTS,
  FL_CTRL_SET_DTR,
  FL_CTRL_GET_DSR,
  FL_CTRL_LAST
};

enum flError {
    FL_ERROR_OK,
    FL_ERROR_UNKNOW,
    FL_ERROR_PORT_ALLREADY_OPEN,
    FL_ERROR_HANDLER,
    FL_ERROR_LAST,
};

#ifdef __cplusplus
extern "C" {
#endif

FFI_PLUGIN_EXPORT int fl_init (int portCount);
FFI_PLUGIN_EXPORT int fl_open (int flh, char *portname, int baudrate);
FFI_PLUGIN_EXPORT int fl_read (int flh, int len, char *buff);
FFI_PLUGIN_EXPORT int fl_write (int flh, int len, char *data);
FFI_PLUGIN_EXPORT int fl_close (int flh);
FFI_PLUGIN_EXPORT int fl_ctrl (int flh, enum flCtrl param, int value);
FFI_PLUGIN_EXPORT int fl_free ();


#ifdef __cplusplus
}
#endif