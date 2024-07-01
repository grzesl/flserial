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
  late FlSerial serial;
  String resultMsg = "Try to use button";
  int totalLen = 0;
  int readTime = 0;
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
                  
                if(serial.isOpen() == FLOpenStatus.open)
                {
                  setState(() {
                    resultMsg = "Port allready open...";
                    totalLen = 0;
                  });
                }
                else if (serial.openPort("COM3", 115200) == FLOpenStatus.error)
                {

                  setState(() {
                    resultMsg = "Port not open because error ${serial.getLastError()}";
                  });

                  serial.closePort(); // free
                } else {

                  serial.onSerialData.subscribe((args) {
                    int duration = serial.getTickCount() - readTime;
                    var list  = serial.readList();

                    setState(() {
                    totalLen += list.length;
                    resultMsg += "Serial port read: $list time: $duration [ms] len: ${list.length} [B] total: $totalLen";
                  });
                 },);

                  setState(() {
                    resultMsg = "Port open";
                  });

                }
                }, child: Text("Otwórz port")),
                TextButton(onPressed: () {

                if(serial.isOpen() == FLOpenStatus.open) {


                 Uint8List send = Uint8List(1000);
                 for (int i=0;i< 1000;i++)
                 {
                  send[i] = 0x10;
                 }
                 serial.write(send.length, send);     
                 readTime = serial.getTickCount();            
                }
                  
                }, child: const Text("Run serial test")),
                Text(resultMsg,
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
