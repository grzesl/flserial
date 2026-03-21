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
  int _baudRate = 115200;

  // Lista logów: {message, isIncoming}
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
      setState(() {
        switch (event.type) {
          case SerialEventType.data:
            _addLog(String.fromCharCodes(event.data as Uint8List), true);
            break;
          case SerialEventType.lineStatusChanged:
            _modemStatus = Map<String, bool>.from(event.data);
            break;
          case SerialEventType.connected:
            _isConnected = true;
            _addLog(">>> PORT OTWARTY <<<", false);
            break;
          case SerialEventType.disconnected:
            _isConnected = false;
            _addLog(">>> PORT ZAMKNIĘTY <<<", false);
            break;
          case SerialEventType.error:
            _addLog("BŁĄD: ${event.data}", false);
            break;
        }
      });
    });
  }

  void _refreshPorts() async {
    final ports = await FlSerial.availablePorts();
    setState(() {
      _availablePorts = ports.map((e) {
        return e.path.toString();
      }).toList();

      if (_availablePorts.isNotEmpty) {
        if (_selectedPort == null || !_availablePorts.contains(_selectedPort)) {
          _selectedPort = _availablePorts.first;
        }
      } else {
        _selectedPort = null;
      }
    });
  }

  void _toggleConnection() {
    if (_isConnected) {
      _serial.close();
    } else {
      if (_selectedPort == null) return;
      final config = SerialConfig(baudRate: _baudRate);
      if (!_serial.open(_selectedPort!, config)) {
        _addLog("Nie udało się otworzyć $_selectedPort", false);
      }
    }
  }

  void _sendData() {
    final text = _sendController.text;
    if (text.isEmpty) return;

    // Wysyłamy tekst z końcem linii \r\n (standard terminala)
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
      body: Column(
        children: [
          // GÓRNY PANEL: WYBÓR PORTU
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
                      items: _availablePorts
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: _isConnected
                          ? null
                          : (v) => setState(() => _selectedPort = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: (_selectedPort != null)
                        ? _toggleConnection
                        : null,
                    icon: Icon(_isConnected ? Icons.stop : Icons.play_arrow),
                    label: Text(_isConnected ? "STOP" : "START"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      foregroundColor: _isConnected ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // STATUS LINII (DIODY)
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

          // TERMINAL (LOGI)
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
                      color: log['in'] ? Colors.blue.shade900 : Colors.black87,
                      fontWeight: log['in']
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  );
                },
              ),
            ),
          ),

          // DOLNY PANEL: WYSYŁANIE DANYCH
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sendController,
                    decoration: const InputDecoration(
                      hintText: "Wpisz komendę...",
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
      ),
    );
  }

  @override
  void dispose() {
    _serial.dispose();
    _sendController.dispose();
    super.dispose();
  }
}
