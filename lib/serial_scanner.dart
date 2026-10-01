import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'src/port_details.dart';
import 'src/serial_types.dart';
import 'src/web_serial_stub.dart'
    if (dart.library.js_interop) 'src/web_serial.dart' as web;
import 'src/windows_ports_stub.dart'
    if (dart.library.io) 'src/windows_ports.dart';

export 'src/serial_types.dart' show SerialPortInfo;

/// Scans the host system for available serial ports.
///
/// Prefer [FlSerial.availablePorts], which delegates here.
///
/// ```dart
/// final ports = await SerialScanner.getAvailablePorts();
/// for (final p in ports) print(p);
/// ```
class SerialScanner {
  static final _usbChannel = MethodChannel('io.github.grzesl.flserial/usb');

  /// Returns all serial ports currently available on this device.
  ///
  /// The implementation is platform-specific:
  ///
  /// * **Windows** — reads `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` from the registry.
  /// * **Linux** — scans `/sys/class/tty` for `ttyUSB*`, `ttyACM*`, `ttyS*` entries.
  /// * **macOS** — scans `/dev/cu.*` (call-out devices only).
  /// * **Android** — queries connected USB serial devices via the USB Host API
  ///   platform channel; returns `usb:`-prefixed paths.
  /// * **Web** — returns a synthetic `"Web Serial Port"` entry (opening it
  ///   shows the browser's native port-picker dialog), followed by the ports
  ///   the user has already granted access to.
  ///
  /// USB devices are reported with [SerialPortInfo.vendorId] and
  /// [SerialPortInfo.productId] filled in.
  static Future<List<SerialPortInfo>> getAvailablePorts() async {
    if (kIsWeb) return _scanWeb();
    if (Platform.isWindows) {
      return _scanWindows();
    } else if (Platform.isLinux) {
      return _scanLinux();
    } else if (Platform.isMacOS) {
      return _scanMacOS();
    } else if (Platform.isAndroid) {
      return _scanAndroid();
    }
    return [];
  }

  /// Returns the available ports that belong to a USB device with the given
  /// [vendorId] and [productId] (and [serialNumber], when provided).
  static Future<List<SerialPortInfo>> findByVidPid(
    int vendorId,
    int productId, {
    String? serialNumber,
  }) async {
    final ports = await getAvailablePorts();
    return ports
        .where((p) => p.matches(vendorId, productId, serialNumber: serialNumber))
        .toList();
  }

  static Future<List<SerialPortInfo>> _scanWindows() async {
    final List<SerialPortInfo> ports = [];
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\HARDWARE\DEVICEMAP\SERIALCOMM',
      ]);

      if (result.exitCode == 0) {
        var details = const <String, PortDetails>{};
        try {
          details = windowsPortDetails();
        } catch (_) {}

        final lines = result.stdout.toString().split('\r\n');
        for (var line in lines) {
          if (line.contains('REG_SZ')) {
            final parts = line.split(RegExp(r'\s+'));
            final portName = parts.last;
            final d = details[portName.toUpperCase()];
            ports.add(SerialPortInfo(
              portName,
              d?.description ?? 'Windows Serial Device',
              vendorId: d?.vendorId,
              productId: d?.productId,
              serialNumber: d?.serialNumber,
            ));
          }
        }
      }
    } catch (_) {}
    return ports;
  }

  static Future<List<SerialPortInfo>> _scanLinux() async {
    final List<SerialPortInfo> ports = [];
    final dir = Directory('/sys/class/tty');

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (name.startsWith('ttyUSB') ||
            name.startsWith('ttyACM') ||
            name.startsWith('ttyS')) {
          final devicePath = '/dev/$name';
          if (await File(devicePath).exists()) {
            final d = await linuxPortDetails(name);
            ports.add(SerialPortInfo(
              devicePath,
              d?.description ?? 'Linux TTY Device',
              vendorId: d?.vendorId,
              productId: d?.productId,
              serialNumber: d?.serialNumber,
            ));
          }
        }
      }
    }
    return ports;
  }

  static Future<List<SerialPortInfo>> _scanMacOS() async {
    final List<SerialPortInfo> ports = [];
    final dir = Directory('/dev');

    if (await dir.exists()) {
      final details = await macosPortDetails();
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (name.startsWith('cu.')) {
          if (!name.contains('Bluetooth') && !name.contains('AirPods')) {
            final d = details[entity.path];
            ports.add(SerialPortInfo(
              entity.path,
              d?.description ?? 'macOS Serial Device',
              vendorId: d?.vendorId,
              productId: d?.productId,
              serialNumber: d?.serialNumber,
            ));
          }
        }
      }
    }
    return ports;
  }

  static Future<List<SerialPortInfo>> _scanAndroid() async {
    final List<SerialPortInfo> ports = [];
    try {
      final List<dynamic>? result =
          await _usbChannel.invokeListMethod<dynamic>('listUsbSerialDevices');
      if (result != null) {
        for (final item in result) {
          if (item is Map) {
            final name = item['name'] as String? ?? '';
            final product = item['product'] as String? ?? '';
            final manufacturer = item['manufacturer'] as String? ?? '';
            final serial = item['serial'] as String? ?? '';
            final desc = [manufacturer, product]
                .where((s) => s.isNotEmpty)
                .join(' ')
                .trim();
            if (name.isNotEmpty) {
              ports.add(SerialPortInfo(
                'usb:$name',
                desc.isNotEmpty ? desc : 'USB Serial Device',
                vendorId: item['vid'] as int?,
                productId: item['pid'] as int?,
                serialNumber: serial.isNotEmpty ? serial : null,
              ));
            }
          }
        }
      }
    } catch (_) {}
    return ports;
  }

  static Future<List<SerialPortInfo>> _scanWeb() async {
    final ports = [SerialPortInfo('web:request', 'Web Serial Port')];
    try {
      for (final p in await web.listWebPorts()) {
        ports.add(SerialPortInfo(
          p.path,
          p.description,
          vendorId: p.vendorId,
          productId: p.productId,
        ));
      }
    } catch (_) {}
    return ports;
  }
}
