import 'dart:async';
import 'dart:typed_data';
import 'package:flserial/serial_scanner.dart';
import 'serial_types.dart';
import 'web_serial.dart' hide SerialPortInfo, SerialPort, SerialOptions;

export 'serial_types.dart';

/// Asynchronous serial port driver for Flutter — **web implementation**.
///
/// Uses the [Web Serial API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Serial_API)
/// via `dart:js_interop`. Requires Chrome 89+ or Edge 89+.
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
/// // "Web Serial Port" is always listed; opening it shows the port picker.
/// final ports = await FlSerial.availablePorts();
/// await serial.open(ports.first.path, SerialConfig(baudRate: 115200));
/// serial.write(Uint8List.fromList('hello\n'.codeUnits));
/// await serial.close();
/// await serial.dispose();
/// ```
///
/// ## Port picker
///
/// [availablePorts] always returns a single synthetic entry with path
/// `web:request`. Passing it to [open] triggers `navigator.serial.requestPort()`
/// which shows the browser's native device-picker dialog. This requires a
/// user gesture — a button tap qualifies.
class FlSerial {
  final _eventController = StreamController<SerialEvent>.broadcast();

  /// Broadcast stream of all port events (connect, disconnect, data).
  ///
  /// Subscribe before calling [open] to avoid missing the initial
  /// [SerialEventType.connected] event.
  Stream<SerialEvent> get events => _eventController.stream;

  /// Convenience stream that emits only raw received bytes.
  Stream<Uint8List> get dataStream => events
      .where((e) => e.type == SerialEventType.data)
      .map((e) => e.data as Uint8List);

  String? _webPath;
  StreamSubscription? _webDataSub;

  /// Creates a new [FlSerial] instance.
  FlSerial();

  /// Opens a Web Serial port selected via the browser's port-picker dialog.
  ///
  /// [path] should be `web:request` (as returned by [availablePorts]).
  /// The browser picker is shown and the returned [Future] resolves once the
  /// user confirms the selection and the port is opened.
  ///
  /// Returns `true` on success, `false` if the user cancels or the port
  /// cannot be opened.
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

  /// Sends [data] to the open port (fire-and-forget).
  ///
  /// Has no effect if no port is open.
  void write(Uint8List data) {
    if (_webPath != null) writeWebPort(_webPath!, data);
  }

  /// Closes the currently open port and emits [SerialEventType.disconnected].
  ///
  /// Safe to call even if no port is open.
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

  /// Closes the port and releases all resources.
  ///
  /// The instance must not be used after calling [dispose].
  Future<void> dispose() async {
    await close();
    _eventController.close();
  }

  /// No-op on web — the Web Serial API does not expose DTR.
  void setDTR(bool active) {}

  /// No-op on web — the Web Serial API does not expose RTS.
  void setRTS(bool active) {}

  /// Always returns all-false on web — modem control lines are not accessible
  /// via the Web Serial API.
  Map<String, bool> getModemStatus() =>
      {'CTS': false, 'DSR': false, 'RI': false, 'DCD': false};

  /// Returns all serial ports currently visible on this device.
  ///
  /// On web, always returns a single `"Web Serial Port"` entry whose path is
  /// `web:request`. Passing that path to [open] shows the browser picker.
  static Future<List<SerialPortInfo>> availablePorts() =>
      SerialScanner.getAvailablePorts();
}
