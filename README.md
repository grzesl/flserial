# FlSerial

A high-performance, asynchronous serial port plugin for **Flutter**, using **Dart FFI** and **Native Assets** on desktop/mobile and the **Web Serial API** on browsers.

| Platform | Transport | Notes |
|----------|-----------|-------|
| Windows | FFI → native C++ / Win32 | COM1, COM3, … |
| Linux | FFI → native C++ / termios | /dev/ttyUSB0, /dev/ttyACM0, … |
| macOS | FFI → native C++ / termios | /dev/cu.usbserial-… |
| Android | USB Host API (platform channel) | USB-serial adapters: CH340, FTDI, CP210x, CDC ACM, PL2303 |
| Web | Web Serial API (dart:js_interop) | Chrome / Edge 89+ |

---

## Features

- **Asynchronous I/O** — native C++ worker thread keeps the Flutter UI thread free
- **Reactive streams** — incoming data and events (connect / disconnect / line status) via `Stream<SerialEvent>`
- **Modem line tracking** — real-time CTS, DSR, RI, DCD status (desktop/macOS/Linux)
- **Flow control** — hardware RTS/CTS and software XON/XOFF
- **USB VID / PID** — list the VID/PID of connected devices and open a device by VID/PID at runtime
- **Android USB Host** — no root required; permission dialog handled automatically
- **Web Serial** — browser port picker dialog on first connect; works in Chrome and Edge
- **Native Assets** — compiled via `hook/build.dart`, no manual `.so`/`.dll` copy needed

---

## Installation

```yaml
dependencies:
  flserial: ^0.7.0
```

---

## Quick start

```dart
import 'dart:typed_data';
import 'package:flserial/flserial.dart';

final serial = FlSerial();

// Listen before opening so no events are missed
serial.events.listen((event) {
  switch (event.type) {
    case SerialEventType.connected:
      print('Port opened');
    case SerialEventType.data:
      print('Received: ${String.fromCharCodes(event.data as Uint8List)}');
    case SerialEventType.disconnected:
      print('Port closed');
    default:
      break;
  }
});

// Scan available ports
final ports = await FlSerial.availablePorts();
print(ports); // e.g. [COM3, /dev/ttyUSB0, Web Serial Port]

// Open a port
final config = SerialConfig(baudRate: 115200);
final ok = await serial.open(ports.first.path, config);

if (ok) {
  serial.write(Uint8List.fromList('PING\n'.codeUnits));
}

// Close when done
await serial.close();
await serial.dispose();
```

---

## USB VID / PID

Ports that belong to a USB device report their vendor ID, product ID and (where the platform exposes it) serial number:

```dart
final ports = await FlSerial.availablePorts();
for (final p in ports) {
  print('${p.path}  ${p.usbId ?? '-'}  ${p.serialNumber ?? ''}');
  // COM3  0403:6001  A50285BI
}
```

`vendorId` / `productId` are `null` for non-USB ports (built-in UARTs, virtual ports).

To connect to a specific device without knowing its port name, open it by VID/PID:

```dart
final ok = await serial.openByVidPid(0x0403, 0x6001, SerialConfig(baudRate: 115200));

// Several identical adapters? Pick one by serial number:
await serial.openByVidPid(0x0403, 0x6001, config, serialNumber: 'A50285BI');
```

`SerialScanner.findByVidPid(vid, pid)` returns all matching ports if you want to choose yourself.

---

## SerialConfig

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `baudRate` | int | 115200 | Baud rate |
| `dataBits` | int | 8 | Data bits (5–8) |
| `stopBits` | int | 1 | Stop bits (1 or 2) |
| `parity` | int | 0 | 0 = none, 1 = odd, 2 = even |
| `flowControl` | int | 0 | 0 = none, 1 = RTS/CTS, 2 = XON/XOFF |

---

## Platform notes

### Android

Add to your app's `AndroidManifest.xml`:

```xml
<uses-feature android:name="android.hardware.usb.host" />
```

The plugin requests USB permission at the OS level when you call `open()`. The connection opens automatically once the user grants it.

Supported USB-serial chips: CDC ACM, FTDI FT232, Silicon Labs CP210x, CH340/CH341, Prolific PL2303 (HX and HXN).

### Web

Scanning always returns a **"Web Serial Port"** entry first. Calling `open()` on it triggers the browser's native port-picker dialog — no permission is needed beforehand. The dialog requires a user gesture (button tap), which the `open()` call from a button handler satisfies.

Ports the user has already granted access to are listed after it, with their VID/PID. The browser does not reveal devices that have not been granted yet, so `openByVidPid()` opens a granted device directly and otherwise shows the picker filtered to that VID/PID.

> **Browser support**: Chrome 89+, Edge 89+. Not supported in Firefox or Safari.

---

## License

MIT © 2026
