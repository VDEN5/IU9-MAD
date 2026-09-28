import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

void main() => runApp(const MyApp());


class ServerClient {
  ServerClient._();
  static final ServerClient instance = ServerClient._();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  StreamController<Map<String, dynamic>>? _controller;

  Stream<Map<String, dynamic>>? get messages => _controller?.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await disconnect();

    final ch = WebSocketChannel.connect(Uri.parse(url));
    await ch.ready.timeout(timeout);
    _channel = ch;

    final ctrl = StreamController<Map<String, dynamic>>();
    _controller = ctrl;

    _sub = ch.stream.listen(
      (data) {
        try {
          final decoded = jsonDecode(data as String);
          if (decoded is Map<String, dynamic>) {
            if (!ctrl.isClosed) ctrl.add(decoded);
          }
        } catch (e) {
          if (!ctrl.isClosed) {
            ctrl.add({'type': 'error', 'message': 'Bad JSON: $e'});
          }
        }
      },
      onDone: () {
        if (!ctrl.isClosed) ctrl.add({'type': 'disconnected'});
        _channel = null;
      },
      onError: (e) {
        if (!ctrl.isClosed) {
          ctrl.add({'type': 'error', 'message': 'Socket error: $e'});
        }
      },
      cancelOnError: false,
    );
  }

  void send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  Future<void> disconnect() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
    try {
      await _controller?.close();
    } catch (_) {}
    _controller = null;
  }
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Управление роботом',
      theme: ThemeData(useMaterial3: true),
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final _hostCtrl = TextEditingController(text: '192.168.43.1');
  final _portCtrl = TextEditingController(text: '8080');

  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _connecting = true;
      _error = null;
    });

    final host = _hostCtrl.text.trim();
    final port = int.parse(_portCtrl.text.trim());
    final url = 'ws://$host:$port';

    try {
      await ServerClient.instance.connect(url);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ControlPage()),
      );
    } catch (e) {
      setState(() {
        _error = _humanReadableError(e);
        _connecting = false;
      });
    }
  }

  String _humanReadableError(Object e) {
    final s = e.toString();
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'Сервер не отвечает. Проверьте адрес и порт.';
    }
    if (s.contains('Connection refused')) {
      return 'Сервер отклонил подключение. Запущен ли сервер?';
    }
    if (s.contains('Failed host lookup') || s.contains('SocketException')) {
      return 'Не удаётся найти сервер. Проверьте хост и сеть.';
    }
    return 'Ошибка подключения: $s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подключение к серверу'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.cloud, size: 64, color: Colors.blueGrey),
                  const SizedBox(height: 16),
                  const Text(
                    'Введите адрес WebSocket-сервера\n(с приложения на телефоне)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _hostCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Хост (IP)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Укажите хост' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _portCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Порт',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Укажите порт';
                      final p = int.tryParse(v.trim());
                      if (p == null || p <= 0 || p > 65535) {
                        return 'Некорректный порт';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null) const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _connecting ? null : _connect,
                      icon: _connecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                          _connecting ? 'Подключение...' : 'Подключиться'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class LogEntry {
  final DateTime time;
  final String message;
  final bool isError;

  LogEntry(this.message, {this.isError = false}) : time = DateTime.now();
  LogEntry.at(this.time, this.message, {this.isError = false});
}


class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  static const int _minSpeed = -100;
  static const int _maxSpeed = 100;

  int _left = 0;
  int _right = 0;

  double _wheelRadius = 0.05;
  double _baseLength = 0.3;

  bool _isLoading = false;
  String _lastUpdate = '';

  bool _isDrawing = false;
  Timer? _drawTimer;
  final List<Offset> _pathPoints = [];
  double _robotX = 0.0;
  double _robotY = 0.0;
  double _robotAngle = 0.0;

  static const double _pixelsPerMeter = 100.0;
  static const double _canvasSize = 300.0;

  final List<LogEntry> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  static const int _maxLogs = 300;

  bool _serverReady = false;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _wsSub = ServerClient.instance.messages?.listen(_onServerMessage);
    _initApp();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _drawTimer?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }


  String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  void _scrollLogsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addLogToUi(LogEntry entry) {
    if (!mounted) return;
    setState(() {
      _logs.add(entry);
      if (_logs.length > _maxLogs) {
        _logs.removeRange(0, _logs.length - _maxLogs);
      }
    });
    _scrollLogsToBottom();
  }

  void _log(String message, {bool isError = false}) {
    print('[${_fmtTime(DateTime.now())}] ${isError ? "ERROR " : ""}$message');
    ServerClient.instance.send({
      'type': 'add_log',
      'message': message,
      'isError': isError,
    });
  }


  void _onServerMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'init':
        _applyVariables(msg['variables']);
        _applyLogs(msg['logs']);
        if (mounted) {
          setState(() {
            _serverReady = true;
            _lastUpdate = DateTime.now().toString();
          });
        }
        break;

      case 'state':
        _applyVariables(msg['variables']);
        break;

      case 'variable':
        final name = msg['name'] as String?;
        final value = msg['value'];
        if (name != null && value is num) {
          _applyVariable(name, value.toDouble());
        }
        break;

      case 'logs':
        _applyLogs(msg['logs']);
        break;

      case 'log':
        final l = msg['log'];
        if (l is Map) {
          DateTime dt;
          try {
            dt = DateTime.parse(l['time'].toString()).toLocal();
          } catch (_) {
            dt = DateTime.now();
          }
          _addLogToUi(LogEntry.at(
            dt,
            l['message'].toString(),
            isError: l['isError'] == true,
          ));
        }
        break;

      case 'logs_cleared':
        if (mounted) setState(() => _logs.clear());
        break;

      case 'error':
        _addLogToUi(
            LogEntry('Server error: ${msg['message']}', isError: true));
        break;

      case 'disconnected':
        if (mounted) setState(() => _serverReady = false);
        _addLogToUi(LogEntry('Disconnected from server', isError: true));
        break;
    }
  }

  void _applyVariables(dynamic vars) {
    if (vars is! Map || !mounted) return;
    setState(() {
      for (final e in vars.entries) {
        final name = e.key.toString();
        final value = e.value;
        if (value is num) _applyVariableInternal(name, value.toDouble());
      }
      _serverReady = true;
    });
  }

  void _applyVariable(String name, double value) {
    if (!mounted) return;
    setState(() => _applyVariableInternal(name, value));
  }

  void _applyVariableInternal(String name, double value) {
    switch (name) {
      case 'left':
        _left = value.round();
        break;
      case 'right':
        _right = value.round();
        break;
      case 'wheel_radius':
        _wheelRadius = value;
        break;
      case 'base_length':
        _baseLength = value;
        break;
    }
  }

  void _applyLogs(dynamic raw) {
    if (raw is! List) return;
    final loaded = <LogEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      DateTime dt;
      try {
        dt = DateTime.parse(item['time'].toString()).toLocal();
      } catch (_) {
        dt = DateTime.now();
      }
      loaded.add(LogEntry.at(
        dt,
        item['message'].toString(),
        isError: item['isError'] == true,
      ));
    }
    loaded.sort((a, b) => a.time.compareTo(b.time));
    if (!mounted) return;
    setState(() {
      _logs
        ..clear()
        ..addAll(loaded);
    });
    _scrollLogsToBottom();
  }


  Future<void> _initApp() async {
    setState(() => _isLoading = true);
    ServerClient.instance.send({'type': 'get_all'});
    ServerClient.instance.send({'type': 'get_logs'});
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _lastUpdate = DateTime.now().toString();
    });
    _log('Connected to server');
  }

  Future<void> _loadBoth() async {
    setState(() => _isLoading = true);
    ServerClient.instance.send({'type': 'get_all'});
    ServerClient.instance.send({'type': 'get_logs'});
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _lastUpdate = DateTime.now().toString();
      _isLoading = false;
    });
    _log('Data and logs updated');
  }

  Future<void> _reloadLogs() async {
    ServerClient.instance.send({'type': 'get_logs'});
    _log('Logs reload requested');
  }

  void _clearLogs() {
    setState(() => _logs.clear());
    ServerClient.instance.send({'type': 'clear_logs'});
  }

  void _updateVariable(String name, num newValue) {
    ServerClient.instance.send({
      'type': 'set',
      'name': name,
      'value': newValue,
    });
    _log('$name updated: $newValue');
  }

  void _onLeftSliderChangeEnd(double v) => _updateVariable('left', v.round());
  void _onRightSliderChangeEnd(double v) =>
      _updateVariable('right', v.round());


  double get _omegaL => _left.toDouble();
  double get _omegaR => _right.toDouble();

  double get _vL => _omegaL * _wheelRadius;
  double get _vR => _omegaR * _wheelRadius;

  double get _linearVelocity => (_vL + _vR) / 2.0;
  double get _angularVelocity => (_vL - _vR) / _baseLength;

  String get _radiusInfo {
    final v = _linearVelocity;
    final w = _angularVelocity;
    if (w == 0) {
      if (v == 0) return 'Радиус: не определён (стоим)';
      return 'Радиус: ∞ (прямо)';
    }
    final r = (v / w).abs();
    return 'Радиус: ${r.toStringAsFixed(3)} м';
  }

  String get _angularInfo =>
      'Угловая скорость: ${_angularVelocity.toStringAsFixed(2)} рад/с';
  String get _linearInfo =>
      'Линейная скорость: ${_linearVelocity.toStringAsFixed(3)} м/с';

  String get _movementStatus {
    if (_left == 0 && _right == 0) return 'Стоит';
    if (_left > 0 && _right > 0) return 'Вперёд';
    if (_left < 0 && _right < 0) return 'Назад';
    return 'Поворот на месте';
  }

  String get _turnStatus {
    final delta = _left - _right;
    if (delta > 0) return 'вправо';
    if (delta < 0) return 'влево';
    return 'прямо';
  }

  String get _fullStatus {
    if (_left == 0 && _right == 0) return 'Робот стоит';
    final movement = _movementStatus;
    final turn = _turnStatus;
    if (movement == 'Поворот на месте') return 'Поворот на месте, $turn';
    return '$movement, поворот $turn';
  }


  void _resetPosition() {
    setState(() {
      _robotX = 0.0;
      _robotY = 0.0;
      _robotAngle = 0.0;
      _pathPoints.clear();
    });
  }

  void _startDrawing() {
    if (_isDrawing) return;
    _resetPosition();
    _log('Robot movement started');
    setState(() {
      _isDrawing = true;
      _pathPoints.add(Offset(_robotX, _robotY));
    });

    const double dt = 0.05;
    _drawTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final v = _linearVelocity;
      final w = _angularVelocity;
      if (v.abs() < 1e-6 && w.abs() < 1e-6) return;

      _robotAngle += w * dt;
      _robotX += v * dt * math.cos(_robotAngle);
      _robotY += v * dt * math.sin(_robotAngle);

      if (_robotX.abs() > 5.0 || _robotY.abs() > 5.0) {
        _stopDrawing();
        return;
      }

      setState(() {
        _pathPoints.add(Offset(_robotX, _robotY));
      });
    });
  }

  void _stopDrawing() {
    final wasDrawing = _isDrawing;
    _drawTimer?.cancel();
    _drawTimer = null;
    if (wasDrawing) _log('Movement stopped');
    setState(() => _isDrawing = false);
  }

  void _clearTrajectory() {
    _stopDrawing();
    _resetPosition();
    _log('Trajectory cleared');
    setState(() {});
  }


  Widget _buildCanvas() {
    return Container(
      width: _canvasSize,
      height: _canvasSize,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        color: Colors.white,
      ),
      child: CustomPaint(
        painter: RobotPathPainter(
          points: _pathPoints,
          robotX: _robotX,
          robotY: _robotY,
          robotAngle: _robotAngle,
          pixelsPerMeter: _pixelsPerMeter,
        ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 500),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Logs (synced with server)',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Icon(
                _serverReady ? Icons.cloud_done : Icons.cloud_off,
                color: _serverReady ? Colors.greenAccent : Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '${_logs.length}',
                style: TextStyle(
                  color: Colors.greenAccent.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 180,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(6),
            ),
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'Logs will appear here...',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _logScrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _logScrollController,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final entry = _logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: entry.isError
                                    ? Colors.redAccent
                                    : Colors.white,
                              ),
                              children: [
                                TextSpan(
                                  text: '[${_fmtTime(entry.time)}] ',
                                  style: const TextStyle(
                                      color: Colors.greenAccent),
                                ),
                                TextSpan(text: entry.message),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление роботом'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadBoth,
            tooltip: 'Обновить всё с сервера',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: _isLoading ? null : _reloadLogs,
            tooltip: 'Перезагрузить логи',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearLogs,
            tooltip: 'Очистить логи',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Text('Левое (ω)'),
                    const SizedBox(width: 8),
                    Text('$_left'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _left.toDouble().clamp(
                            _minSpeed.toDouble(), _maxSpeed.toDouble()),
                        min: _minSpeed.toDouble(),
                        max: _maxSpeed.toDouble(),
                        divisions: (_maxSpeed - _minSpeed).abs(),
                        label: _left.toString(),
                        onChanged: _isLoading
                            ? null
                            : (v) => setState(() => _left = v.round()),
                        onChangeEnd:
                            _isLoading ? null : _onLeftSliderChangeEnd,
                      ),
                    ),
                    const Text('100'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Правое (ω)'),
                    const SizedBox(width: 8),
                    Text('$_right'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _right.toDouble().clamp(
                            _minSpeed.toDouble(), _maxSpeed.toDouble()),
                        min: _minSpeed.toDouble(),
                        max: _maxSpeed.toDouble(),
                        divisions: (_maxSpeed - _minSpeed).abs(),
                        label: _right.toString(),
                        onChanged: _isLoading
                            ? null
                            : (v) => setState(() => _right = v.round()),
                        onChangeEnd:
                            _isLoading ? null : _onRightSliderChangeEnd,
                      ),
                    ),
                    const Text('100'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Радиус колеса:'),
                    const SizedBox(width: 8),
                    Text('${_wheelRadius.toStringAsFixed(2)} м'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _wheelRadius,
                        min: 0.01,
                        max: 0.30,
                        divisions: 29,
                        label: _wheelRadius.toStringAsFixed(2),
                        onChanged: (v) => setState(() => _wheelRadius = v),
                        onChangeEnd: (v) => _updateVariable('wheel_radius', v),
                      ),
                    ),
                    const Text('0.30'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('База (L):'),
                    const SizedBox(width: 8),
                    Text('${_baseLength.toStringAsFixed(2)} м'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: _baseLength,
                        min: 0.10,
                        max: 1.00,
                        divisions: 18,
                        label: _baseLength.toStringAsFixed(2),
                        onChanged: (v) => setState(() => _baseLength = v),
                        onChangeEnd: (v) => _updateVariable('base_length', v),
                      ),
                    ),
                    const Text('1.00'),
                  ],
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  Column(
                    children: [
                      Text(
                        _fullStatus,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(_linearInfo,
                          style: const TextStyle(fontSize: 16)),
                      Text(_angularInfo,
                          style: const TextStyle(fontSize: 16)),
                      Text(_radiusInfo,
                          style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _isDrawing ? null : _startDrawing,
                      child: const Text('Рисовать'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isDrawing ? _stopDrawing : null,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red),
                      child: const Text('Стоп'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _clearTrajectory,
                      child: const Text('Очистить'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildCanvas(),
                const SizedBox(height: 12),
                _buildLogPanel(),
                const SizedBox(height: 8),
                Text(
                  'Последнее обновление: $_lastUpdate',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class RobotPathPainter extends CustomPainter {
  final List<Offset> points;
  final double robotX;
  final double robotY;
  final double robotAngle;
  final double pixelsPerMeter;

  RobotPathPainter({
    required this.points,
    required this.robotX,
    required this.robotY,
    required this.robotAngle,
    required this.pixelsPerMeter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final gridPaint = Paint()
      ..color = Colors.grey[200]!
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (double x = -5; x <= 5; x += 0.5) {
      final dx = center.dx + x * pixelsPerMeter;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }
    for (double y = -5; y <= 5; y += 0.5) {
      final dy = center.dy + y * pixelsPerMeter;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    if (points.length > 1) {
      for (int i = 0; i < points.length - 1; i++) {
        final p1 = points[i];
        final p2 = points[i + 1];
        final s1 = Offset(
          center.dx + p1.dx * pixelsPerMeter,
          center.dy - p1.dy * pixelsPerMeter,
        );
        final s2 = Offset(
          center.dx + p2.dx * pixelsPerMeter,
          center.dy - p2.dy * pixelsPerMeter,
        );
        canvas.drawLine(s1, s2, paint);
      }
    }

    if (points.isNotEmpty) {
      final robotScreen = Offset(
        center.dx + robotX * pixelsPerMeter,
        center.dy - robotY * pixelsPerMeter,
      );
      canvas.drawCircle(robotScreen, 6, Paint()..color = Colors.red);
      final dirX = 12 * math.cos(robotAngle);
      final dirY = -12 * math.sin(robotAngle);
      canvas.drawLine(
        robotScreen,
        Offset(robotScreen.dx + dirX, robotScreen.dy + dirY),
        Paint()
          ..color = Colors.red
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RobotPathPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.robotX != robotX ||
        oldDelegate.robotY != robotY ||
        oldDelegate.robotAngle != robotAngle;
  }
}