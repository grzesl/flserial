enum SerialEventType {
  data(0),
  connected(1),
  disconnected(2),
  lineStatusChanged(3),
  error(4);

  final int value;
  const SerialEventType(this.value);
  static SerialEventType? fromInt(int i) =>
      i >= 0 && i < SerialEventType.values.length
          ? SerialEventType.values[i]
          : null;
}

class SerialEvent {
  final SerialEventType type;
  final dynamic data;
  SerialEvent(this.type, this.data);
}

class SerialConfig {
  int baudRate;
  int dataBits; // 5, 6, 7, 8
  int stopBits; // 1, 2
  int parity;   // 0: none, 1: odd, 2: even
  int flowControl; // 0: none, 1: RTS/CTS, 2: XON/XOFF

  SerialConfig({
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
    this.flowControl = 0,
  });
}
