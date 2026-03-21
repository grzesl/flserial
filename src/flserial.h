#ifndef FLSERIAL_H
#define FLSERIAL_H

#include <stdint.h>
#include <stdbool.h>

// Definicja makra dla eksportu symboli (Windows vs POSIX)
#if defined(_WIN32)
    #define FFI_EXPORT __declspec(dllexport)
#else
    #define FFI_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Opaque pointer dla klasy SerialPort (Dart widzi to jako Pointer<Void>)
typedef struct SerialPort SerialPort;

// --- INICJALIZACJA ---

/**
 * Inicjalizuje Dart Native API. Musi być wywołane przed 
 * jakąkolwiek próbą wysłania danych przez NativePort.
 */
FFI_EXPORT intptr_t InitDartApiDL(void* data);

/**
 * Tworzy nową instancję sterownika portu szeregowego.
 */
FFI_EXPORT SerialPort* serial_new();

/**
 * Zwalnia pamięć i zamyka port.
 */
FFI_EXPORT void serial_free(SerialPort* sp);

// --- KOMUNIKACJA ---

/**
 * Rejestruje ID portu Darta, do którego C++ będzie wysyłać dane i zdarzenia.
 */
FFI_EXPORT void register_port(SerialPort* sp, int64_t port_id);

/**
 * Otwiera port z zaawansowaną konfiguracją.
 * parity: 0=none, 1=odd, 2=even
 * stopBits: 1 lub 2
 */
FFI_EXPORT bool serial_open_ext(SerialPort* sp, const char* path, int baud, int dataBits, int stopBits, int parity);

/**
 * Zamyka fizyczne połączenie z portem.
 */
FFI_EXPORT void serial_close(SerialPort* sp);

/**
 * Wysyła surowe bajty do portu.
 */
FFI_EXPORT void serial_write(SerialPort* sp, const uint8_t* data, int length);

// --- LINIE MODEMOWE (WYJŚCIA) ---

/**
 * Ustawia stan linii DTR (Data Terminal Ready).
 */
FFI_EXPORT void serial_set_dtr(SerialPort* sp, int active);

/**
 * Ustawia stan linii RTS (Request To Send).
 */
FFI_EXPORT void serial_set_rts(SerialPort* sp, int active);

// --- LINIE MODEMOWE (WEJŚCIA) ---

/**
 * Pobiera stan linii wejściowych jako maskę bitową:
 * Bit 0: CTS, Bit 1: DSR, Bit 2: RI, Bit 3: DCD
 */
FFI_EXPORT int serial_get_modem_status(SerialPort* sp);

#ifdef __cplusplus
}
#endif

#endif // FLSERIAL_H