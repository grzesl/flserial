#ifndef SERIAL_PORT_HPP
#define SERIAL_PORT_HPP

#include <string>
#include <vector>
#include <atomic>
#include <thread>
#include <mutex>
#include <chrono>
#include <stdint.h>

#include "dart_api_dl.h"

#if defined(_WIN32) || defined(_WIN64)
#include <windows.h>
#define PLATFORM_WINDOWS
#else
#include <fcntl.h>
#include <errno.h>
#include <termios.h>
#include <unistd.h>
#include <sys/ioctl.h>
#define PLATFORM_POSIX
#endif

enum SerialEventType
{
    EVENT_DATA = 0,
    EVENT_CONNECTED = 1,
    EVENT_DISCONNECTED = 2,
    EVENT_LINE_STATUS_CHANGED = 3,
    EVENT_ERROR = 4
};

class SerialPort
{
public:
    SerialPort() : running(false), send_port_id(0), last_modem_status(-1)
    {
#ifdef PLATFORM_WINDOWS
        hSerial = INVALID_HANDLE_VALUE;
#else
        fd = -1;
#endif
    }

    ~SerialPort()
    {
        close();
    }

    void set_port(Dart_Port port_id)
    {
        send_port_id = port_id;
    }

    bool open(const std::string &portName, int baudRate, int dataBits, int stopBits, int parity)
    {
        close(); // Upewnij się, że stary port jest zamknięty

#ifdef PLATFORM_WINDOWS
        std::string portPath = (portName.rfind("\\\\.\\", 0) == 0)
            ? portName
            : "\\\\.\\" + portName;
        hSerial = CreateFileA(portPath.c_str(), GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
        if (hSerial == INVALID_HANDLE_VALUE)
            return false;

        DCB dcb = {0};
        dcb.DCBlength = sizeof(dcb);
        GetCommState(hSerial, &dcb);
        dcb.BaudRate = baudRate;
        dcb.ByteSize = (BYTE)dataBits;
        dcb.StopBits = (stopBits == 1) ? ONESTOPBIT : TWOSTOPBITS;
        dcb.Parity = (BYTE)parity;
        dcb.fBinary = TRUE;
        dcb.fParity = (parity > 0);

        dcb.fOutxCtsFlow = FALSE; // Wyłącz czekanie na sygnał CTS od urządzenia
        dcb.fOutxDsrFlow = FALSE; // Wyłącz czekanie na sygnał DSR
        dcb.fDtrControl = DTR_CONTROL_ENABLE;
        dcb.fRtsControl = RTS_CONTROL_ENABLE;
        dcb.fOutX = FALSE; // Wyłącz programowe sterowanie XON/XOFF
        dcb.fInX = FALSE;

        SetCommState(hSerial, &dcb);

        COMMTIMEOUTS timeouts = {0};
        // ReadIntervalTimeout = MAXDWORD + pozostałe 0 wymusza natychmiastowy powrót
        // z funkcji ReadFile, jeśli w buforze nie ma danych (non-blocking read).
        timeouts.ReadIntervalTimeout = MAXDWORD;
        timeouts.ReadTotalTimeoutConstant = 0;
        timeouts.ReadTotalTimeoutMultiplier = 0;

        // Timeouty dla zapisu (WriteFile) - ustawiamy na 0, aby system
        // nie blokował wątku czekając na potwierdzenie wysłania.
        timeouts.WriteTotalTimeoutConstant = 0;
        timeouts.WriteTotalTimeoutMultiplier = 0;
        SetCommTimeouts(hSerial, &timeouts);
#else
        fd = ::open(portName.c_str(), O_RDWR | O_NOCTTY | O_NDELAY);
        if (fd == -1)
        {
            send_simple_event(EVENT_ERROR);
            return false;
        }

        struct termios tty;
        tcgetattr(fd, &tty);

        cfmakeraw(&tty);
        tty.c_cc[VMIN]  = 0;
        tty.c_cc[VTIME] = 0;

        speed_t speed = baud_to_speed(baudRate);
        cfsetospeed(&tty, speed);
        cfsetispeed(&tty, speed);

        tty.c_cflag = (tty.c_cflag & ~CSIZE) | (dataBits == 7 ? CS7 : CS8);
        tty.c_cflag |= (CLOCAL | CREAD);
        tty.c_cflag &= ~PARENB;
        if (parity == 1)
            tty.c_cflag |= (PARENB | PARODD);
        else if (parity == 2)
            tty.c_cflag |= PARENB;
        if (stopBits == 2)
            tty.c_cflag |= CSTOPB;
        else
            tty.c_cflag &= ~CSTOPB;
        tcsetattr(fd, TCSANOW, &tty);
#endif

        running = true;
        last_modem_status = get_modem_status();

        // Start wątku czytającego
        readThread = std::thread(&SerialPort::run, this);

        send_simple_event(EVENT_CONNECTED);

        return true;
    }

    void close()
    {
        if (running)
        {

            running = false;

            if (readThread.joinable())
                readThread.join();

#ifdef PLATFORM_WINDOWS
            if (hSerial != INVALID_HANDLE_VALUE)
            {
                CloseHandle(hSerial);
                hSerial = INVALID_HANDLE_VALUE;
            }
#else
            if (fd != -1)
            {
                ::close(fd);
                fd = -1;
            }
#endif

            send_simple_event(EVENT_DISCONNECTED);
        }
    }

    void write(const uint8_t *data, int length)
    {
#ifdef PLATFORM_WINDOWS
        if (hSerial == INVALID_HANDLE_VALUE) return;
        DWORD written;
        WriteFile(hSerial, data, length, &written, NULL);
#else
        if (fd == -1) return;
        int total = 0;
        while (total < length) {
            int n = ::write(fd, data + total, length - total);
            if (n <= 0) break;
            total += n;
        }
#endif
    }

#ifndef PLATFORM_WINDOWS
    static speed_t baud_to_speed(int baudRate)
    {
        switch (baudRate) {
            case 9600:   return B9600;
            case 19200:  return B19200;
            case 38400:  return B38400;
            case 57600:  return B57600;
            case 115200: return B115200;
            case 230400: return B230400;
#ifdef B460800
            case 460800: return B460800;
#endif
#ifdef B921600
            case 921600: return B921600;
#endif
            default:     return B115200;
        }
    }
#endif

    void set_dtr(bool active)
    {
#ifdef PLATFORM_WINDOWS
        if (hSerial == INVALID_HANDLE_VALUE) return;
        EscapeCommFunction(hSerial, active ? SETDTR : CLRDTR);
#else
        if (fd == -1) return;
        int flag = TIOCM_DTR;
        ioctl(fd, active ? TIOCMBIS : TIOCMBIC, &flag);
#endif
    }

    void set_rts(bool active)
    {
#ifdef PLATFORM_WINDOWS
        if (hSerial == INVALID_HANDLE_VALUE) return;
        EscapeCommFunction(hSerial, active ? SETRTS : CLRRTS);
#else
        if (fd == -1) return;
        int flag = TIOCM_RTS;
        ioctl(fd, active ? TIOCMBIS : TIOCMBIC, &flag);
#endif
    }

    int get_modem_status()
    {
        int status = 0;
        auto now = std::chrono::steady_clock::now();
        if (std::chrono::duration_cast<std::chrono::milliseconds>(now - last_status_check).count() < 1000)
        {
            return last_modem_status;
        }
        last_status_check = now;
#ifdef PLATFORM_WINDOWS
        DWORD modemStat;
        if (GetCommModemStatus(hSerial, &modemStat))
        {
            if (modemStat & MS_CTS_ON)
                status |= 0x01;
            if (modemStat & MS_DSR_ON)
                status |= 0x02;
            if (modemStat & MS_RING_ON)
                status |= 0x04;
            if (modemStat & MS_RLSD_ON)
                status |= 0x08;
        }
#else
        int mctrl;
        if (fd != -1 && ioctl(fd, TIOCMGET, &mctrl) != -1)
        {
            if (mctrl & TIOCM_CTS)
                status |= 0x01;
            if (mctrl & TIOCM_DSR)
                status |= 0x02;
            if (mctrl & TIOCM_RI)
                status |= 0x04;
            if (mctrl & TIOCM_CD)
                status |= 0x08;
        }
#endif
        return status;
    }

private:
    std::atomic<bool> running;
    std::thread readThread;
    std::atomic<Dart_Port> send_port_id;
    std::atomic<int> last_modem_status;
    std::chrono::steady_clock::time_point last_status_check;

#ifdef PLATFORM_WINDOWS
    HANDLE hSerial;
#else
    int fd;
#endif

    void run()
    {
        uint8_t buffer[2048];
        while (running)
        {
            // Monitorowanie linii modemowych
            int current_status = get_modem_status();
            if (current_status != last_modem_status)
            {
                send_complex_event(EVENT_LINE_STATUS_CHANGED, current_status);
                last_modem_status = current_status;
            }

            // Odczyt danych
            int bytesRead = 0;
#ifdef PLATFORM_WINDOWS
            DWORD dwRead;
            if (ReadFile(hSerial, buffer, sizeof(buffer), &dwRead, NULL) && dwRead > 0)
            {
                bytesRead = (int)dwRead;
            }
#else
            bytesRead = ::read(fd, buffer, sizeof(buffer));
#endif
            if (bytesRead > 0)
            {
                send_raw_data(buffer, bytesRead);
            }
            else
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
        }
    }

    // Wysyła surowe bajty (Uint8List w Darcie)
    void send_raw_data(uint8_t *buffer, int length)
    {
        if (send_port_id == 0)
            return;
        Dart_CObject message;
        message.type = Dart_CObject_kTypedData;
        message.value.as_typed_data.type = Dart_TypedData_kUint8;
        message.value.as_typed_data.values = buffer;
        message.value.as_typed_data.length = length;
        Dart_PostCObject_DL(send_port_id, &message);
    }

    // Wysyła prosty event typu [int]
    void send_simple_event(SerialEventType type)
    {
        if (send_port_id == 0)
            return;
        Dart_CObject typeObj;
        typeObj.type = Dart_CObject_kInt32;
        typeObj.value.as_int32 = (int32_t)type;

        Dart_CObject *values[1] = {&typeObj};
        Dart_CObject msg;
        msg.type = Dart_CObject_kArray;
        msg.value.as_array.length = 1;
        msg.value.as_array.values = values;
        Dart_PostCObject_DL(send_port_id, &msg);
    }

    // Wysyła event z danymi typu [int, int]
    void send_complex_event(SerialEventType type, int data)
    {
        if (send_port_id == 0)
            return;
        Dart_CObject typeObj, dataObj;
        typeObj.type = Dart_CObject_kInt32;
        typeObj.value.as_int32 = (int32_t)type;
        dataObj.type = Dart_CObject_kInt32;
        dataObj.value.as_int32 = (int32_t)data;

        Dart_CObject *values[2] = {&typeObj, &dataObj};
        Dart_CObject msg;
        msg.type = Dart_CObject_kArray;
        msg.value.as_array.length = 2;
        msg.value.as_array.values = values;
        Dart_PostCObject_DL(send_port_id, &msg);
    }
};

#endif