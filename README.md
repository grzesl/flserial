# FlSerial

A high-performance, asynchronous serial port driver for **Flutter**, utilizing **Dart FFI** and **Native Assets** to provide low-latency hardware communication on Windows, Linux, and macOS.

---

## 🚀 Key Features

* **Asynchronous Architecture**: Moves all heavy I/O and polling to a dedicated native C++ worker thread, keeping the Flutter UI at a constant 60/120 FPS.
* **Non-Blocking I/O**: Optimized Windows implementation using `MAXDWORD` timeouts to prevent thread stalling.
* **Reactive Streams**: Listen to incoming data and hardware events (Connect/Disconnect) using standard Dart Streams.
* **Modem Line Tracking**: Real-time status monitoring for **CTS, DSR, RI, and DCD** pins with throttled CPU usage (1Hz).
* **Zero-Latency Write**: Forced buffer flushing ensures data is pushed to the wire immediately.
* **Native Assets Ready**: Uses the modern Flutter `hook/build.dart` workflow for seamless cross-platform compilation.

---

## 📂 Project Structure

```text
flserial/
├── hook/
│   └── build.dart          # Native Assets build script (MSVC/Clang/GCC)
├── lib/
│   ├── flserial.dart       # High-level Dart API & Stream logic
│   └── flserial_bindings.dart # FFI generated bindings
├── src/
│   ├── SerialPort.hpp      # Core C++ Driver (Cross-platform)
│   ├── flserial.cpp/h      # C-style FFI Bridge
│   └── dart_api_dl.cpp/h   # Dart Native API (Required for Ports)
├── example/
│   └── lib/main.dart       # Full-featured Serial Terminal example
└── pubspec.yaml
```

🛠 Prerequisites & Installation
Windows

    Visual Studio 2022: Install the "Desktop development with C++" workload.

    Permissions: None required (standard user access for COM ports).

Linux

    Build Tools: sudo apt install clang cmake ninja-build build-essential libc++-dev.

    Linker Fix: If you encounter ld errors, ensure lld is installed: sudo apt install lld.

    Permissions: Add your user to the dialout group:
    Bash

    sudo usermod -a -G dialout $USER

    Note: You must log out and back in for changes to take effect.

macOS

    Xcode: Command Line Tools must be installed.

    Entitlements: If your app is Sandboxed, add the following to DebugProfile.entitlements and Release.entitlements:
    XML

    <key>com.apple.security.device.serial</key>
    <true/>

📖 Usage Guide
1. Initialization

Create an instance of the driver. It will automatically initialize the Dart Native API.
Dart

final serial = FlSerial();

2. Listening to Events

Data and hardware status changes are pushed through a single stream.
Dart

serial.events.listen((event) {
  switch (event.type) {
    case SerialEventType.data:
      final rawData = event.data as Uint8List;
      print("Received: ${String.fromCharCodes(rawData)}");
      break;

    case SerialEventType.lineStatusChanged:
      final lines = event.data as Map<String, bool>;
      print("Modem Status - CTS: ${lines['CTS']}, DCD: ${lines['DCD']}");
      break;

    case SerialEventType.connected:
      print("Port is now open and ready.");
      break;

    case SerialEventType.disconnected:
      print("Port was closed.");
      break;
      
    case SerialEventType.error:
      print("Hardware Error: ${event.data}");
      break;
  }
});

3. Opening a Port

Configure the port with SerialConfig.
Dart

bool success = serial.open(
  "COM3", // Or "/dev/ttyUSB0" on Linux
  SerialConfig(
    baudRate: 115200,
    dataBits: 8,
    stopBits: 1,
    parity: 0, // 0: None, 1: Odd, 2: Even
  ),
);

4. Writing Data

Send strings or raw bytes directly to the hardware.
Dart

void sendCommand(String cmd) {
  if (serial.isConnected) {
    serial.write(Uint8List.fromList("$cmd\r\n".codeUnits));
  }
}

⚙️ Technical Specifications
Parameter	Performance / Setting
Internal Latency	< 1ms (native processing)
Max Baud Rate	Tested up to 921600 bps
Read Loop Interval	1ms (Asynchronous)
Modem Polling	1000ms (Power-efficient throttling)
Thread Safety	Atomic-guarded worker thread
Memory Management	Opaque pointers (No Dart heap pressure)
🛡 License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.