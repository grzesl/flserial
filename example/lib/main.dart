import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  late int sumResult = 0;
  late FlSerial serial;
  String resultMsg = "Try to use button";
  @override
  void initState() {
    super.initState();
    serial = FlSerial();
    serial.init();
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Native Packages'),
        ),
        body: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                TextButton(onPressed: () {

                if (serial.openPort("COM3", 115200) == fLOpenStatus.Error)
                {

                  setState(() {
                    resultMsg = "Port not open because error " + serial.getLastError();
                  });

                  serial.closePort(); // free
                } else {
                 int wrt = serial.write(1, Uint8List.fromList({0x10}.toList()));

                 if (wrt > 0) {
                  Uint8List read = serial.read(1);
                  if(read.isNotEmpty ) {
                    print(read);
                  }
                  setState(() {
                    resultMsg = "Success read byte: " + read.toString();
                  });
                 }

                 serial.closePort();                
                }
                  
                }, child: const Text("Run serial test")),
                Text(resultMsg,
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                spacerSmall,
                Text(
                  'sum(1, 2) = $sumResult',
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
                spacerSmall,
             
              ],
            ),
          ),
        ),
      ),
    );
  }
}
