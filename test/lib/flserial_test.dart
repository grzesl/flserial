import 'dart:ffi';
import 'dart:io';

import 'package:flserial/flserial.dart';
import 'package:flutter/foundation.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as Path;

void main() {

  if (kReleaseMode) {
    // I'm on release mode, absolute linking
    final String local_lib = Path.join('data',  'flutter_assets', 'assets', 'flserial.dll');
    String pathToLib = Path.join(Directory(Platform.resolvedExecutable).parent.path, local_lib);
    DynamicLibrary lib = DynamicLibrary.open(pathToLib);
  } else {
    // I'm on debug mode, local linking
    var path = Directory.current.path;
    DynamicLibrary lib = DynamicLibrary.open('$path/assets/flserial.dll');
  }
  
  test('FLSerial status should be closed', () {
    final port = FlSerial();

    port.init();

    FLOpenStatus status = port.isOpen();

    expect(status, FLOpenStatus.closed);

    port.free();


  });
}