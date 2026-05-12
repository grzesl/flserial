#ifndef SERIAL_PORT_HPP
#define SERIAL_PORT_HPP

#include <string>
#include <vector>
#include <queue>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>
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

    bool open(const std::string &portName, int baudRate, int dataBits, int stopBits, int parity, int flowControl = 0)
    {
        close();

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

        dcb.fOutxDsrFlow = FALSE;
        if (flowControl == 1) {
            // Hardware RTS/CTS
            dcb.fOutxCtsFlow = TRUE;
            dcb.fRtsControl  = RTS_CONTROL_HANDSHAKE;
            dcb.fDtrControl  = DTR_CONTROL_ENABLE;
            dcb.fOutX = FALSE;
            dcb.fInX  = FALSE;
        } else if (flowControl == 2) {
            // Software XON/XOFF
            dcb.fOutxCtsFlow = FALSE;
            dcb.fRtsControl  = RTS_CONTROL_ENABLE;
            dcb.fDtrControl  = DTR_CONTROL_ENABLE;
            dcb.fOutX  = TRUE;
            dcb.fInX   = TRUE;
            dcb.XonChar  = 0x11;
            dcb.XoffChar = 0x13;
            dcb.XonLim   = 100;
            dcb.XoffLim  = 100;
        } else {
            // No flow control
            dcb.fOutxCtsFlow = FALSE;
            dcb.fRtsControl  = RTS_CONTROL_ENABLE;
            dcb.fDtrControl  = DTR_CONTROL_ENABLE;
            dcb.fOutX = FALSE;
            dcb.fInX  = FALSE;
        }

        SetCommState(hSerial, &dcb);

        COMMTIMEOUTS timeouts = {0};
        timeouts.ReadIntervalTimeout = MAXDWORD;
        timeouts.ReadTotalTimeoutConstant = 0;
        timeouts.ReadTotalTimeoutMultiplier = 0;
        // 2-second write timeout — prevents WriteFile from blocking indefinitely
        // (e.g. when com0com flow control stalls the port)
        timeouts.WriteTotalTimeoutConstant = 2000;
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

        // Flow control (cfmakeraw clears IXON/IXOFF/CRTSCTS by default)
        if (flowControl == 1) {
            tty.c_cflag |= CRTSCTS;
        } else if (flowControl == 2) {
            tty.c_iflag |= (IXON | IXOFF);
        }

        tcsetattr(fd, TCSANOW, &tty);
#endif

        running = true;
        last_modem_status = get_modem_status();

        readThread = std::thread(&SerialPort::run, this);
        writeThread = std::thread(&SerialPort::writeLoop, this);

        send_simple_event(EVENT_CONNECTED);

        return true;
    }

    void close()
    {
        if (running)
        {
            running = false;
            writeCV.notify_all();

            if (writeThread.joinable())
                writeThread.join();
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

    // Non-blocking: pushes data to write queue, returns immediately
    void write(const uint8_t *data, int length)
    {
        if (length <= 0) return;
        std::vector<uint8_t> buf(data, data + length);
        {
            std::lock_guard<std::mutex> lock(writeMutex);
            writeQueue.push(std::move(buf));
        }
        writeCV.notify_one();
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
    std::thread writeThread;
    std::atomic<Dart_Port> send_port_id;
    std::atomic<int> last_modem_status;
    std::chrono::steady_clock::time_point last_status_check;

    std::queue<std::vector<uint8_t>> writeQueue;
    std::mutex writeMutex;
    std::condition_variable writeCV;

#ifdef PLATFORM_WINDOWS
    HANDLE hSerial;
#else
    int fd;
#endif

    // Dedicated write thread — drains writeQueue without blocking Dart
    void writeLoop()
    {
        while (running)
        {
            std::vector<uint8_t> buf;
            {
                std::unique_lock<std::mutex> lock(writeMutex);
                writeCV.wait_for(lock, std::chrono::milliseconds(5),
                    [this] { return !writeQueue.empty() || !running; });
                if (!writeQueue.empty())
                {
                    buf = std::move(writeQueue.front());
                    writeQueue.pop();
                }
            }
            if (buf.empty()) continue;

#ifdef PLATFORM_WINDOWS
            if (hSerial == INVALID_HANDLE_VALUE) continue;
            DWORD written;
            WriteFile(hSerial, buf.data(), (DWORD)buf.size(), &written, NULL);
#else
            if (fd == -1) continue;
            int total = 0;
            while (total < (int)buf.size())
            {
                int n = ::write(fd, buf.data() + total, buf.size() - total);
                if (n > 0) {
                    total += n;
                } else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(1));
                } else {
                    break;
                }
            }
#endif
        }
    }

    void run()
    {
        uint8_t buffer[2048];
        while (running)
        {
            int current_status = get_modem_status();
            if (current_status != last_modem_status)
            {
                send_complex_event(EVENT_LINE_STATUS_CHANGED, current_status);
                last_modem_status = current_status;
            }

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
