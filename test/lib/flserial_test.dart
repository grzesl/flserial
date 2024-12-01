import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:flserial/flserial.dart';

void main() {

  if (kReleaseMode) {
    // I'm on release mode, absolute linking
    final String local_lib = path.join('data',  'flutter_assets', 'assets', 'flserial.dll');
    String pathToLib = path.join(Directory(Platform.resolvedExecutable).parent.path, local_lib);
    DynamicLibrary.open(pathToLib);
  } else {
    // I'm on debug mode, local linking
    var path = Directory.current.path;
    DynamicLibrary.open('$path/assets/flserial.dll');
  }
  
  test('FLSerial status should be closed', () {
    final port = FlSerial();

    port.init();

    FLOpenStatus status = port.isOpen();

    expect(status, FLOpenStatus.closed);

    port.free();


  });
}