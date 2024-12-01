# flserial
Flutter Serial Port Plugin FFI based on great C library. Useful to communicate with RS232 devices.

Supported platforms:
- Linux
- Windows
- Android

Example of usage:


```
    FlSerial serial = FlSerial();
    serial.openPort("COM3", 9600);
    serial.onSerialData.subscribe(
      (args) {
        if (args != null && args.len > 0) {
          print(serial.readList());
        }
      },
    );

    serial.setByteSize8();
    serial.setByteParityNone(); 
    serial.setStopBits1();
    serial.setFlowControlNone();

    String msg = "Hello World!";
    var list = msg.codeUnits;
    serial.write(list.length, Uint8List.fromList(list) );


```
Based on great serial library: https://github.com/wjwwood/serial

Licensed under MIT