import 'package:flserial/flserial_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flserial/flserial.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _errorMsg = 'Unknown';
  final _flserialPlugin = FlSerial();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            ElevatedButton(
                onPressed: () {
                  try {
                    _flserialPlugin.init();
                    _flserialPlugin.openPort(
                        FlSerial.listPorts()[0].split(" - ")[0], 115200);
                    _flserialPlugin.onSerialData.stream.listen(
                      (args) {
                        if (args.len > 0) {
                          setState(() {
                            _errorMsg = args.serial.readList().toString();
                          });
                        }
                      },
                    );

                    String msg = "Hello World!";
                    var list = msg.codeUnits;
                    _flserialPlugin.write(Uint8List.fromList(list));
                    setState(() {
                      _errorMsg = "Test OK";
                    });
                  } on FlSerialException catch (e) {
                    setState(() {
                      _errorMsg = e.msg;
                    });
                  } on Exception catch (ex) {
                    setState(() {
                      _errorMsg = ex.toString();
                    });
                  } finally {
                    if (_flserialPlugin.isOpen() == FlOpenStatus.open) {
                      _flserialPlugin.closePort();
                    }
                    _flserialPlugin.free();
                  }
                },
                child: const Text("Serial port test")),
            Center(
              child: Text('Message: $_errorMsg\n'),
            ),
          ],
        ),
      ),
    );
  }
}
