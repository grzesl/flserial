import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flserial/flserial.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'Serial Terminal',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const SerialProTerminal(),
    ),
  );
}

class SerialProTerminal extends StatefulWidget {
  const SerialProTerminal({super.key});

  @override
  State<SerialProTerminal> createState() => _SerialProTerminalState();
}

class _SerialProTerminalState extends State<SerialProTerminal> {
  final FlSerial _serial = FlSerial();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _sendController = TextEditingController();

  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isConnected = false;

  // SerialConfig parameters
  int _baudRate = 115200;
  int _dataBits = 8;
  int _stopBits = 1;
  int _parity = 0;
  int _flowControl = 0;

  final List<Map<String, dynamic>> _logs = [];
  Map<String, bool> _modemStatus = {
    'CTS': false,
    'DSR': false,
    'RI': false,
    'DCD': false,
  };

  @override
  void initState() {
    super.initState();
    _refreshPorts();

    _serial.events.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case SerialEventType.data:
          _addLog(String.fromCharCodes(event.data as Uint8List), true);
        case SerialEventType.lineStatusChanged:
          setState(() {
            _modemStatus = Map<String, bool>.from(event.data);
          });
        case SerialEventType.connected:
          setState(() => _isConnected = true);
          _addLog(">>> PORT OPEN <<<", false);
        case SerialEventType.disconnected:
          setState(() => _isConnected = false);
          _addLog(">>> PORT CLOSED <<<", false);
        case SerialEventType.error:
          _addLog("ERROR: ${event.data}", false);
      }
    });
  }

  void _refreshPorts() async {
    final ports = await FlSerial.availablePorts();
    setState(() {
      _availablePorts = ports.map((e) => e.path.toString()).toList();
      if (_availablePorts.isNotEmpty) {
        if (_selectedPort == null || !_availablePorts.contains(_selectedPort)) {
          _selectedPort = _availablePorts.first;
        }
      } else {
        _selectedPort = null;
      }
    });
  }

  Future<void> _toggleConnection() async {
    if (_isConnected) {
      _serial.close();
    } else {
      if (_selectedPort == null) return;
      final config = SerialConfig(
        baudRate: _baudRate,
        dataBits: _dataBits,
        stopBits: _stopBits,
        parity: _parity,
        flowControl: _flowControl,
      );
      final ok = await _serial.open(_selectedPort!, config);
      if (!ok) {
        _addLog("Failed to open $_selectedPort", false);
      }
    }
  }

  void _sendData() {
    final text = _sendController.text;
    if (text.isEmpty || !_isConnected) return;
    final data = Uint8List.fromList("$text\r\n".codeUnits);
    _serial.write(data);
    _addLog(text, false);
    _sendController.clear();
  }

  void _addLog(String msg, bool isIncoming) {
    setState(() {
      _logs.add({'msg': msg, 'in': isIncoming});
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Serial FFI Terminal"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(onPressed: _refreshPorts, icon: const Icon(Icons.sync)),
        ],
      ),
      body: SafeArea(child: Column(
        children: [
          // PORT SELECTION
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedPort,
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: const Text("No ports found"),
                      items: _availablePorts
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: _isConnected
                          ? null
                          : (v) => setState(() => _selectedPort = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _selectedPort != null ? _toggleConnection : null,
                    icon: Icon(_isConnected ? Icons.stop : Icons.play_arrow),
                    label: Text(_isConnected ? "STOP" : "START"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      foregroundColor:
                          _isConnected ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // CONFIGURATION
          Card(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  _cfgDropdown<int>(
                    label: "Baud",
                    value: _baudRate,
                    items: const [
                      9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600,
                    ],
                    onChanged: (v) => setState(() => _baudRate = v!),
                  ),
                  const SizedBox(width: 8),
                  _cfgDropdown<int>(
                    label: "Data",
                    value: _dataBits,
                    items: const [7, 8],
                    onChanged: (v) => setState(() => _dataBits = v!),
                  ),
                  const SizedBox(width: 8),
                  _cfgDropdown<int>(
                    label: "Stop",
                    value: _stopBits,
                    items: const [1, 2],
                    onChanged: (v) => setState(() => _stopBits = v!),
                  ),
                  const SizedBox(width: 8),
                  _cfgDropdown<int>(
                    label: "Parity",
                    value: _parity,
                    items: const [0, 1, 2],
                    labels: const ["N", "O", "E"],
                    onChanged: (v) => setState(() => _parity = v!),
                  ),
                  const SizedBox(width: 8),
                  _cfgDropdown<int>(
                    label: "Flow",
                    value: _flowControl,
                    items: const [0, 1, 2],
                    labels: const ["None", "RTS/CTS", "XON/XOFF"],
                    onChanged: (v) => setState(() => _flowControl = v!),
                  ),
                ],
              ),
            ),
          ),

          // MODEM STATUS
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _modemStatus.entries
                  .map(
                    (e) => Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: e.value ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(e.key, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),

          // TERMINAL LOG
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                itemCount: _logs.length,
                itemBuilder: (context, i) {
                  final log = _logs[i];
                  return Text(
                    "${log['in'] ? '←' : '→'} ${log['msg']}",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color:
                          log['in'] ? Colors.blue.shade900 : Colors.black87,
                      fontWeight:
                          log['in'] ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                },
              ),
            ),
          ),

          // SEND
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sendController,
                    decoration: const InputDecoration(
                      hintText: "Enter command...",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendData(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isConnected ? _sendData : null,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }

  Widget _cfgDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    List<String>? labels,
    required ValueChanged<T?> onChanged,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox(),
            items: items.asMap().entries
                .map((e) => DropdownMenuItem<T>(
                      value: e.value,
                      child: Text(
                        labels != null ? labels[e.key] : e.value.toString(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ))
                .toList(),
            onChanged: _isConnected ? null : onChanged,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serial.dispose();
    _sendController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
