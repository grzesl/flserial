import 'dart:async';
import 'dart:typed_data';
import 'package:flserial/serial_scanner.dart';
import 'serial_types.dart';
import 'web_serial.dart' hide SerialPortInfo, SerialPort, SerialOptions;

export 'serial_types.dart';

class FlSerial {
  final _eventController = StreamController<SerialEvent>.broadcast();
  Stream<SerialEvent> get events => _eventController.stream;

  Stream<Uint8List> get dataStream => events
      .where((e) => e.type == SerialEventType.data)
      .map((e) => e.data as Uint8List);

  String? _webPath;
  StreamSubscription? _webDataSub;

  FlSerial();

  /// Opens a port via the Web Serial API.
  /// Use "web:N" for a previously-granted port or "web:request" to prompt the user.
  Future<bool> open(String path, SerialConfig config) async {
    _stopSession();

    final ok = await openWebPort(
      path,
      baudRate: config.baudRate,
      dataBits: config.dataBits,
      stopBits: config.stopBits,
      parity: config.parity,
      flowControl: config.flowControl,
    );
    if (!ok) return false;

    _webPath = path;
    _webDataSub = webDataStream(path)?.listen((bytes) {
      _eventController.add(SerialEvent(SerialEventType.data, bytes));
    });
    _eventController.add(SerialEvent(SerialEventType.connected, null));
    return true;
  }

  void write(Uint8List data) {
    if (_webPath != null) writeWebPort(_webPath!, data);
  }

  Future<void> close() async {
    final path = _webPath;
    _stopSession();
    if (path != null) await closeWebPort(path);
    _eventController.add(SerialEvent(SerialEventType.disconnected, null));
  }

  void _stopSession() {
    _webDataSub?.cancel();
    _webDataSub = null;
    _webPath = null;
  }

  Future<void> dispose() async {
    await close();
    _eventController.close();
  }

  // Web Serial does not expose modem control lines
  void setDTR(bool active) {}
  void setRTS(bool active) {}
  Map<String, bool> getModemStatus() =>
      {'CTS': false, 'DSR': false, 'RI': false, 'DCD': false};

  static Future<List<SerialPortInfo>> availablePorts() =>
      SerialScanner.getAvailablePorts();
}
