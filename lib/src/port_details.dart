import 'dart:io';

/// USB identification of a serial port, as far as the platform exposes it.
typedef PortDetails = ({
  String? description,
  int? vendorId,
  int? productId,
  String? serialNumber,
});

// ── Linux ───────────────────────────────────────────────────────────────────

/// Looks up the USB device behind `/dev/<ttyName>` in sysfs.
///
/// Returns `null` for non-USB ports (e.g. `ttyS*`).
Future<PortDetails?> linuxPortDetails(String ttyName) async {
  try {
    // .../usb1/1-1/1-1:1.0/ttyUSB0 → walk up to the USB device node (1-1),
    // which is the first ancestor carrying idVendor/idProduct.
    var dir = Directory(
      await Directory('/sys/class/tty/$ttyName/device').resolveSymbolicLinks(),
    );
    for (int i = 0; i < 6 && dir.path != dir.parent.path; i++) {
      final vid = await _readSysfs('${dir.path}/idVendor');
      final pid = await _readSysfs('${dir.path}/idProduct');
      if (vid != null && pid != null) {
        final desc = [
          await _readSysfs('${dir.path}/manufacturer'),
          await _readSysfs('${dir.path}/product'),
        ].whereType<String>().join(' ');
        return (
          description: desc.isNotEmpty ? desc : null,
          vendorId: int.tryParse(vid, radix: 16),
          productId: int.tryParse(pid, radix: 16),
          serialNumber: await _readSysfs('${dir.path}/serial'),
        );
      }
      dir = dir.parent;
    }
  } catch (_) {}
  return null;
}

Future<String?> _readSysfs(String path) async {
  try {
    final value = (await File(path).readAsString()).trim();
    return value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}

// ── macOS ───────────────────────────────────────────────────────────────────

/// Returns USB details for every USB serial port, keyed by call-out device
/// path (`/dev/cu.*`).
Future<Map<String, PortDetails>> macosPortDetails() async {
  final result = <String, PortDetails>{};
  // IOUSBHostDevice on macOS 10.11+, IOUSBDevice on older releases.
  for (final cls in const ['IOUSBHostDevice', 'IOUSBDevice']) {
    try {
      final res = await Process.run('ioreg', ['-r', '-c', cls, '-l', '-w', '0']);
      if (res.exitCode == 0) result.addAll(parseIoreg(res.stdout.toString()));
    } catch (_) {}
    if (result.isNotEmpty) break;
  }
  return result;
}

class _IoregNode {
  final int depth;
  int? vendorId;
  int? productId;
  String? serialNumber;
  String? vendorName;
  String? productName;
  _IoregNode(this.depth);
}

final _ioregIndent = RegExp(r'^[|\s]*$');
final _ioregInt =RegExp(r'"(idVendor|idProduct)" = (\d+)');
final _ioregStr = RegExp(
  r'"(USB Serial Number|kUSBSerialNumberString|USB Vendor Name|'
  r'USB Product Name|IOCalloutDevice)" = "([^"]*)"',
);

/// Parses `ioreg -r -c IOUSBHostDevice -l` output.
///
/// Each `/dev/cu.*` entry (`IOCalloutDevice`) is attributed to the nearest
/// enclosing registry node that carries `idVendor`/`idProduct`.
Map<String, PortDetails> parseIoreg(String output) {
  final result = <String, PortDetails>{};
  final stack = <_IoregNode>[];

  for (final line in output.split('\n')) {
    final nodeAt = line.indexOf('+-o ');
    if (nodeAt >= 0 && _ioregIndent.hasMatch(line.substring(0, nodeAt))) {
      while (stack.isNotEmpty && stack.last.depth >= nodeAt) {
        stack.removeLast();
      }
      stack.add(_IoregNode(nodeAt));
      continue;
    }
    if (stack.isEmpty) continue;
    final node = stack.last;

    final mi = _ioregInt.firstMatch(line);
    if (mi != null) {
      final value = int.parse(mi.group(2)!);
      if (mi.group(1) == 'idVendor') {
        node.vendorId = value;
      } else {
        node.productId = value;
      }
      continue;
    }

    final ms = _ioregStr.firstMatch(line);
    if (ms == null) continue;
    final value = ms.group(2)!;
    switch (ms.group(1)) {
      case 'USB Serial Number' || 'kUSBSerialNumberString':
        node.serialNumber = value;
      case 'USB Vendor Name':
        node.vendorName = value;
      case 'USB Product Name':
        node.productName = value;
      case 'IOCalloutDevice':
        // IDs repeat on interface nodes, but the strings live only on the
        // device node, so each field is taken from its own nearest ancestor.
        int? vid, pid;
        String? serial, vendor, product;
        for (final n in stack.reversed) {
          if (vid == null && n.vendorId != null && n.productId != null) {
            vid = n.vendorId;
            pid = n.productId;
          }
          serial ??= n.serialNumber;
          vendor ??= n.vendorName;
          product ??= n.productName;
        }
        if (vid == null) break;
        final desc = [vendor, product]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' ');
        result[value] = (
          description: desc.isNotEmpty ? desc : null,
          vendorId: vid,
          productId: pid,
          serialNumber: (serial?.isEmpty ?? true) ? null : serial,
        );
    }
  }
  return result;
}
