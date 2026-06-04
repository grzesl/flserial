import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Information about a single serial port discovered on the host system.
class SerialPortInfo {
  /// Platform-specific port identifier passed to [FlSerial.open].
  ///
  /// | Platform | Example |
  /// |----------|---------|
  /// | Windows | `COM3` |
  /// | Linux | `/dev/ttyUSB0` |
  /// | macOS | `/dev/cu.usbserial-1410` |
  /// | Android | `usb:/dev/bus/usb/001/002` |
  /// | Web | `web:request` |
  final String path;

  /// Human-readable label (device name, manufacturer, or generic category).
  final String description;

  /// Creates a [SerialPortInfo] with the given [path] and [description].
  SerialPortInfo(this.path, this.description);

  @override
  String toString() => '$path ($description)';
}

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
  /// * **Web** — returns a single synthetic `"Web Serial Port"` entry; opening
  ///   it shows the browser's native port-picker dialog.
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

  static Future<List<SerialPortInfo>> _scanWindows() async {
    final List<SerialPortInfo> ports = [];
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\HARDWARE\DEVICEMAP\SERIALCOMM',
      ]);

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\r\n');
        for (var line in lines) {
          if (line.contains('REG_SZ')) {
            final parts = line.split(RegExp(r'\s+'));
            final portName = parts.last;
            ports.add(SerialPortInfo(portName, 'Windows Serial Device'));
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
            ports.add(SerialPortInfo(devicePath, 'Linux TTY Device'));
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
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (name.startsWith('cu.')) {
          if (!name.contains('Bluetooth') && !name.contains('AirPods')) {
            ports.add(SerialPortInfo(entity.path, 'macOS Serial Device'));
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
            final desc = [manufacturer, product]
                .where((s) => s.isNotEmpty)
                .join(' ')
                .trim();
            if (name.isNotEmpty) {
              ports.add(SerialPortInfo(
                'usb:$name',
                desc.isNotEmpty ? desc : 'USB Serial Device',
              ));
            }
          }
        }
      }
    } catch (_) {}
    return ports;
  }

  static Future<List<SerialPortInfo>> _scanWeb() async {
    return [SerialPortInfo('web:request', 'Web Serial Port')];
  }
}
