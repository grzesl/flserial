/// Event types emitted by [FlSerial.events].
enum SerialEventType {
  /// Raw bytes received from the device.
  /// [SerialEvent.data] is a `Uint8List`.
  data(0),

  /// The port was successfully opened.
  connected(1),

  /// The port was closed, either by calling [FlSerial.close] or because the
  /// device was physically disconnected.
  disconnected(2),

  /// One or more modem control lines (CTS, DSR, RI, DCD) changed state.
  /// [SerialEvent.data] is a `Map<String, bool>` with keys
  /// `'CTS'`, `'DSR'`, `'RI'`, `'DCD'`.
  lineStatusChanged(3),

  /// A transport-level error occurred.
  /// [SerialEvent.data] may contain a descriptive string.
  error(4);

  /// Integer wire value used when the native layer sends event codes.
  final int value;
  const SerialEventType(this.value);

  /// Returns the [SerialEventType] corresponding to [i], or `null` if [i] is
  /// out of range.
  static SerialEventType? fromInt(int i) =>
      i >= 0 && i < SerialEventType.values.length
          ? SerialEventType.values[i]
          : null;
}

/// A single event emitted on the [FlSerial.events] stream.
///
/// ```dart
/// serial.events.listen((event) {
///   if (event.type == SerialEventType.data) {
///     final bytes = event.data as Uint8List;
///   }
/// });
/// ```
class SerialEvent {
  /// The kind of event.
  final SerialEventType type;

  /// Event payload — type depends on [type]:
  ///
  /// | type | data |
  /// |------|------|
  /// | [SerialEventType.data] | `Uint8List` |
  /// | [SerialEventType.lineStatusChanged] | `Map<String, bool>` |
  /// | others | `null` |
  final dynamic data;

  /// Creates a [SerialEvent] with the given [type] and optional [data].
  SerialEvent(this.type, this.data);
}

/// Port configuration passed to [FlSerial.open].
///
/// All parameters are optional and default to the most common RS-232 settings
/// (115200 8N1, no flow control).
///
/// ```dart
/// final config = SerialConfig(
///   baudRate: 9600,
///   parity: 2,       // even
///   flowControl: 1,  // RTS/CTS
/// );
/// ```
class SerialConfig {
  /// Baud rate in bits per second. Common values: 9600, 19200, 38400, 57600,
  /// 115200, 230400, 460800, 921600.
  int baudRate;

  /// Number of data bits per frame: 5, 6, 7, or 8.
  int dataBits;

  /// Number of stop bits: 1 or 2.
  int stopBits;

  /// Parity mode:
  /// * `0` — none
  /// * `1` — odd
  /// * `2` — even
  int parity;

  /// Flow control mode:
  /// * `0` — none
  /// * `1` — hardware RTS/CTS
  /// * `2` — software XON/XOFF (not supported on Web)
  int flowControl;

  /// Creates a [SerialConfig] with sensible defaults (115200 8N1, no flow
  /// control).
  SerialConfig({
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
    this.flowControl = 0,
  });
}
