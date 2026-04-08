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
