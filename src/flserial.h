#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

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

#ifdef __cplusplus
extern "C" {
#endif

FFI_PLUGIN_EXPORT int fl_init (int portCount);
FFI_PLUGIN_EXPORT int fl_open (char *portname, int baudrate);
FFI_PLUGIN_EXPORT int fl_read (int ioh, int len, char *buff);
FFI_PLUGIN_EXPORT int fl_write (int ioh, int len, char *data);
FFI_PLUGIN_EXPORT int fl_close (int ioh);
FFI_PLUGIN_EXPORT int fl_ctrl(int ioh, int param, int value);
FFI_PLUGIN_EXPORT int fl_free();


#ifdef __cplusplus
}
#endif