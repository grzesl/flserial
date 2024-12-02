
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:event/event.dart';
import 'package:ffi/ffi.dart';

import 'package:flserial/flserial_exception.dart';

import 'flserial_bindings_generated.dart';

const String _libName = 'flserial';

/// The dynamic library in which the symbols for [FlserialBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final FlserialBindings _bindings = FlserialBindings(_dylib);


String nativeInt8ToString(Pointer<Int8> pointer, {bool allowMalformed = true}) {
  var ptrName = pointer.cast<Utf8>();
  final ptrNameCodeUnits = pointer.cast<Uint8>();
  var list = ptrNameCodeUnits.asTypedList(ptrName.length);
  return utf8.decode(list, allowMalformed: allowMalformed);
}

Pointer<Char> stringToNativeInt8(String str, {Allocator allocator = calloc}) {
  final units = utf8.encode(str);
  final result = allocator<Uint8>(units.length + 1);
  final nativeString = result.asTypedList(units.length + 1);
  nativeString.setAll(0, units);
  nativeString[units.length] = 0;
  return result.cast<Char>();
}

Pointer<Char> int8ListToPointerInt8(Uint8List units,
    {Allocator allocator = calloc}) {
  final pointer = allocator<Uint8>(units.length + 1); //blob
  final nativeString = pointer.asTypedList(units.length + 1); //blobBytes
  nativeString.setAll(0, units);
  nativeString[units.length] = 0;
  return pointer.cast<Char>();
}

Int8List nativeInt8ToInt8List(Pointer<Int8> pointer) {
  var ptrName = pointer.cast<Utf8>();
  final ptrNameCodeUnits = pointer.cast<Int8>();
  var list = ptrNameCodeUnits.asTypedList(ptrName.length);
  return list;
}

enum FLOpenStatus {
  open,
  closed,
  error,
}

class FlSerialEventArgs extends EventArgs {
  FlSerialEventArgs(this.len, this.dataRecivied, this.cts, this.dsr);
  final int len;
  final Uint8List dataRecivied;
  final bool cts , dsr;
}


class FlSerial {
  int flh = -1;
  List<int> readBuff = List.empty(growable: true);
  late Timer _timer;
  var onSerialData = Event<FlSerialEventArgs>();
  bool prevCTS = false;
  bool prevDSR = false;

  int init () {
    return _bindings.fl_init(16);
  }

  static List<String>  listPorts() {
    List<String> list = List<String>.empty(growable: true);

    Allocator allocator = calloc;
    var result = allocator<Char>(1024);

    for(int i=0;i < 255;i++){

      int len = _bindings.fl_ports(i, 1024, result);
     if(  len > 0)
     {
      String resultStr = result.cast<Utf8>()
        .toDartString(length: len);
      list.add(resultStr);
     } else {
      break;
     }
    }
    return  list;
  }

  int _checkFLH(int handler) {
    if (handler >=0 && handler < MAX_PORT_COUNT){
      return FlError.FL_ERROR_OK;
    }
    throw FlserialException(FlError.FL_ERROR_HANDLER);
  }
 
  FLOpenStatus openPort(String portname, int baudrate) {
    onSerialData = Event<FlSerialEventArgs>();
    prevCTS = false;
    prevDSR = false;
    flh = _bindings.fl_open(flh, stringToNativeInt8(portname), baudrate);
    return isOpen();
  }


  FLOpenStatus isOpen() {

    if(flh < 0) {
      return FLOpenStatus.closed;
    }    

    int error = _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_LAST_ERROR, -1);
    if(error > 0) {
      return FLOpenStatus.error;
    }
    int nres = _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_IS_PORT_OPEN, -1);
    if(nres == 0) {
      return FLOpenStatus.closed;
    }

    bool isFirstRun = true;
    _timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (timer) async {
        if (flh < 0) {
          _timer.cancel();
          return;
        }
        
        if(isFirstRun) {
          isFirstRun = false;
          return;
        }

        int read = await  _readProcess();
        
        if (read > 0) {
          onSerialData.broadcast(FlSerialEventArgs(
              readBuff.length, Uint8List(0), prevCTS, prevDSR));
        }
      },
    );
    
    return FLOpenStatus.open;
  }

  String getLastError() {

    _checkFLH(flh);

    int res  = _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_LAST_ERROR, -1);
    String strres = "";

    switch(res) {
      case FlError.FL_ERROR_OK:
        strres = "0: None";
        break;
      case FlError.FL_ERROR_PORT_ALLREADY_OPEN:
        strres = "$res: Port allready open";
        break;
      default:
        strres = "-1: Unknow error";
        break;
    }
    return strres;
  }

  Future<int> _readProcess() async {
    _checkFLH(flh);
    await _readLineStatus();

    Uint8List list = await _readList(1024);
     
    readBuff.addAll(list);
    return Future<int>.value( readBuff.length );
  }

  Future<int> _readLineStatus() async {

    return 0;

    _checkFLH(flh);

    bool currCTS = getCTS();
    bool currDSR = getDSR();
    if(currCTS != prevCTS || prevDSR != currDSR)
    {
      prevCTS = currCTS;
      prevDSR = currDSR;

      onSerialData.broadcast(FlSerialEventArgs(
              readBuff.length, Uint8List(0), currCTS, currDSR));
    }
    return 0;
  }

  Future< Uint8List> _readList(int len) async  {
    _checkFLH(flh);

    Allocator allocator = calloc;
    var result = allocator<Char>(len);
    int intres = _bindings.fl_read(flh, len, result);

    if(intres <=0) {
      return Uint8List(0);
    }
      
    final ptrNameCodeUnits = result.cast<Uint8>();
    var list = ptrNameCodeUnits.asTypedList(intres);
    return list;
  }

  Uint8List readList() {
    return readListLen(readBuff.length);
  }

  Uint8List readListLen(int len) {
    _checkFLH(flh);

    Uint8List old = Uint8List(0);
    if (readBuff.isNotEmpty) {
      if(len > readBuff.length){
        len = readBuff.length;
      }
      old = Uint8List.fromList(readBuff.sublist(0, len));
      readBuff.removeRange(0, len);
    } 
    return old;
  }

  int read() {
    _checkFLH(flh);

    if (readBuff.isNotEmpty) {
      return readBuff.removeAt(0);
    }
    return -1;
  }

  int write(int len, Uint8List data) {
    _checkFLH(flh);

    return _bindings.fl_write(flh,  len, int8ListToPointerInt8(data));
  }

  int closePort() {
    _checkFLH(flh);
    sleep(const Duration(milliseconds: 1));
    _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_BREAK, 0);
    _bindings.fl_close(flh);
     flh = -1;
    return flh;
  }

  int ctrl(int cmd, int value) {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh,cmd,value);
  }

  int setRTS(bool value){
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh,FlCtrl.FL_CTRL_SET_RTS,value?1:0);
  }

  bool getCTS() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_GET_CTS, 0) > 0 ? true : false;
  }

  int setDTR(bool value) {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_DTR, value ? 1 : 0);
  }

  bool getDSR() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_GET_DSR, 0) > 0 ? true : false;
  }

  int setByteSize5() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_BYTESIZE_5, 0);
  }

  int setByteSize6() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_BYTESIZE_6, 0);
  }

  int setByteSize7() {
    _checkFLH(flh);     
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_BYTESIZE_7, 0);
  }

  int setByteSize8() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_BYTESIZE_8, 0);
  }

  int setByteParityNone() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_PARITY_NONE, 0);
  }

  int setByteParityOdd() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_PARITY_ODD, 0);
  }

  int setByteParityEven() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_PARITY_EVEN, 0);
  }

  int setByteParityMark() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_PARITY_MARK, 0);
  }

  int setByteParitySpace() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_PARITY_SPACE, 0);
  }

  int setStopBits1() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_STOPBITS_ONE, 0);
  }

  int setStopBits1_5() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(
        flh, FlCtrl.FL_CTRL_SET_STOPBITS_ONE_POINT_FIVE, 0);
  }

  int setStopBits2() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_STOPBITS_TWO, 0);
  }

  int setFlowControlNone() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_FLOWCONTROL_NONE, 0);
  }

  int setFlowControlHardware() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_FLOWCONTROL_HARDWARE, 0);
  }

  int setFlowControlSoftware() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_SET_FLOWCONTROL_SOFTWARE, 0);
  }

  int setWaitStatusChange() {
    _checkFLH(flh);
    return _bindings.fl_ctrl(flh, FlCtrl.FL_CTRL_GET_STATUS_CHANGE, 0);
  }

  int free() {
    return _bindings.fl_free();
  }

  int getTickCount() {
    return DateTime.now().millisecond;
  }
}