import 'package:flutter/material.dart';
import 'dart:math' as math;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Вариант 39 — вращающийся круг с секторами',
      theme: ThemeData(useMaterial3: true),
      home: const SectorPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SectorPage extends StatefulWidget {
  const SectorPage({super.key});

  @override
  State<SectorPage> createState() => _SectorPageState();
}

class _SectorPageState extends State<SectorPage>
    with SingleTickerProviderStateMixin {
  int _diameter = 250;
  int _sectors = 8;
  int _seed = 42;
  bool _showBorders = true;

  late final AnimationController _rotController;
  bool _autoRotate = true;
  double _speed = 1.0;      
  double _manualAngle = 0.0; 

  @override
  void initState() {
    super.initState();
    _rotController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(); 
  }

  @override
  void dispose() {
    _rotController.dispose();
    super.dispose();
  }

  void _randomizeColors() {
    setState(() => _seed = math.Random().nextInt(1 << 30));
  }

  double get _totalAngleRad {
    final auto = _autoRotate
        ? 2 * math.pi * _speed * _rotController.value
        : 0.0;
    final manual = _manualAngle * math.pi / 180.0;
    return auto + manual;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вращающийся круг с секторами'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: 360,
                height: 360,
                child: AnimatedBuilder(
                  animation: _rotController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: SectorPainter(
                        diameter: _diameter.toDouble(),
                        sectors: _sectors,
                        seed: _seed,
                        showBorders: _showBorders,
                        angle: _totalAngleRad,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              _sliderRow(
                label: 'Диаметр d',
                value: _diameter.toDouble(),
                min: 50,
                max: 340,
                divisions: 290,
                display: '$_diameter px',
                onChanged: (v) => setState(() => _diameter = v.round()),
              ),

              _sliderRow(
                label: 'Секторов n',
                value: _sectors.toDouble(),
                min: 2,
                max: 60,
                divisions: 58,
                display: '$_sectors',
                onChanged: (v) => setState(() => _sectors = v.round()),
              ),

              _sliderRow(
                label: 'Скорость',
                value: _speed,
                min: 0.0,
                max: 5.0,
                divisions: 100,
                display: '${_speed.toStringAsFixed(2)} об/с',
                onChanged: (v) => setState(() => _speed = v),
              ),

              _sliderRow(
                label: 'Угол',
                value: _manualAngle,
                min: 0,
                max: 360,
                divisions: 360,
                display: '${_manualAngle.round()}°',
                onChanged: (v) => setState(() => _manualAngle = v),
              ),

              SwitchListTile(
                title: const Text('Автоматическое вращение'),
                value: _autoRotate,
                onChanged: (v) => setState(() => _autoRotate = v),
              ),

              SwitchListTile(
                title: const Text('Показывать границы секторов'),
                value: _showBorders,
                onChanged: (v) => setState(() => _showBorders = v),
              ),

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _randomizeColors,
                    icon: const Icon(Icons.casino),
                    label: const Text('Новые цвета'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _manualAngle = 0),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Сброс угла'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 90,
          child: Text(display, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}


class SectorPainter extends CustomPainter {
  final double diameter;
  final int sectors;
  final int seed;
  final bool showBorders;
  final double angle;

  SectorPainter({
    required this.diameter,
    required this.sectors,
    required this.seed,
    required this.showBorders,
    required this.angle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (sectors <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = diameter / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);

    final rnd = math.Random(seed);
    final sweep = 2 * math.pi / sectors;
    double start = -math.pi / 2;

    for (int i = 0; i < sectors; i++) {
      final color = Color.fromARGB(
        255,
        60 + rnd.nextInt(196),
        60 + rnd.nextInt(196),
        60 + rnd.nextInt(196),
      );

      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawArc(rect, start, sweep, true, fillPaint);

      if (showBorders) {
        final borderPaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black54
          ..strokeWidth = 1;
        canvas.drawArc(rect, start, sweep, true, borderPaint);
      }

      start += sweep;
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black
        ..strokeWidth = 2,
    );

    canvas.restore();

    canvas.drawCircle(
      center,
      3,
      Paint()..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(covariant SectorPainter old) {
    return old.diameter != diameter ||
        old.sectors != sectors ||
        old.seed != seed ||
        old.showBorders != showBorders ||
        old.angle != angle;
  }
}