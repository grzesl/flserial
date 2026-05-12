#include "dart_api_dl.h"
#include "SerialPort.hpp"
#include <vector>
#include <stdint.h>

// Definicja makra dla eksportu symboli
#if defined(_WIN32)
    #define FFI_EXPORT __declspec(dllexport)
#else
    #define FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

extern "C" {

// --- INICJALIZACJA DART API ---

FFI_EXPORT intptr_t InitDartApiDL(void* data) {
    return Dart_InitializeApiDL(data);
}

// --- ZARZĄDZANIE INSTANCJĄ ---

FFI_EXPORT SerialPort* serial_new() {
    return new SerialPort();
}

FFI_EXPORT void serial_free(SerialPort* sp) {
    delete sp;
}

// --- KOMUNIKACJA I KONFIGURACJA ---

FFI_EXPORT void register_port(SerialPort* sp, Dart_Port port_id) {
    if (sp) {
        sp->set_port(port_id);
    }
}

FFI_EXPORT bool serial_open_ext(SerialPort* sp, const char* path, int baud, int dataBits, int stopBits, int parity, int flowControl) {
    if (!sp) return false;
    return sp->open(std::string(path), baud, dataBits, stopBits, parity, flowControl);
}

FFI_EXPORT void serial_close(SerialPort* sp) {
    if (sp) {
        sp->close();
    }
}

FFI_EXPORT void serial_write(SerialPort* sp, const uint8_t* data, int length) {
    if (sp) {
        sp->write(data, length);
    }
}

// --- LINIE MODEMOWE (CONTROL) ---

FFI_EXPORT void serial_set_dtr(SerialPort* sp, int active) {
    if (sp) {
        sp->set_dtr(active != 0);
    }
}

FFI_EXPORT void serial_set_rts(SerialPort* sp, int active) {
    if (sp) {
        sp->set_rts(active != 0);
    }
}

// --- STATUS LINII (INPUT) ---

FFI_EXPORT int serial_get_modem_status(SerialPort* sp) {
    if (!sp) return 0;
    return sp->get_modem_status();
}

} // extern "C"