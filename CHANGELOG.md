## 0.7.0

### Web support
* Added Web Serial API support via `dart:js_interop` — works in Chrome and Edge
* `FlSerial` is now split into a native implementation (`dart:ffi`) and a web implementation (JS interop), selected at compile time via conditional export
* `SerialScanner.getAvailablePorts()` on web returns a single `"Web Serial Port"` entry; opening it triggers the browser's native port-picker dialog (`navigator.serial.requestPort()`)
* `open()`, `write()`, `close()` transparently route through the Web Serial API on web
* `setDTR`, `setRTS`, `getModemStatus` are no-ops on web (Web Serial API does not expose modem control lines)

## 0.6.0

### Android support
* Added Android as a build target in `hook/build.dart` — native library now compiles via the Android NDK using the existing POSIX/termios code path
* Fixed build hook to use `input.config.code.targetOS` instead of `Platform.is*` — correctly identifies the **target** platform rather than the host, enabling cross-compilation for Android
* Added Android serial port scanner — probes known `/dev/` paths (`ttyUSB0–7`, `ttyACM0–7`, `ttyS0–3`, `ttyHS0–3`, `ttyMSM0–3`, `ttyGS0–3`) instead of directory listing, which SELinux blocks on Android

### Flow control
* Added `flowControl` parameter to `SerialConfig` (0 = none, 1 = RTS/CTS, 2 = XON/XOFF)
* Implemented hardware RTS/CTS flow control on Windows (`DCB`: `fOutxCtsFlow`, `RTS_CONTROL_HANDSHAKE`) and POSIX (`CRTSCTS`)
* Implemented software XON/XOFF flow control on Windows (`fOutX`/`fInX`, `XonChar`/`XoffChar`) and POSIX (`IXON`/`IXOFF`)
* Extended `serial_open_ext()` C function signature with `flowControl` parameter — updated in `flserial.h`, `flserial.cpp`, `flserial_port_bindings.dart`, and `flserial.dart`

### Native library (C++)
* Refactored `write()` to be fully non-blocking — data is now queued and drained by a dedicated `writeThread` using a condition variable, preventing Dart from blocking on slow or flow-controlled ports
* Added `writeLoop()` — drain loop handles `EAGAIN`/`EWOULDBLOCK` on POSIX gracefully with a 1 ms back-off
* Set Windows write timeout to 2 seconds (`WriteTotalTimeoutConstant = 2000`) to prevent `WriteFile` from blocking indefinitely when flow control stalls the port
* Added `std::queue`, `std::mutex`, `std::condition_variable` for the write queue

### Build hook
* Added early return when `buildCodeAssets` is false — avoids running the compiler for non-code asset invocations
* Added iOS as an alias for macOS build configuration

## 0.5.3

### Dart layer
* Fixed critical race condition in `dispose()` — `close()` is now `Future<void>` and properly awaited before freeing native resources
* Fixed potential memory leak in `write()` — native buffer is now always freed via `try/finally`
* Fixed `RangeError` crash when receiving unknown event type from C++ — `fromInt()` now returns `null` for out-of-range values
* Removed unnecessary `async` from `getModemStatus()` — it was synchronous all along
* Improved native library load error message with platform context
* Fixed missing braces on single-statement `if` blocks in `setDTR()`/`setRTS()`

### Native library (C++)
* Fixed incomplete `termios` configuration on POSIX — added `cfmakeraw()`, `VMIN=0`, `VTIME=0` to prevent inherited terminal settings from corrupting communication
* Fixed data race on `last_modem_status` and `send_port_id` — both are now `std::atomic`
* Fixed partial write on POSIX — `write()` now loops until all bytes are sent
* Fixed missing guard in `write()`, `set_dtr()`, `set_rts()` when port is closed
* Expanded POSIX baud rate support: added 57600, 230400, 460800, 921600 (platform-conditional)
* Fixed redundant double `close()` call in `serial_free()` — destructor already handles it
* Added Windows COM port path fix — ports above COM9 now automatically use `\\.\COMx` prefix required by `CreateFileA`

## 0.5.2
* Add Dart C API

## 0.5.1
* Update readme

## 0.5.0
* Completely rewritten driver

## 0.3.5
* Add support 16KB Page Size

## 0.3.4
* Changelog fix

## 0.3.3
* Replace fifo library

## 0.3.2
* MacOS support
* Memory allocation fix

## 0.3.1
* Update libs

## 0.3.0
* Import project to new plugin ffi template
* Few Api changes

## 0.2.0
* New event model
* Cleaning up unnecessary libs
* Performance improvements
* Api changes, main functions:

Stream based events, before:
```
serial.onSerialData.subscribe(
```
to:
```
serial.onSerialData.stream.listen(
```

Write serial port, before:
```
serial.write(data.length, data);     
```
to:
```
serial.write(data);    
```

## 0.1.2
* Android compilation

## 0.1.1
* Initial beta version
