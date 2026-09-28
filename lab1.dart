import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Управление роботом',
      theme: ThemeData(useMaterial3: true),
      home: const ControlPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
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
  List<Offset> _pathPoints = [];
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
        setState(() {
          if (name == 'left') _left = value;
          else _right = value;
        });
      } else {
        print('Ошибка загрузки $name: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка загрузки $name: $e');
    }
  }

  Future<void> _updateVariable(String name, int newValue) async {
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse('$_baseSendUrl$name/$newValue?key=$_key');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        print('$name обновлён: $newValue');
        await _loadVariable(name);
      } else {
        print('Ошибка обновления $name: ${response.statusCode}');
        await _loadVariable(name);
      }
    } catch (e) {
      print('Ошибка обновления $name: $e');
      await _loadVariable(name);
    }
    setState(() {
      _lastUpdate = DateTime.now().toString();
      _isLoading = false;
    });
  }

  void _onLeftSliderChangeEnd(double newValue) {
    _updateVariable('left', newValue.round());
  }

  void _onRightSliderChangeEnd(double newValue) {
    _updateVariable('right', newValue.round());
  }

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

  String get _angularInfo => 'Угловая скорость: ${_angularVelocity.toStringAsFixed(2)} рад/с';
  String get _linearInfo => 'Линейная скорость: ${_linearVelocity.toStringAsFixed(3)} м/с';

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

      if (v.abs() < 1e-6 && w.abs() < 1e-6) {
        return;
      }

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
    _drawTimer?.cancel();
    _drawTimer = null;
    setState(() {
      _isDrawing = false;
    });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление роботом'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadBoth,
            tooltip: 'Обновить',
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
                        value: _left.toDouble().clamp(_minSpeed.toDouble(), _maxSpeed.toDouble()),
                        min: _minSpeed.toDouble(),
                        max: _maxSpeed.toDouble(),
                        divisions: (_maxSpeed - _minSpeed).abs(),
                        label: _left.toString(),
                        onChanged: _isLoading
                            ? null
                            : (newValue) {
                          setState(() {
                            _left = newValue.round();
                          });
                        },
                        onChangeEnd: _isLoading ? null : _onLeftSliderChangeEnd,
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
                        value: _right.toDouble().clamp(_minSpeed.toDouble(), _maxSpeed.toDouble()),
                        min: _minSpeed.toDouble(),
                        max: _maxSpeed.toDouble(),
                        divisions: (_maxSpeed - _minSpeed).abs(),
                        label: _right.toString(),
                        onChanged: _isLoading
                            ? null
                            : (newValue) {
                          setState(() {
                            _right = newValue.round();
                          });
                        },
                        onChangeEnd: _isLoading ? null : _onRightSliderChangeEnd,
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
                        onChanged: (newValue) {
                          setState(() {
                            _wheelRadius = newValue;
                          });
                        },
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
                        onChanged: (newValue) {
                          setState(() {
                            _baseLength = newValue;
                          });
                        },
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
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
        final screenP1 = Offset(
          center.dx + p1.dx * pixelsPerMeter,
          center.dy - p1.dy * pixelsPerMeter,
        );
        final screenP2 = Offset(
          center.dx + p2.dx * pixelsPerMeter,
          center.dy - p2.dy * pixelsPerMeter,
        );
        canvas.drawLine(screenP1, screenP2, paint);
      }
    }

    if (points.isNotEmpty) {
      final robotScreen = Offset(
        center.dx + robotX * pixelsPerMeter,
        center.dy - robotY * pixelsPerMeter,
      );
      final robotPaint = Paint()..color = Colors.red;
      canvas.drawCircle(robotScreen, 6, robotPaint);
      final dirX = 12 * math.cos(robotAngle);
      final dirY = -12 * math.sin(robotAngle);
      canvas.drawLine(
        robotScreen,
        Offset(robotScreen.dx + dirX, robotScreen.dy + dirY),
        Paint()..color = Colors.red ..strokeWidth = 2,
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