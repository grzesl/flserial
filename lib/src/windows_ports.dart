import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'port_details.dart';

// ── SetupAPI bindings ───────────────────────────────────────────────────────

final class _SpDevinfoData extends Struct {
  @Uint32()
  external int cbSize;
  @Array(16)
  external Array<Uint8> classGuid;
  @Uint32()
  external int devInst;
  @IntPtr()
  external int reserved;
}

const _digcfPresent = 0x02;
const _spdrpFriendlyName = 0x0C;
const _spdrpDeviceDesc = 0x00;
const _dicsFlagGlobal = 1;
const _diregDev = 1;
const _keyRead = 0x20019;
const _invalidHandle = -1;
const _bufChars = 512;

// GUID_DEVCLASS_PORTS  {4D36E978-E325-11CE-BFC1-08002BE10318}
// GUID_DEVCLASS_MODEM  {4D36E96D-E325-11CE-BFC1-08002BE10318}
const _classGuids = [
  [0x78, 0xE9, 0x36, 0x4D, 0x25, 0xE3, 0xCE, 0x11, 0xBF, 0xC1, 0x08, 0x00, 0x2B, 0xE1, 0x03, 0x18],
  [0x6D, 0xE9, 0x36, 0x4D, 0x25, 0xE3, 0xCE, 0x11, 0xBF, 0xC1, 0x08, 0x00, 0x2B, 0xE1, 0x03, 0x18],
];

final _setupapi = DynamicLibrary.open('setupapi.dll');
final _advapi32 = DynamicLibrary.open('advapi32.dll');

final _getClassDevs = _setupapi.lookupFunction<
    IntPtr Function(Pointer<Uint8>, Pointer<Utf16>, IntPtr, Uint32),
    int Function(Pointer<Uint8>, Pointer<Utf16>, int, int)>('SetupDiGetClassDevsW');

final _enumDeviceInfo = _setupapi.lookupFunction<
    Int32 Function(IntPtr, Uint32, Pointer<_SpDevinfoData>),
    int Function(int, int, Pointer<_SpDevinfoData>)>('SetupDiEnumDeviceInfo');

final _getInstanceId = _setupapi.lookupFunction<
    Int32 Function(IntPtr, Pointer<_SpDevinfoData>, Pointer<Utf16>, Uint32, Pointer<Uint32>),
    int Function(int, Pointer<_SpDevinfoData>, Pointer<Utf16>, int, Pointer<Uint32>)>(
  'SetupDiGetDeviceInstanceIdW',
);

final _getRegistryProperty = _setupapi.lookupFunction<
    Int32 Function(IntPtr, Pointer<_SpDevinfoData>, Uint32, Pointer<Uint32>, Pointer<Uint8>, Uint32,
        Pointer<Uint32>),
    int Function(int, Pointer<_SpDevinfoData>, int, Pointer<Uint32>, Pointer<Uint8>, int,
        Pointer<Uint32>)>('SetupDiGetDeviceRegistryPropertyW');

final _openDevRegKey = _setupapi.lookupFunction<
    IntPtr Function(IntPtr, Pointer<_SpDevinfoData>, Uint32, Uint32, Uint32, Uint32),
    int Function(int, Pointer<_SpDevinfoData>, int, int, int, int)>('SetupDiOpenDevRegKey');

final _destroyInfoList = _setupapi.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
  'SetupDiDestroyDeviceInfoList',
);

final _getParent = _setupapi.lookupFunction<
    Uint32 Function(Pointer<Uint32>, Uint32, Uint32),
    int Function(Pointer<Uint32>, int, int)>('CM_Get_Parent');

final _getDeviceId = _setupapi.lookupFunction<
    Uint32 Function(Uint32, Pointer<Utf16>, Uint32, Uint32),
    int Function(int, Pointer<Utf16>, int, int)>('CM_Get_Device_IDW');

final _regQueryValue = _advapi32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>,
        Pointer<Uint32>),
    int Function(int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint8>,
        Pointer<Uint32>)>('RegQueryValueExW');

final _regCloseKey =
    _advapi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');

// ── Enumeration ─────────────────────────────────────────────────────────────

final _vidPid = RegExp(r'VID_([0-9A-F]{4})[&+]PID_([0-9A-F]{4})', caseSensitive: false);
// A plain USB device node: its last path segment is the serial number, unless
// Windows generated it (generated IDs contain '&').
final _usbDevice = RegExp(r'^USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4}\\([^&\\]+)$', caseSensitive: false);

/// Returns USB details of every present COM port, keyed by port name
/// (`COM3`).
Map<String, PortDetails> windowsPortDetails() {
  final result = <String, PortDetails>{};
  using((arena) {
    final guid = arena<Uint8>(16);
    final info = arena<_SpDevinfoData>();
    final buf = arena<Uint16>(_bufChars);
    final size = arena<Uint32>();
    final parent = arena<Uint32>();
    final valueName = 'PortName'.toNativeUtf16(allocator: arena);

    String? property(int devs, int prop) {
      buf[0] = 0;
      final ok = _getRegistryProperty(
          devs, info, prop, nullptr, buf.cast(), (_bufChars - 1) * 2, nullptr);
      if (ok == 0) return null;
      final s = buf.cast<Utf16>().toDartString();
      return s.isEmpty ? null : s;
    }

    String? portName(int devs) {
      final key = _openDevRegKey(devs, info, _dicsFlagGlobal, 0, _diregDev, _keyRead);
      if (key == _invalidHandle) return null;
      try {
        // Registry strings are not guaranteed to be NUL-terminated.
        for (int i = 0; i < _bufChars; i++) {
          buf[i] = 0;
        }
        size.value = (_bufChars - 1) * 2;
        if (_regQueryValue(key, valueName, nullptr, nullptr, buf.cast(), size) != 0) {
          return null;
        }
        final s = buf.cast<Utf16>().toDartString();
        return s.isEmpty ? null : s;
      } finally {
        _regCloseKey(key);
      }
    }

    for (final bytes in _classGuids) {
      guid.asTypedList(16).setAll(0, bytes);
      final devs = _getClassDevs(guid, nullptr, 0, _digcfPresent);
      if (devs == _invalidHandle) continue;
      try {
        for (int index = 0;; index++) {
          info.ref.cbSize = sizeOf<_SpDevinfoData>();
          if (_enumDeviceInfo(devs, index, info) == 0) break;

          final port = portName(devs);
          if (port == null || !port.toUpperCase().startsWith('COM')) continue;

          String? instanceId;
          if (_getInstanceId(devs, info, buf.cast(), _bufChars, nullptr) != 0) {
            instanceId = buf.cast<Utf16>().toDartString();
          }
          // Composite-device interfaces (…&MI_00) and FTDIBUS children carry
          // a generated instance ID; the real USB device is their parent.
          String? parentId;
          if (_getParent(parent, info.ref.devInst, 0) == 0 &&
              _getDeviceId(parent.value, buf.cast(), _bufChars, 0) == 0) {
            parentId = buf.cast<Utf16>().toDartString();
          }

          final ids = _vidPid.firstMatch(instanceId ?? '') ?? _vidPid.firstMatch(parentId ?? '');
          final serial = _usbDevice.firstMatch(instanceId ?? '') ??
              (ids != null ? _usbDevice.firstMatch(parentId ?? '') : null);

          result[port.toUpperCase()] = (
            description:
                property(devs, _spdrpFriendlyName) ?? property(devs, _spdrpDeviceDesc),
            vendorId: ids != null ? int.parse(ids.group(1)!, radix: 16) : null,
            productId: ids != null ? int.parse(ids.group(2)!, radix: 16) : null,
            serialNumber: serial?.group(1),
          );
        }
      } finally {
        _destroyInfoList(devs);
      }
    }
  });
  return result;
}
