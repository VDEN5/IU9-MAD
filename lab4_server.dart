import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const ServerApp());

class ServerApp extends StatelessWidget {
  const ServerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Robot Server',
        theme: ThemeData(useMaterial3: true),
        debugShowCheckedModeBanner: false,
        home: const ServerPage(),
      );
}

class LogEntry {
  final DateTime time;
  final String message;
  final bool isError;
  LogEntry(this.message, {this.isError = false}) : time = DateTime.now();
  Map<String, dynamic> toJson() =>
      {'time': time.toIso8601String(), 'message': message, 'isError': isError};
}

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});
  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  static const int _maxLogs = 300;
  static const int _minSpeed = -100;
  static const int _maxSpeed = 100;

  HttpServer? _server;
  final Set<WebSocket> _clients = {};

  final TextEditingController _portCtrl = TextEditingController(text: '8080');
  bool _starting = false;
  int? _boundPort;
  String? _error;

  final Map<String, double> _variables = {
    'left': 0.0,
    'right': 0.0,
    'wheel_radius': 0.05,
    'base_length': 0.3,
  };

  final List<LogEntry> _logs = [];
  final ScrollController _logScroll = ScrollController();
  List<String> _ips = [];

  @override
  void initState() {
    super.initState();
    _refreshIps();
  }

  @override
  void dispose() {
    _stopServer();
    _portCtrl.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _refreshIps() async {
    final ips = <String>[];
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in ifaces) {
        for (final a in i.addresses) {
          ips.add('${a.address} (${i.name})');
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _ips = ips);
  }

  Future<void> _startServer() async {
    if (_server != null) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _refreshIps();
      final port = int.parse(_portCtrl.text.trim());
      final srv = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server = srv;
      _boundPort = port;
      srv.listen(_handleRequest);
      _addLog('Server started on port $port');
    } catch (e) {
      setState(() => _error = 'Не удалось запустить: $e');
    }
    setState(() => _starting = false);
  }

  Future<void> _stopServer() async {
    for (final c in _clients.toList()) {
      try {
        await c.close();
      } catch (_) {}
    }
    _clients.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _boundPort = null;
    if (mounted) {
      setState(() {});
      _addLog('Server stopped');
    }
  }

  void _handleRequest(HttpRequest req) async {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      _handleClient(ws);
    } else {
      req.response
        ..statusCode = 200
        ..write('Robot WS server is running. Connect via WebSocket.\n')
        ..close();
    }
  }

  void _handleClient(WebSocket ws) {
    _clients.add(ws);
    _addLog('Client connected (${_clients.length})');

    _send(ws, {
      'type': 'init',
      'variables': _variables,
      'logs': _logs.map((e) => e.toJson()).toList(),
    });

    ws.listen(
      (data) {
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(data as String) as Map<String, dynamic>;
        } catch (e) {
          _send(ws, {'type': 'error', 'message': 'Bad JSON: $e'});
          return;
        }
        _handleMessage(ws, msg);
      },
      onDone: () {
        _clients.remove(ws);
        _addLog('Client disconnected (${_clients.length})');
      },
      onError: (e) {
        _clients.remove(ws);
        _addLog('Client error: $e', isError: true);
      },
    );
  }

  void _handleMessage(WebSocket from, Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'set':
        final name = msg['name'] as String?;
        final value = msg['value'];
        if (name == null || value is! num || !_variables.containsKey(name)) {
          _send(from, {'type': 'error', 'message': 'Invalid set request'});
          return;
        }
        final v = value.toDouble();
        setState(() => _variables[name] = v);
        _addLog('client set $name = $v');
        _broadcast({'type': 'variable', 'name': name, 'value': v});
        break;

      case 'get_all':
        _send(from, {'type': 'state', 'variables': _variables});
        break;

      case 'add_log':
        final message = (msg['message'] ?? '').toString();
        final isError = msg['isError'] == true;
        _addLog('[client] $message', isError: isError, broadcastLog: true);
        break;

      case 'get_logs':
        _send(from, {
          'type': 'logs',
          'logs': _logs.map((e) => e.toJson()).toList(),
        });
        break;

      case 'clear_logs':
        setState(() => _logs.clear());
        _broadcast({'type': 'logs_cleared'});
        _addLog('Logs cleared');
        break;

      default:
        _send(from, {'type': 'error', 'message': 'Unknown type: $type'});
    }
  }

  void _send(WebSocket ws, Map<String, dynamic> msg) {
    try {
      ws.add(jsonEncode(msg));
    } catch (_) {}
  }

  void _broadcast(Map<String, dynamic> msg) {
    final data = jsonEncode(msg);
    for (final c in _clients.toList()) {
      try {
        c.add(data);
      } catch (_) {}
    }
  }

  void _addLog(String m, {bool isError = false, bool broadcastLog = false}) {
    final e = LogEntry(m, isError: isError);
    if (mounted) {
      setState(() {
        _logs.add(e);
        if (_logs.length > _maxLogs) {
          _logs.removeRange(0, _logs.length - _maxLogs);
        }
      });
    }
    print('[${_fmtTime(e.time)}] ${isError ? "ERROR " : ""}$m');
    _scrollBottom();
    if (broadcastLog) _broadcast({'type': 'log', 'log': e.toJson()});
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  void _setVariableFromGui(String name, double value) {
    setState(() => _variables[name] = value);
    _broadcast({'type': 'variable', 'name': name, 'value': value});
    _addLog('GUI set $name = $value');
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Скопировано: $text'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сервер робота'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _statusCard(),
          const SizedBox(height: 12),
          _variablesCard(),
          const SizedBox(height: 12),
          _logsCard(),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final running = _server != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.cloud_done : Icons.cloud_off,
                  color: running ? Colors.green : Colors.grey,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    running ? 'Сервер работает (порт $_boundPort)' : 'Сервер остановлен',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!running)
                  Expanded(
                    child: TextField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Порт',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Обновить IP'),
                      onPressed: _refreshIps,
                    ),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed:
                      _starting ? null : (running ? _stopServer : _startServer),
                  icon: Icon(running ? Icons.stop : Icons.play_arrow),
                  label: Text(running ? 'Стоп' : 'Запустить'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: running ? Colors.red : null,
                    foregroundColor: running ? Colors.white : null,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Адрес для клиента (введи на эмуляторе):',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (_ips.isEmpty)
                    const Text('— нет активных IPv4 интерфейсов —',
                        style: TextStyle(color: Colors.grey))
                  else
                    ..._ips.map((entry) {
                      final ip = entry.split(' ').first;
                      final port = _boundPort ?? _portCtrl.text;
                      final text = '$ip  |  порт $port';
                      return InkWell(
                        onTap: () => _copy(ip),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              const Icon(Icons.wifi,
                                  size: 14, color: Colors.blueGrey),
                              const SizedBox(width: 6),
                              Expanded(
                                child: SelectableText(
                                  text,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(Icons.copy,
                                  size: 14, color: Colors.blueGrey),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 4),
                  Text('Подключено клиентов: ${_clients.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _variablesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Переменные',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _slider('Левое (ω)', 'left', _variables['left']!,
                _minSpeed.toDouble(), _maxSpeed.toDouble(),
                (_maxSpeed - _minSpeed).abs(), (v) => v.round().toString()),
            _slider('Правое (ω)', 'right', _variables['right']!,
                _minSpeed.toDouble(), _maxSpeed.toDouble(),
                (_maxSpeed - _minSpeed).abs(), (v) => v.round().toString()),
            _slider('Радиус колеса', 'wheel_radius', _variables['wheel_radius']!,
                0.01, 0.30, 29, (v) => '${v.toStringAsFixed(2)} м'),
            _slider('База L', 'base_length', _variables['base_length']!,
                0.10, 1.00, 18, (v) => '${v.toStringAsFixed(2)} м'),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, String name, double value, double min,
      double max, int divisions, String Function(double) fmt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label),
              const Spacer(),
              Text(fmt(value),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: fmt(value),
            onChanged: (v) => setState(() => _variables[name] = v),
            onChangeEnd: (v) => _setVariableFromGui(name, v),
          ),
        ],
      ),
    );
  }

  Widget _logsCard() {
    return Card(
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal,
                    color: Colors.greenAccent, size: 16),
                const SizedBox(width: 6),
                const Text('Логи',
                    style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const Spacer(),
                Text('${_logs.length}',
                    style: TextStyle(
                        color: Colors.greenAccent.withValues(alpha: 0.7),
                        fontSize: 12)),
                const SizedBox(width: 4),
                IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.delete_sweep,
                      color: Colors.greenAccent),
                  onPressed: () {
                    setState(() => _logs.clear());
                    _broadcast({'type': 'logs_cleared'});
                  },
                ),
              ],
            ),
            SizedBox(
              height: 180,
              width: double.infinity,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _logs.isEmpty
                    ? const Center(
                        child: Text('Логи появятся здесь…',
                            style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontFamily: 'monospace')))
                    : ListView.builder(
                        controller: _logScroll,
                        itemCount: _logs.length,
                        itemBuilder: (_, i) {
                          final e = _logs[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: e.isError
                                      ? Colors.redAccent
                                      : Colors.white,
                                ),
                                children: [
                                  TextSpan(
                                    text: '[${_fmtTime(e.time)}] ',
                                    style: const TextStyle(
                                        color: Colors.greenAccent),
                                  ),
                                  TextSpan(text: e.message),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}