import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mysql1/mysql1.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Лабораторные работы',
      theme: ThemeData(useMaterial3: true),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int? _current; 
  final Set<int> _visited = {};
  final Map<int, Widget> _cache = {};

  Widget _getLab(int index) {
    return _cache.putIfAbsent(index, () {
      switch (index) {
        case 0:
          return const Lab0Page();
        case 1:
          return const Lab1Page();
        case 2:
          return const Lab2Page();
      }
      throw StateError('Invalid lab index: $index');
    });
  }

  Widget _buildBody() {
    if (_current == null) return const WelcomeScreen();
    _visited.add(_current!);
    return IndexedStack(
      index: _current!,
      children: List.generate(3, (i) {
        if (_visited.contains(i)) return _getLab(i);
        return const SizedBox.shrink();
      }),
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _current == index;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: TextButton(
        onPressed: () => setState(() => _current = index),
        style: TextButton.styleFrom(
          backgroundColor: selected ? scheme.primary : scheme.primaryContainer,
          foregroundColor:
              selected ? scheme.onPrimary : scheme.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Лабораторные работы'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Главная',
            onPressed: () => setState(() => _current = null),
          ),
          _tabButton('Лаб0', 0),
          _tabButton('Лаб1', 1),
          _tabButton('Лаб2', 2),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.science, size: 96, color: scheme.primary),
            const SizedBox(height: 24),
            const Text(
              'Добро пожаловать!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Выберите лабораторную работу в меню сверху',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class Lab0Page extends StatefulWidget {
  const Lab0Page({super.key});

  @override
  State<Lab0Page> createState() => _Lab0PageState();
}

class _Lab0PageState extends State<Lab0Page> {
  static const String _key = '???';
  static const int _minValue = -100;
  static const int _maxValue = 100;

  int _counter = 0;
  bool _isLoading = false;
  String _lastUpdate = '';

  final String _baseReadUrl = 'http://iocontrol.ru/api/readData/omgomg/counter';
  final String _baseSendUrl = 'http://iocontrol.ru/api/sendData/omgomg/counter';

  @override
  void initState() {
    super.initState();
    _loadCounter();
  }

  Future<void> _loadCounter() async {
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse('$_baseReadUrl?key=$_key');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _counter = int.tryParse(data['value']?.toString() ?? '0') ?? 0;
          _lastUpdate = DateTime.now().toString();
        });
      } else {
        debugPrint('Ошибка загрузки: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _updateCounter(int newValue) async {
    setState(() {
      _counter = newValue;
      _isLoading = true;
    });
    try {
      final url = Uri.parse('$_baseSendUrl/$newValue?key=$_key');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        debugPrint('Счётчик обновлён: $newValue');
      } else {
        debugPrint('Ошибка обновления: ${response.statusCode}');
      }
      await _loadCounter();
    } catch (e) {
      debugPrint('Ошибка обновления: $e');
      await _loadCounter();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _onSliderChangeEnd(double newValue) {
    _updateCounter(newValue.round());
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                const Text(
                  'Счётчик (iocontrol)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _loadCounter,
                  tooltip: 'Обновить',
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Текущее значение:', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Text(
                '$_counter',
                style: const TextStyle(
                    fontSize: 72, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 40),
            Row(
              children: [
                Text('$_minValue'),
                Expanded(
                  child: Slider(
                    value: _counter.toDouble().clamp(
                        _minValue.toDouble(), _maxValue.toDouble()),
                    min: _minValue.toDouble(),
                    max: _maxValue.toDouble(),
                    divisions: (_maxValue - _minValue).abs(),
                    label: _counter.toString(),
                    onChanged: _isLoading
                        ? null
                        : (v) => setState(() => _counter = v.round()),
                    onChangeEnd: _isLoading ? null : _onSliderChangeEnd,
                  ),
                ),
                Text('$_maxValue'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Последнее обновление: $_lastUpdate',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class Lab1Page extends StatefulWidget {
  const Lab1Page({super.key});

  @override
  State<Lab1Page> createState() => _Lab1PageState();
}

class _Lab1PageState extends State<Lab1Page> {
  static const String _key = '???';
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

  final String _baseReadUrl = 'http://iocontrol.ru/api/readData/omgomg/';
  final String _baseSendUrl = 'http://iocontrol.ru/api/sendData/omgomg/';

  @override
  void initState() {
    super.initState();
    _loadBoth();
    _resetPosition();
  }

  @override
  void dispose() {
    _drawTimer?.cancel();
    super.dispose();
  }

  void _resetPosition() {
    setState(() {
      _robotX = 0.0;
      _robotY = 0.0;
      _robotAngle = 0.0;
      _pathPoints.clear();
    });
  }

  Future<void> _loadBoth() async {
    setState(() => _isLoading = true);
    await Future.wait([_loadVariable('left'), _loadVariable('right')]);
    if (!mounted) return;
    setState(() {
      _lastUpdate = DateTime.now().toString();
      _isLoading = false;
    });
  }

  Future<void> _loadVariable(String name) async {
    try {
      final url = Uri.parse('$_baseReadUrl$name?key=$_key');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final value = int.tryParse(data['value']?.toString() ?? '0') ?? 0;
        if (!mounted) return;
        setState(() {
          if (name == 'left') {
            _left = value;
          } else {
            _right = value;
          }
        });
      } else {
        debugPrint('Ошибка загрузки $name: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Ошибка загрузки $name: $e');
    }
  }

  Future<void> _updateVariable(String name, int newValue) async {
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse('$_baseSendUrl$name/$newValue?key=$_key');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        debugPrint('$name обновлён: $newValue');
      } else {
        debugPrint('Ошибка обновления $name: ${response.statusCode}');
      }
      await _loadVariable(name);
    } catch (e) {
      debugPrint('Ошибка обновления $name: $e');
      await _loadVariable(name);
    }
    if (!mounted) return;
    setState(() {
      _lastUpdate = DateTime.now().toString();
      _isLoading = false;
    });
  }

  void _onLeftSliderChangeEnd(double v) => _updateVariable('left', v.round());
  void _onRightSliderChangeEnd(double v) => _updateVariable('right', v.round());

  double get _omegaL => _left.toDouble();
  double get _omegaR => _right.toDouble();

  double get _vL => _omegaL * _wheelRadius;
  double get _vR => _omegaR * _wheelRadius;

  double get _linearVelocity => (_vL + _vR) / 2.0;
  double get _angularVelocity => (_vL - _vR) / _baseLength;

  String get _radiusInfo {
    final double v = _linearVelocity;
    final double w = _angularVelocity;
    if (w == 0) {
      if (v == 0) return 'Радиус: не определён (стоим)';
      return 'Радиус: ∞ (прямо)';
    }
    final double r = (v / w).abs();
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
    final int delta = _left - _right;
    if (delta > 0) return 'вправо';
    if (delta < 0) return 'влево';
    return 'прямо';
  }

  String get _fullStatus {
    if (_left == 0 && _right == 0) return 'Робот стоит';
    final movement = _movementStatus;
    final turn = _turnStatus;
    if (movement == 'Поворот на месте') {
      return 'Поворот на месте, $turn';
    }
    return '$movement, поворот $turn';
  }

  void _startDrawing() {
    if (_isDrawing) return;
    _resetPosition();
    setState(() {
      _isDrawing = true;
      _pathPoints.add(Offset(_robotX, _robotY));
    });

    const double dt = 0.05;
    _drawTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final double v = _linearVelocity;
      final double w = _angularVelocity;

      if (v.abs() < 1e-6 && w.abs() < 1e-6) return;

      _robotAngle += w * dt;
      _robotX += v * dt * math.cos(_robotAngle);
      _robotY += v * dt * math.sin(_robotAngle);

      if (_robotX.abs() > 5.0 || _robotY.abs() > 5.0) {
        _stopDrawing();
        return;
      }

      if (!mounted) return;
      setState(() {
        _pathPoints.add(Offset(_robotX, _robotY));
      });
    });
  }

  void _stopDrawing() {
    _drawTimer?.cancel();
    _drawTimer = null;
    if (!mounted) return;
    setState(() => _isDrawing = false);
  }

  void _clearTrajectory() {
    _stopDrawing();
    _resetPosition();
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

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Text(
                    'Управление роботом (iocontrol)',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _isLoading ? null : _loadBoth,
                    tooltip: 'Обновить',
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                    Text(_linearInfo, style: const TextStyle(fontSize: 16)),
                    Text(_angularInfo, style: const TextStyle(fontSize: 16)),
                    Text(_radiusInfo, style: const TextStyle(fontSize: 16)),
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
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
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
              const SizedBox(height: 8),
              Text(
                'Последнее обновление: $_lastUpdate',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DbConfig {
  final String host;
  final int port;
  final String user;
  final String password;
  final String db;

  const DbConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.db,
  });
}

class Database {
  static MySqlConnection? _conn;
  static DbConfig? _config;

  static Future<MySqlConnection> connect(DbConfig config) async {
    await close();
    _config = config;
    _conn = await MySqlConnection.connect(ConnectionSettings(
      host: config.host,
      port: config.port,
      user: config.user,
      password: config.password,
      db: config.db,
    ));
    return _conn!;
  }

  static Future<MySqlConnection> getConnection() async {
    if (_conn != null) {
      try {
        await _conn!.query('SELECT 1');
        return _conn!;
      } catch (_) {
        try {
          await _conn!.close();
        } catch (_) {}
        _conn = null;
      }
    }
    if (_config == null) {
      throw Exception('No active DB connection');
    }
    _conn = await MySqlConnection.connect(ConnectionSettings(
      host: _config!.host,
      port: _config!.port,
      user: _config!.user,
      password: _config!.password,
      db: _config!.db,
    ));
    return _conn!;
  }

  static Future<void> close() async {
    try {
      await _conn?.close();
    } catch (_) {}
    _conn = null;
  }
}

class Lab2Page extends StatefulWidget {
  const Lab2Page({super.key});

  @override
  State<Lab2Page> createState() => _Lab2PageState();
}

class _Lab2PageState extends State<Lab2Page> {
  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      await Database.connect(const DbConfig(
        host: 'students.yss.su',
        port: 3306,
        user: 'iu9mobile',
        password: 'bmstubmstu123',
        db: 'iu9mobile',
      ));
      final conn = await Database.getConnection();
      await conn.query('SELECT 1');
      if (!mounted) return;
      setState(() => _connecting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _connecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Подключение к базе данных...'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Не удалось подключиться к БД',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _connecting = true;
                    _error = null;
                  });
                  _connect();
                },
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    return const Lab2ControlPage();
  }
}

class LogEntry {
  final DateTime time;
  final String message;
  final bool isError;

  LogEntry(this.message, {this.isError = false}) : time = DateTime.now();
  LogEntry.fromDb(this.time, this.message, {this.isError = false});
}

class Lab2ControlPage extends StatefulWidget {
  const Lab2ControlPage({super.key});

  @override
  State<Lab2ControlPage> createState() => _Lab2ControlPageState();
}

class _Lab2ControlPageState extends State<Lab2ControlPage> {
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

  static const String _table = 'Lab2VDEN';
  static const String _logTable = 'Lab2VDEN_logs';

  final List<LogEntry> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  static const int _maxLogs = 300;

  bool _logsTableReady = false;
  final List<LogEntry> _pendingLogs = [];
  bool _flushScheduled = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _drawTimer?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _fmtMysql(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
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
    final entry = LogEntry(message, isError: isError);
    debugPrint('[${_fmtTime(entry.time)}] ${isError ? "ERROR " : ""}$message');
    _addLogToUi(entry);

    if (!_logsTableReady) {
      _pendingLogs.add(entry);
      return;
    }
    _insertLog(entry);
  }

  void _insertLog(LogEntry entry) {
    Database.getConnection()
        .then((conn) => conn.query(
              'INSERT INTO $_logTable (log_time, message) VALUES (?, ?)',
              [_fmtMysql(entry.time), entry.message],
            ))
        .catchError((e) {
      debugPrint('INSERT log failed: $e');
      _addLogToUi(LogEntry('Error writing log to DB: $e', isError: true));
    });
  }

  Future<void> _flushPendingLogs() async {
    if (_flushScheduled) return;
    _flushScheduled = true;
    final snapshot = List<LogEntry>.from(_pendingLogs);
    _pendingLogs.clear();
    for (final entry in snapshot) {
      try {
        final conn = await Database.getConnection();
        await conn.query(
          'INSERT INTO $_logTable (log_time, message) VALUES (?, ?)',
          [_fmtMysql(entry.time), entry.message],
        );
      } catch (e) {
        debugPrint('Flush log failed: $e');
      }
    }
    _flushScheduled = false;
  }

  Future<void> _loadLogsFromDb() async {
    try {
      final conn = await Database.getConnection();
      final results = await conn.query(
        'SELECT log_time, message FROM $_logTable ORDER BY id DESC LIMIT ?',
        [_maxLogs],
      );
      final loaded = <LogEntry>[];
      for (var row in results) {
        final rawTime = row[0];
        final msg = row[1].toString();
        DateTime dt;
        if (rawTime is DateTime) {
          dt = rawTime;
        } else {
          try {
            dt = DateTime.parse(rawTime.toString());
          } catch (_) {
            dt = DateTime.now();
          }
        }
        loaded.add(LogEntry.fromDb(dt, msg));
      }
      loaded.sort((a, b) => a.time.compareTo(b.time));

      if (!mounted) return;
      setState(() {
        _logs
          ..clear()
          ..addAll(loaded);
      });
      _scrollLogsToBottom();
      debugPrint('Loaded ${loaded.length} logs from DB');
    } catch (e) {
      debugPrint('Load logs from DB failed: $e');
      _addLogToUi(LogEntry('Error loading logs from DB: $e', isError: true));
    }
  }

  Future<void> _initApp() async {
    setState(() => _isLoading = true);
    try {
      final conn = await Database.getConnection();

      await conn.query('''
        CREATE TABLE IF NOT EXISTS $_table (
          id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
          variable_name VARCHAR(50) NOT NULL UNIQUE,
          variable_value DOUBLE NOT NULL
        )
      ''');

      await conn.query('''
        CREATE TABLE IF NOT EXISTS $_logTable (
          id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
          log_time DATETIME NOT NULL,
          message TEXT NOT NULL
        )
      ''');

      final defaults = {
        'left': 0.0,
        'right': 0.0,
        'wheel_radius': 0.05,
        'base_length': 0.3,
      };
      for (final e in defaults.entries) {
        await conn.query(
          'INSERT IGNORE INTO $_table (variable_name, variable_value) VALUES (?, ?)',
          [e.key, e.value],
        );
      }

      await _loadLogsFromDb();
      await _loadVariable('left');
      await _loadVariable('right');
      await _loadVariable('wheel_radius');
      await _loadVariable('base_length');

      _logsTableReady = true;
      await _flushPendingLogs();

      _log('Tables $_table and $_logTable ready');
      _log('Logs loaded from DB (${_logs.length})');
    } catch (e) {
      _logsTableReady = false;
      _addLogToUi(LogEntry('DB init error: $e', isError: true));
    }
    if (!mounted) return;
    setState(() {
      _lastUpdate = DateTime.now().toString();
      _isLoading = false;
    });
  }

  Future<void> _reloadLogs() async {
    await _loadLogsFromDb();
    _log('Logs reloaded from DB');
  }

  Future<void> _loadBoth() async {
    setState(() => _isLoading = true);
    await _loadLogsFromDb();
    await Future.wait([
      _loadVariable('left'),
      _loadVariable('right'),
      _loadVariable('wheel_radius'),
      _loadVariable('base_length'),
    ]);
    _log('Data and logs updated from DB');
    if (!mounted) return;
    setState(() {
      _lastUpdate = DateTime.now().toString();
      _isLoading = false;
    });
  }

  Future<void> _loadVariable(String name) async {
    try {
      final conn = await Database.getConnection();
      final results = await conn.query(
        'SELECT variable_value FROM $_table WHERE variable_name = ?',
        [name],
      );
      if (results.isEmpty) return;
      final value = (results.first[0] as num).toDouble();

      if (!mounted) return;
      setState(() {
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
      });
    } catch (e) {
      _log('Error loading $name: $e', isError: true);
    }
  }

  Future<void> _updateVariable(String name, num newValue) async {
    setState(() => _isLoading = true);
    try {
      final conn = await Database.getConnection();
      await conn.query(
        'UPDATE $_table SET variable_value = ? WHERE variable_name = ?',
        [newValue, name],
      );
      _log('$name updated: $newValue');
    } catch (e) {
      _log('Error updating $name: $e', isError: true);
      await _loadVariable(name);
    }
    if (!mounted) return;
    setState(() {
      _lastUpdate = DateTime.now().toString();
      _isLoading = false;
    });
  }

  Future<void> _clearLogs() async {
    setState(() => _logs.clear());
    try {
      final conn = await Database.getConnection();
      await conn.query('DELETE FROM $_logTable');
      _log('Logs cleared (UI and DB)');
    } catch (e) {
      _log('Failed to clear logs in DB: $e', isError: true);
    }
  }

  void _onLeftSliderChangeEnd(double v) => _updateVariable('left', v.round());
  void _onRightSliderChangeEnd(double v) => _updateVariable('right', v.round());

  double get _omegaL => _left.toDouble();
  double get _omegaR => _right.toDouble();

  double get _vL => _omegaL * _wheelRadius;
  double get _vR => _omegaR * _wheelRadius;

  double get _linearVelocity => (_vL + _vR) / 2.0;
  double get _angularVelocity => (_vL - _vR) / _baseLength;

  String get _radiusInfo {
    final double v = _linearVelocity;
    final double w = _angularVelocity;
    if (w == 0) {
      if (v == 0) return 'Радиус: не определён (стоим)';
      return 'Радиус: ∞ (прямо)';
    }
    final double r = (v / w).abs();
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
    final int delta = _left - _right;
    if (delta > 0) return 'вправо';
    if (delta < 0) return 'влево';
    return 'прямо';
  }

  String get _fullStatus {
    if (_left == 0 && _right == 0) return 'Робот стоит';
    final movement = _movementStatus;
    final turn = _turnStatus;
    if (movement == 'Поворот на месте') {
      return 'Поворот на месте, $turn';
    }
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
      final double v = _linearVelocity;
      final double w = _angularVelocity;

      if (v.abs() < 1e-6 && w.abs() < 1e-6) return;

      _robotAngle += w * dt;
      _robotX += v * dt * math.cos(_robotAngle);
      _robotY += v * dt * math.sin(_robotAngle);

      if (_robotX.abs() > 5.0 || _robotY.abs() > 5.0) {
        _stopDrawing();
        return;
      }

      if (!mounted) return;
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
    if (!mounted) return;
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
                'Logs (synced with DB)',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Icon(
                _logsTableReady ? Icons.cloud_done : Icons.cloud_off,
                color: _logsTableReady ? Colors.greenAccent : Colors.orange,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Text(
                    'Управление роботом (MySQL)',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _isLoading ? null : _loadBoth,
                    tooltip: 'Обновить всё из БД',
                  ),
                  IconButton(
                    icon: const Icon(Icons.cloud_download),
                    onPressed: _isLoading ? null : _reloadLogs,
                    tooltip: 'Перезагрузить логи из БД',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep),
                    onPressed: _clearLogs,
                    tooltip: 'Очистить логи',
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                    Text(_linearInfo, style: const TextStyle(fontSize: 16)),
                    Text(_angularInfo, style: const TextStyle(fontSize: 16)),
                    Text(_radiusInfo, style: const TextStyle(fontSize: 16)),
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
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
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