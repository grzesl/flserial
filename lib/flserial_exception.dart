
/// Exception class for serial port
class FlserialException implements Exception {
  FlserialException(this.error, {required this.msg});
  final int error;
  final String msg;
}