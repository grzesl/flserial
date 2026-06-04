import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flserial/flserial_port_bindings.dart';
import 'package:flutter/services.dart';
import 'package:flserial/serial_scanner.dart';
import 'serial_types.dart';

export 'serial_types.dart';

/// Asynchronous serial port driver for Flutter.
///
/// Supports Windows, Linux, macOS (via Dart FFI + native C++) and Android
/// (via USB Host API platform channel).
///
/// ## Basic usage
///
/// ```dart
/// final serial = FlSerial();
///
/// serial.events.listen((event) {
///   if (event.type == SerialEventType.data) {
///     print(String.fromCharCodes(event.data as Uint8List));
///   }
/// });
///
/// final ports = await FlSerial.availablePorts();
/// await serial.open(ports.first.path, SerialConfig(baudRate: 115200));
/// serial.write(Uint8List.fromList('hello\n'.codeUnits));
/// await serial.close();
/// await serial.dispose();
/// ```
///
/// ## Android
///
/// Paths starting with `usb:` are routed through the USB Host platform
/// channel. The OS permission dialog is shown automatically on first connect.
///
/// Requires `<uses-feature android:name="android.hardware.usb.host" />` in
/// the host app's `AndroidManifest.xml`.
class FlSerial {
  static final _usbMethodChannel =
      MethodChannel('io.github.grzesl.flserial/usb');
  static final _usbEventChannel =
      EventChannel('io.github.grzesl.flserial/usb_data');

  late FLSerialBindings _bindings;
  ffi.Pointer<SerialPort>? _serialPtr;

  ReceivePort? _receivePort;
  StreamSubscription? _subscription;

  bool _isUsbMode = false;
  String? _usbDeviceName;
  StreamSubscription? _usbDataSubscription;

  /// Broadcast stream of all port events.
  ///
  /// Subscribe before calling [open] to avoid missing the initial
  /// [SerialEventType.connected] event.
  final _eventController = StreamController<SerialEvent>.broadcast();

  /// Broadcast stream of all port events (connect, disconnect, data, line
  /// status changes, errors).
  Stream<SerialEvent> get events => _eventController.stream;

  /// Convenience stream that emits only raw received bytes.
  ///
  /// Equivalent to filtering [events] for [SerialEventType.data].
  Stream<Uint8List> get dataStream => events
      .where((e) => e.type == SerialEventType.data)
      .map((e) => e.data as Uint8List);

  /// Creates a new [FlSerial] instance and loads the native library.
  ///
  /// Throws [UnsupportedError] if the native library cannot be loaded.
  FlSerial() {
    _initNative();
  }

  void _initNative() {
    const libName = 'flserial';

    final DynamicLibrary dylib = () {
      try {
        if (Platform.isMacOS || Platform.isIOS) {
          return DynamicLibrary.open('$libName.framework/$libName');
        }
        if (Platform.isAndroid || Platform.isLinux) {
          return DynamicLibrary.open('lib$libName.so');
        }
        if (Platform.isWindows) {
          return DynamicLibrary.open('$libName.dll');
        }
        throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
      } catch (e) {
        throw UnsupportedError('flserial: cannot load native library: $e');
      }
    }();

    _bindings = FLSerialBindings(dylib);

    if (_bindings.InitDartApiDL(ffi.NativeApi.initializeApiDLData) != 0) {
      throw Exception('FFI: InitDartApiDL failed');
    }

    _serialPtr = _bindings.serial_new();
  }

  /// Opens [path] with the given [config].
  ///
  /// Returns `true` on success, `false` if the port could not be opened
  /// (device busy, wrong path, permission denied, etc.).
  ///
  /// On Android, `usb:`-prefixed paths trigger the USB permission dialog; the
  /// method resolves only after the user responds.
  ///
  /// Calling [open] while a port is already open implicitly closes the
  /// previous session first.
  Future<bool> open(String path, SerialConfig config) async {
    _stopSession();

    if (Platform.isAndroid && path.startsWith('usb:')) {
      return _openUsb(path.substring(4), config);
    }

    _receivePort = ReceivePort();
    _subscription = _receivePort!.listen(_handleNativeMessage);

    final pathPtr = path.toNativeUtf8();
    try {
      _bindings.register_port(_serialPtr!, _receivePort!.sendPort.nativePort);

      final success = _bindings.serial_open_ext(
        _serialPtr!,
        pathPtr.cast(),
        config.baudRate,
        config.dataBits,
        config.stopBits,
        config.parity,
        config.flowControl,
      );

      if (!success) {
        _stopSession();
        return false;
      }

      return true;
    } finally {
      malloc.free(pathPtr);
    }
  }

  Future<bool> _openUsb(String deviceName, SerialConfig config) async {
    try {
      final ok = await _usbMethodChannel.invokeMethod<bool>('openUsbDevice', {
        'name': deviceName,
        'baud': config.baudRate,
      });
      if (ok != true) return false;

      _isUsbMode = true;
      _usbDeviceName = deviceName;

      _usbDataSubscription =
          _usbEventChannel.receiveBroadcastStream().listen((dynamic event) {
        if (event is Map) {
          final bytes = event['data'];
          if (bytes is Uint8List) {
            _eventController.add(SerialEvent(SerialEventType.data, bytes));
          }
        }
      });

      _eventController.add(SerialEvent(SerialEventType.connected, null));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleNativeMessage(dynamic msg) {
    if (msg is Uint8List) {
      _eventController.add(SerialEvent(SerialEventType.data, msg));
    } else if (msg is List && msg.isNotEmpty) {
      final type = SerialEventType.fromInt(msg[0] as int);
      if (type == null) return;

      if (type == SerialEventType.lineStatusChanged && msg.length > 1) {
        final int mask = msg[1] as int;
        _eventController.add(SerialEvent(type, {
          'CTS': (mask & 0x01) != 0,
          'DSR': (mask & 0x02) != 0,
          'RI':  (mask & 0x04) != 0,
          'DCD': (mask & 0x08) != 0,
        }));
      } else {
        _eventController
            .add(SerialEvent(type, msg.length > 1 ? msg[1] : null));
      }
    }
  }

  /// Sets the DTR (Data Terminal Ready) control line.
  ///
  /// Has no effect if the port is not open.
  void setDTR(bool active) {
    if (_serialPtr != null) {
      _bindings.serial_set_dtr(_serialPtr!, active ? 1 : 0);
    }
  }

  /// Sets the RTS (Request To Send) control line.
  ///
  /// Has no effect if the port is not open or if hardware flow control is
  /// enabled (the driver controls RTS automatically in that case).
  void setRTS(bool active) {
    if (_serialPtr != null) {
      _bindings.serial_set_rts(_serialPtr!, active ? 1 : 0);
    }
  }

  /// Returns the current state of the input modem control lines.
  ///
  /// Returns an empty map if the port is not open.
  ///
  /// Keys: `'CTS'`, `'DSR'`, `'RI'`, `'DCD'`.
  Map<String, bool> getModemStatus() {
    if (_serialPtr == null) return {};
    final int status = _bindings.serial_get_modem_status(_serialPtr!);
    return {
      'CTS': (status & 0x01) != 0,
      'DSR': (status & 0x02) != 0,
      'RI':  (status & 0x04) != 0,
      'DCD': (status & 0x08) != 0,
    };
  }

  /// Sends [data] to the open port.
  ///
  /// The call returns immediately; the data is written asynchronously by the
  /// native worker thread. Has no effect if the port is not open.
  void write(Uint8List data) {
    if (_isUsbMode && _usbDeviceName != null) {
      _usbMethodChannel.invokeMethod<void>('writeUsbDevice', {
        'name': _usbDeviceName,
        'data': data,
      });
      return;
    }
    if (_serialPtr == null) return;
    final ptr = malloc.allocate<ffi.Uint8>(data.length);
    try {
      ptr.asTypedList(data.length).setAll(0, data);
      _bindings.serial_write(_serialPtr!, ptr.cast(), data.length);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Closes the currently open port and emits [SerialEventType.disconnected].
  ///
  /// Safe to call even if no port is open.
  Future<void> close() async {
    if (_isUsbMode) {
      final name = _usbDeviceName;
      _stopSession();
      if (name != null) {
        await _usbMethodChannel.invokeMethod('closeUsbDevice', {'name': name});
      }
      _eventController.add(SerialEvent(SerialEventType.disconnected, null));
      return;
    }
    if (_serialPtr != null) _bindings.serial_close(_serialPtr!);
    await Future.delayed(Duration.zero);
    _stopSession();
  }

  void _stopSession() {
    _usbDataSubscription?.cancel();
    _usbDataSubscription = null;
    _isUsbMode = false;
    _usbDeviceName = null;
    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
  }

  /// Closes the port and releases all native resources.
  ///
  /// The instance must not be used after calling [dispose].
  Future<void> dispose() async {
    await close();
    if (_serialPtr != null) {
      _bindings.serial_free(_serialPtr!);
      _serialPtr = null;
    }
    _eventController.close();
  }

  /// Returns all serial ports currently visible on this device.
  ///
  /// Delegates to [SerialScanner.getAvailablePorts].
  static Future<List<SerialPortInfo>> availablePorts() async {
    return SerialScanner.getAvailablePorts();
  }
}
