import 'package:flserial/flserial_bindings_generated.dart';

class FlserialException implements Exception {
  FlserialException(error);
  int error = FlError.FL_ERROR_OK;
}