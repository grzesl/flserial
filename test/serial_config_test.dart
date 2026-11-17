import 'package:flserial/src/serial_types.dart';
import 'package:test/test.dart';

void main() {
  test('DTR and RTS are asserted by default (previous behaviour)', () {
    final config = SerialConfig();
    expect(config.dtr, isTrue);
    expect(config.rts, isTrue);
  });

  test('DTR and RTS can be released on open', () {
    final config = SerialConfig(dtr: false, rts: false);
    expect(config.dtr, isFalse);
    expect(config.rts, isFalse);
    expect(config.baudRate, 115200);
  });
}
