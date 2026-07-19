import 'dart:async';
import 'dart:typed_data';

bool get webSerialAvailable => false;

typedef WebPortDesc = ({String path, String description});

Future<WebPortDesc?> requestWebPort() async => null;

Future<List<WebPortDesc>> listWebPorts() async => [];

Future<bool> openWebPort(
  String path, {
  required int baudRate,
  int dataBits = 8,
  int stopBits = 1,
  int parity = 0,
  int flowControl = 0,
}) async =>
    false;

Stream<Uint8List>? webDataStream(String path) => null;

void writeWebPort(String path, Uint8List data) {}

Future<void> closeWebPort(String path) async {}
