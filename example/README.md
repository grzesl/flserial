# flserial_example

Demonstrates how to use the flserial plugin.



```
import 'package:flserial/flserial.dart';

late  FlSerial serial;

(...)
 @override
  void initState() {
    super.initState();
    serial = FlSerial();
    serial.init();
  }
(...)

if(serial.openPort("COM3", 115200) == FLOpenStatus.open)
{
                    serial.onSerialData.subscribe((args) {
                        var list  = serial.readList();
                        resultMsg += "Serial port read: $list time: $duration [ms] len: ${list.length} [B] total: $totalLen CTS: ${args!.cts} DSR: ${args.dsr}\n";
                    });

                    Uint8List send = Uint8List(1);
                    send[0] = 0x10;
                    serial.write(send.length, send);  
},);

}

```