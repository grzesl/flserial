import 'dart:ffi';
import 'package:test/test.dart';
import 'package:flserial/flserial.dart';

void main() {
  DynamicLibrary.open('libflserial.so');
  //'/home/runner/work/flserial/flserial/build/linux/x64/release/shared/libflserial.so');

  test('FLSerial status should be closed', () {
    final port = FlSerial();

    port.init();

    FLOpenStatus status = port.isOpen();

    expect(status, FLOpenStatus.closed);

    port.free();
  });
}
