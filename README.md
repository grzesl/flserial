# flserial
Flutter Serial Port Plugin FFI based on great C library. Useful to communicate with RS232 devices.

Supported platforms:
- Linux
- Windows
- Android


Example of usage:


```
    FlSerial serial = FlSerial();
    serial.init();
    serial.openPort("COM3", 9600);
    serial.onSerialData.stream.listen(
      (args) {
        if (args.len > 0) {
          print(args.serial.readList());
        }
      },
    );

    serial.setByteSize8();
    serial.setByteParityNone(); 
    serial.setStopBits1();
    serial.setFlowControlNone();

    String msg = "Hello World!";
    var list = msg.codeUnits;
    serial.write(Uint8List.fromList(list));

    serial.closePort();
    serial.free();


```
Based on great serial library: https://github.com/wjwwood/serial

Licensed under MIT