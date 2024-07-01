
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'dart:io';
import 'flserial_bindings_generated.dart';
import 'package:event/event.dart';

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
  FlSerialEventArgs(len, dataRecivied);
  int len = 0;
  Uint8List dataRecivied = Uint8List(0);
}


class FlSerial {
  int flh = -1;
  List<int> readBuff = List.empty(growable: true);
  late Timer _timer;
  Event<FlSerialEventArgs> onSerialData = Event<FlSerialEventArgs>();

  int init () {
    return _bindings.fl_init(1);
  }
 
  FLOpenStatus openPort(String portname, int baudrate) {
    onSerialData = Event<FlSerialEventArgs>();
    flh = _bindings.fl_open(flh, stringToNativeInt8(portname), baudrate);
    return isOpen();
  }


  FLOpenStatus isOpen() {

    if(flh < 0) {
      return FLOpenStatus.closed;
    }    

    int error = _bindings.fl_ctrl(flh, flCtrl.FL_CTRL_LAST_ERROR, -1);
    if(error > 0) {
      return FLOpenStatus.error;
    }
    int nres = _bindings.fl_ctrl(flh, flCtrl.FL_CTRL_IS_PORT_OPEN, -1);
    if(nres == 0) {
      return FLOpenStatus.closed;
    }


    _timer = Timer.periodic(Duration(milliseconds: 100), (timer) async {
      await _readProcess();
      if(readBuff.isNotEmpty) {
        onSerialData.broadcast(FlSerialEventArgs(readBuff.length, Uint8List(0) /*readBuff.toList()*/));
    }
    },);
    
    return FLOpenStatus.open;
  }

  String getLastError() {
    int res  = _bindings.fl_ctrl(flh, flCtrl.FL_CTRL_LAST_ERROR, -1);
    String strres = "";

    switch(res) {
      case flError.FL_ERROR_OK:
        strres = "0: None";
        break;
      case flError.FL_ERROR_PORT_ALLREADY_OPEN:
        strres = "$res: Port allready open";
        break;
      default:
        strres = "-1: Unknow error";
        break;
    }
    return strres;
  }

  Future<int> _readProcess() async {
    Uint8List list = await _readList(64);
    readBuff.addAll(list);
    return readBuff.length;
  }

  Uint8List _readList(int len) {
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
    Uint8List old = Uint8List(0);
    if (readBuff.isNotEmpty) {
      var len = readBuff.length;
      old = Uint8List.fromList(readBuff.sublist(0, len));
      readBuff.removeRange(0, len);

    } 
    return old;
  }

  int read() {
    if (readBuff.isNotEmpty) {
      return readBuff.removeAt(0);
    }
    return -1;
  }

  int write(int len, Uint8List data) {
    return _bindings.fl_write(flh,  len, int8ListToPointerInt8(data));
  }

  int closePort() {
    _timer.cancel();
    return _bindings.fl_close(flh);
  }

  int ctrl(int cmd, int value) {
    return _bindings.fl_ctrl(flh,cmd,value);
  }

  int free() {
    return _bindings.fl_free();
  }

  int getTickCount() {
    return new DateTime.now().millisecond;
  }


}