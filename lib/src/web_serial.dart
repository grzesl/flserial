import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

// ── JS interop bindings ─────────────────────────────────────────────────────

@JS('navigator.serial')
external Serial? get _serial;

@JS()
extension type Serial._(JSObject _) implements JSObject {
  external JSPromise<JSArray<SerialPort>> getPorts();
  external JSPromise<SerialPort> requestPort();
}

@JS()
extension type SerialPort._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open(SerialOptions options);
  external JSPromise<JSAny?> close();
  external ReadableStream get readable;
  external WritableStream get writable;
  external SerialPortInfo getInfo();
}

@JS()
extension type SerialOptions._(JSObject _) implements JSObject {
  external factory SerialOptions({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required String parity,
    required String flowControl,
  });
}

@JS()
extension type SerialPortInfo._(JSObject _) implements JSObject {
  external int? get usbVendorId;
  external int? get usbProductId;
}

@JS()
extension type ReadableStream._(JSObject _) implements JSObject {
  external ReadableStreamDefaultReader getReader();
}

@JS()
extension type ReadableStreamDefaultReader._(JSObject _) implements JSObject {
  external JSPromise<ReadResult> read();
  external void releaseLock();
}

@JS()
extension type ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

@JS()
extension type WritableStream._(JSObject _) implements JSObject {
  external WritableStreamDefaultWriter getWriter();
}

@JS()
extension type WritableStreamDefaultWriter._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSUint8Array chunk);
  external void releaseLock();
}

// ── Port registry ───────────────────────────────────────────────────────────

bool get webSerialAvailable => _serial != null;

typedef WebPortDesc = ({String path, String description});

final _portCache = <String, SerialPort>{};

int _nextRequestedPortId = 0;

/// Requests permission for a port via the browser's native device-picker
/// dialog, **without opening it**.
///
/// Requires a user gesture (e.g. a button tap). The returned path is cached
/// in [_portCache], so a later [openWebPort] call for it resolves
/// immediately without prompting again — unlike opening the `web:request`
/// sentinel path, which always fuses the prompt and the open into one step.
///
/// Returns `null` if the user cancels the picker or permission is denied.
Future<WebPortDesc?> requestWebPort() async {
  final s = _serial;
  if (s == null) return null;

  final SerialPort port;
  try {
    port = await s.requestPort().toDart;
  } catch (_) {
    // The picker rejects its promise (rather than resolving null) when the
    // user cancels or denies permission.
    return null;
  }

  final path = 'web:requested:${_nextRequestedPortId++}';
  _portCache[path] = port;
  final info = port.getInfo();
  final vid = info.usbVendorId;
  final pid = info.usbProductId;
  final desc = (vid != null && pid != null)
      ? 'VID:${vid.toRadixString(16).padLeft(4, '0').toUpperCase()} '
        'PID:${pid.toRadixString(16).padLeft(4, '0').toUpperCase()}'
      : 'Web Serial Device';
  return (path: path, description: desc);
}

Future<List<WebPortDesc>> listWebPorts() async {
  final s = _serial;
  if (s == null) return [];
  final list = (await s.getPorts().toDart).toDart;
  final result = <WebPortDesc>[];
  for (int i = 0; i < list.length; i++) {
    final path = 'web:$i';
    _portCache[path] = list[i];
    final info = list[i].getInfo();
    final vid = info.usbVendorId;
    final pid = info.usbProductId;
    final desc = (vid != null && pid != null)
        ? 'VID:${vid.toRadixString(16).padLeft(4, '0').toUpperCase()} '
          'PID:${pid.toRadixString(16).padLeft(4, '0').toUpperCase()}'
        : 'Web Serial Device';
    result.add((path: path, description: desc));
  }
  return result;
}

// ── Connection management ───────────────────────────────────────────────────

class _WebConn {
  final SerialPort port;
  final ReadableStreamDefaultReader reader;
  final WritableStreamDefaultWriter writer;
  final StreamController<Uint8List> ctrl =
      StreamController<Uint8List>.broadcast();
  bool closed = false;

  _WebConn(this.port, this.reader, this.writer);
}

final _conns = <String, _WebConn>{};

Future<bool> openWebPort(
  String path, {
  required int baudRate,
  int dataBits = 8,
  int stopBits = 1,
  int parity = 0,
  int flowControl = 0,
}) async {
  late SerialPort port;

  if (path == 'web:request') {
    final p = await _serial?.requestPort().toDart;
    if (p == null) return false;
    port = p;
    _portCache[path] = port;
  } else {
    final cached = _portCache[path];
    if (cached == null) return false;
    port = cached;
  }

  final parityStr = const ['none', 'odd', 'even'][parity.clamp(0, 2)];
  // Web Serial only supports 'hardware' or 'none' flow control
  final flowStr = flowControl == 1 ? 'hardware' : 'none';

  try {
    await port.open(SerialOptions(
      baudRate: baudRate,
      dataBits: dataBits,
      stopBits: stopBits,
      parity: parityStr,
      flowControl: flowStr,
    )).toDart;
  } catch (_) {
    return false;
  }

  final reader = port.readable.getReader();
  final writer = port.writable.getWriter();
  final conn = _WebConn(port, reader, writer);
  _conns[path] = conn;

  Future.microtask(() async {
    try {
      while (!conn.closed) {
        final result = await conn.reader.read().toDart;
        if (result.done) break;
        final bytes = result.value;
        if (bytes != null && !conn.ctrl.isClosed) {
          conn.ctrl.add(bytes.toDart);
        }
      }
    } catch (_) {}
    if (!conn.ctrl.isClosed) conn.ctrl.close();
  });

  return true;
}

Stream<Uint8List>? webDataStream(String path) => _conns[path]?.ctrl.stream;

void writeWebPort(String path, Uint8List data) {
  _conns[path]?.writer.write(data.toJS); // fire-and-forget
}

Future<void> closeWebPort(String path) async {
  final conn = _conns.remove(path);
  if (conn == null) return;
  conn.closed = true;
  try { conn.reader.releaseLock(); } catch (_) {}
  try { conn.writer.releaseLock(); } catch (_) {}
  try { await conn.port.close().toDart; } catch (_) {}
  if (!conn.ctrl.isClosed) conn.ctrl.close();
}
