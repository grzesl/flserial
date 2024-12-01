import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:test/test.dart';
import 'package:flserial/flserial.dart';

void main() {
  const String libName = 'flserial';
  String libPath = ''; 

  /// The dynamic library in which the symbols for [FlserialBindings] can be found.
  final DynamicLibrary dylib = () {
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.open('$libPath$libName.framework/$libName');
    }
    if (Platform.isAndroid || Platform.isLinux) {
      libPath = '/home/runner/work/flserial/flserial/build/linux/x64/release/shared/libflserial.so'; 
      DynamicLibrary.open(libPath);
      //return DynamicLibrary.open('${libPath}lib$libName.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('$libPath$libName.dll');
    }
    throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
  }();
  //'/home/runner/work/flserial/flserial/build/linux/x64/release/shared/libflserial.so');

  test('FLSerial status should be closed', () {

    if (kDebugMode) {
      print(dylib.toString());
    }

    final port = FlSerial();

    port.init();

    FLOpenStatus status = port.isOpen();

    expect(status, FLOpenStatus.closed);

    port.free();
  });
}
