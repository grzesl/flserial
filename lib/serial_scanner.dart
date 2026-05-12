import 'dart:io';
import 'package:flutter/services.dart';

class SerialPortInfo {
  final String path;
  final String description;

  SerialPortInfo(this.path, this.description);

  @override
  String toString() => "$path ($description)";
}

class SerialScanner {
  static final _usbChannel = MethodChannel('io.github.grzesl.flserial/usb');

  /// Returns list of available serial ports
  static Future<List<SerialPortInfo>> getAvailablePorts() async {
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

  /// Windows: reads from registry HARDWARE\DEVICEMAP\SERIALCOMM
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
            ports.add(SerialPortInfo(portName, "Windows Serial Device"));
          }
        }
      }
    } catch (_) {}
    return ports;
  }

  /// Linux: scans /sys/class/tty
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
            ports.add(SerialPortInfo(devicePath, "Linux TTY Device"));
          }
        }
      }
    }
    return ports;
  }

  /// macOS: scans /dev/cu.*
  static Future<List<SerialPortInfo>> _scanMacOS() async {
    final List<SerialPortInfo> ports = [];
    final dir = Directory('/dev');

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (name.startsWith('cu.')) {
          if (!name.contains('Bluetooth') && !name.contains('AirPods')) {
            ports.add(SerialPortInfo(entity.path, "macOS Serial Device"));
          }
        }
      }
    }
    return ports;
  }

  /// Android: queries USB serial devices via platform channel (USB Host API).
  /// Returns paths prefixed with "usb:" so the caller can route them correctly.
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
}
