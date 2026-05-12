import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flserial/flserial_port_bindings.dart';
import 'package:flserial/serial_scanner.dart';

/// Typy zdarzeń przesyłanych z C++ do Darta
enum SerialEventType {
  data(0),
  connected(1),
  disconnected(2),
  lineStatusChanged(3),
  error(4);

  final int value;
  const SerialEventType(this.value);
  static SerialEventType? fromInt(int i) =>
      i >= 0 && i < SerialEventType.values.length ? SerialEventType.values[i] : null;
}

/// Struktura zdarzenia portu szeregowego
class SerialEvent {
  final SerialEventType type;
  final dynamic data;
  SerialEvent(this.type, this.data);
}

/// Parametry otwarcia portu
class SerialConfig {
  int baudRate;
  int dataBits; // 5, 6, 7, 8
  int stopBits; // 1, 2
  int parity; // 0: none, 1: odd, 2: even
  int flowControl; // 0: none, 1: RTS/CTS, 2: XON/XOFF

  SerialConfig({
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
    this.flowControl = 0,
  });
}

class FlSerial {
  late FLSerialBindings _bindings;
  ffi.Pointer<SerialPort>? _serialPtr;

  ReceivePort? _receivePort;
  StreamSubscription? _subscription;

  // Kontroler zdarzeń (Strumień główny)
  final _eventController = StreamController<SerialEvent>.broadcast();
  Stream<SerialEvent> get events => _eventController.stream;

  // Helper dla samych danych (kompatybilność z poprzednim kodem)
  Stream<Uint8List> get dataStream => events
      .where((e) => e.type == SerialEventType.data)
      .map((e) => e.data as Uint8List);

  FlSerial() {
    _initNative();
  }

  void _initNative() {
    final _libName = 'flserial';

    final DynamicLibrary dylib = () {
      try {
        if (Platform.isMacOS || Platform.isIOS) {
          return DynamicLibrary.open('$_libName.framework/$_libName');
        }
        if (Platform.isAndroid || Platform.isLinux) {
          return DynamicLibrary.open('lib$_libName.so');
        }
        if (Platform.isWindows) {
          return DynamicLibrary.open('$_libName.dll');
        }
        throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
      } catch (e) {
        throw UnsupportedError('flserial: nie można załadować biblioteki natywnej: $e');
      }
    }();

    _bindings = FLSerialBindings(dylib);

    // Inicjalizacja Dart VM API
    if (_bindings.InitDartApiDL(ffi.NativeApi.initializeApiDLData) != 0) {
      throw Exception("FFI: InitDartApiDL failed");
    }

    _serialPtr = _bindings.serial_new();
  }

  /// Otwiera port z pełną konfiguracją
  bool open(String path, SerialConfig config) {
    _stopSession();

    _receivePort = ReceivePort();
    _subscription = _receivePort!.listen(_handleNativeMessage);

    final pathPtr = path.toNativeUtf8();
    try {
      _bindings.register_port(_serialPtr!, _receivePort!.sendPort.nativePort);

      // Zakł\adamy rozszerzoną funkcję w C++: serial_open_ext
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

  /// Obsługa wiadomości z NativePort (C++)
  void _handleNativeMessage(dynamic msg) {
    if (msg is Uint8List) {
      _eventController.add(SerialEvent(SerialEventType.data, msg));
    } else if (msg is List && msg.isNotEmpty) {
      final type = SerialEventType.fromInt(msg[0] as int);
      if (type == null) return;

      // Jeśli to zmiana linii, msg[1] to int (maska bitowa z C++)
      if (type == SerialEventType.lineStatusChanged && msg.length > 1) {
        final int mask = msg[1] as int;
        final Map<String, bool> statusMap = {
          'CTS': (mask & 0x01) != 0,
          'DSR': (mask & 0x02) != 0,
          'RI': (mask & 0x04) != 0,
          'DCD': (mask & 0x08) != 0,
        };
        _eventController.add(SerialEvent(type, statusMap));
      } else {
        // Inne eventy (Connected, Disconnected)
        _eventController.add(SerialEvent(type, msg.length > 1 ? msg[1] : null));
      }
    }
  }

  // --- STEROWANIE LINIAMI MODEMOWYMI ---

  /// Ustawia linię DTR (Data Terminal Ready)
  void setDTR(bool active) {
    if (_serialPtr != null) {
      _bindings.serial_set_dtr(_serialPtr!, active ? 1 : 0);
    }
  }

  /// Ustawia linię RTS (Request To Send)
  void setRTS(bool active) {
    if (_serialPtr != null) {
      _bindings.serial_set_rts(_serialPtr!, active ? 1 : 0);
    }
  }

  /// Pobiera aktualny stan linii wejściowych (CTS, DSR, RI, DCD)
  /// Zwraca mapę flag lub rzuca błąd jeśli port zamknięty
  Map<String, bool> getModemStatus() {
    if (_serialPtr == null) return {};
    final int status = _bindings.serial_get_modem_status(_serialPtr!);
    return {
      'CTS': (status & 0x01) != 0, // Clear To Send
      'DSR': (status & 0x02) != 0, // Data Set Ready
      'RI': (status & 0x04) != 0, // Ring Indicator
      'DCD': (status & 0x08) != 0, // Data Carrier Detect
    };
  }

  // --- FUNKCJE POMOCNICZE ---

  void write(Uint8List data) {
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
    if (_serialPtr != null) _bindings.serial_close(_serialPtr!);
    await Future.delayed(Duration.zero);
    _stopSession();
  }

  void _stopSession() {
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

  /// Statyczna metoda skanująca dostępne porty w systemie
  static Future<List<SerialPortInfo>> availablePorts() async {
    return SerialScanner.getAvailablePorts();
  }
}
