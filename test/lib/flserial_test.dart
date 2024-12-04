import 'dart:ffi';
import 'dart:io';
import 'package:flserial/flserial_bindings_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart';
import 'package:flserial/flserial.dart';

void main() {
  const String _libName = 'flserial';

  /// The dynamic library in which the symbols for [FlserialBindings] can be found.
  final DynamicLibrary _dylib = () {
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
  }();

  /// The bindings to the native functions in [_dylib].
  final FlserialBindings _bindings = FlserialBindings(_dylib);
  //'/home/runner/work/flserial/flserial/build/linux/x64/release/shared/libflserial.so');

  test('FLSerial status should be closed', () {
    final port = FlSerial();

    port.init();

    FlOpenStatus status = port.isOpen();

    expect(status, FlOpenStatus.closed);

    port.free();
  });
}
