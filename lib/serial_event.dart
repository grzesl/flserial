enum SerialEventType { data, connected, disconnected, lineStatusChanged }

class SerialEvent {
  final SerialEventType type;
  final dynamic data;
  SerialEvent(this.type, this.data);
}
