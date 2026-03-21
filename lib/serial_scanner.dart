import 'dart:io';

class SerialPortInfo {
  final String path;
  final String description;

  SerialPortInfo(this.path, this.description);

  @override
  String toString() => "$path ($description)";
}

class SerialScanner {
  /// Zwraca listę dostępnych portów szeregowych
  static Future<List<SerialPortInfo>> getAvailablePorts() async {
    if (Platform.isWindows) {
      return _scanWindows();
    } else if (Platform.isLinux) {
      return _scanLinux();
    } else if (Platform.isMacOS) {
      return _scanMacOS();
    }
    return [];
  }

  /// Windows: Odczyt z rejestru HARDWARE\DEVICEMAP\SERIALCOMM
  static Future<List<SerialPortInfo>> _scanWindows() async {
    final List<SerialPortInfo> ports = [];
    try {
      // Wykorzystujemy komendę reg query do odczytu portów COM
      final result = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\HARDWARE\DEVICEMAP\SERIALCOMM',
      ]);

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\r\n');
        for (var line in lines) {
          if (line.contains('REG_SZ')) {
            final parts = line.split(RegExp(r'\s+'));
            final portName = parts.last; // np. COM3
            ports.add(SerialPortInfo(portName, "Urządzenie szeregowe Windows"));
          }
        }
      }
    } catch (e) {
      print("Błąd skanowania Windows: $e");
    }
    return ports;
  }

  /// Linux: Przeszukiwanie /sys/class/tty
  static Future<List<SerialPortInfo>> _scanLinux() async {
    final List<SerialPortInfo> ports = [];
    final dir = Directory('/sys/class/tty');

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        // Szukamy ttyUSB, ttyACM (Arduino/STM32) lub ttyS (fizyczne porty)
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

  /// macOS: Przeszukiwanie /dev/cu.*
  static Future<List<SerialPortInfo>> _scanMacOS() async {
    final List<SerialPortInfo> ports = [];
    final dir = Directory('/dev');

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        // Na macu używamy portów "cu" (call-out), bo nie czekają na sygnał DCD
        if (name.startsWith('cu.')) {
          // Filtrujemy tylko rzeczywiste urządzenia USB/Bluetooth
          if (!name.contains('Bluetooth') && !name.contains('AirPods')) {
            ports.add(SerialPortInfo(entity.path, "macOS Serial Device"));
          }
        }
      }
    }
    return ports;
  }
}
