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

class FlSerial {
  static final _usbMethodChannel = MethodChannel('io.github.grzesl.flserial/usb');
  static final _usbEventChannel = EventChannel('io.github.grzesl.flserial/usb_data');

  late FLSerialBindings _bindings;
  ffi.Pointer<SerialPort>? _serialPtr;

  ReceivePort? _receivePort;
  StreamSubscription? _subscription;

  bool _isUsbMode = false;
  String? _usbDeviceName;
  StreamSubscription? _usbDataSubscription;

  final _eventController = StreamController<SerialEvent>.broadcast();
  Stream<SerialEvent> get events => _eventController.stream;

  Stream<Uint8List> get dataStream => events
      .where((e) => e.type == SerialEventType.data)
      .map((e) => e.data as Uint8List);

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

  /// Opens a port. On Android, "usb:" paths use the USB Host platform channel.
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
        _eventController.add(
            SerialEvent(type, msg.length > 1 ? msg[1] : null));
      }
    }
  }

  void setDTR(bool active) {
    if (_serialPtr != null) {
      _bindings.serial_set_dtr(_serialPtr!, active ? 1 : 0);
    }
  }

  void setRTS(bool active) {
    if (_serialPtr != null) {
      _bindings.serial_set_rts(_serialPtr!, active ? 1 : 0);
    }
  }

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

  Future<void> dispose() async {
    await close();
    if (_serialPtr != null) {
      _bindings.serial_free(_serialPtr!);
      _serialPtr = null;
    }
    _eventController.close();
  }

  static Future<List<SerialPortInfo>> availablePorts() async {
    return SerialScanner.getAvailablePorts();
  }
}
