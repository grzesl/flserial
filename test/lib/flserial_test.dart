import 'dart:ffi';
import 'dart:io';
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
      return DynamicLibrary.open(libPath);
      //return DynamicLibrary.open('${libPath}lib$libName.so');
    }
    if (Platform.isWindows) {
      String basedir = Directory.current.path;
      libPath =  '$basedir/build/windows/x64/release/shared/flserial.dll'; 
      return DynamicLibrary.open(libPath);
    }
    throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
  }();
  //'/home/runner/work/flserial/flserial/build/linux/x64/release/shared/libflserial.so');

  test('FLSerial status should be closed', () {
    
    final port = FlSerial();

    port.init();

    FLOpenStatus status = port.isOpen();

    expect(status, FLOpenStatus.closed);

    port.free();
  });
}
