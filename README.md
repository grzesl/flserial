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
```
import 'dart:typed_data';
import 'package:flserial/flserial.dart';

void main() async {
  // 1. Initialize the driver instance
  final serial = FlSerial();

  // 2. Set up the listener BEFORE opening the port 
  // This ensures we don't miss any data sent immediately after connection
  serial.events.listen((event) {
    if (event.type == SerialEventType.data) {
      // Handle incoming raw bytes as a string
      final received = String.fromCharCodes(event.data as Uint8List);
      print("📥 Received: $received");

      // 5. Close the port after receiving the response
      serial.close();
      print("🔌 Port closed successfully.");
    }
  });

  // 3. Open the port with specific configuration
  // COM3 for Windows, /dev/ttyUSB0 for Linux/macOS
  bool success = serial.open("COM3", SerialConfig(baudRate: 9600));

  if (success) {
    print("✅ Port opened!");

    // 4. Send a command (convert String to Uint8List)
    final command = Uint8List.fromList("PING\n".codeUnits);
    serial.write(command);
    print("📤 Sent: PING");
  } else {
    print("❌ Failed to open port. Check if device is connected.");
  }
}
```

---


🛡 License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.