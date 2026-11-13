import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bouncing Ball 2D',
    theme: ThemeData.dark(useMaterial3: true),
    home: const SimPage(),
  );
}

class SimPage extends StatefulWidget {
  const SimPage({super.key});
  @override
  State<SimPage> createState() => _SimPageState();
}

class _SimPageState extends State<SimPage> with SingleTickerProviderStateMixin {
  double v0       = 12.0;  
  double angleDeg = 55.0;   
  double delta    = 0.75;   
  double g        = 9.81;   

  double x = 0, y = 0;
  double vx = 0, vy = 0;
  double simTime = 0;
  int    bounces = 0;
  bool   running = false;
  bool   finished = false;

  double camX = 0;
  static const double pxPerMeter = 45.0;

  final List<Offset> trail = <Offset>[];

  double canvasW = 800;
  double canvasH = 400;

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

  double get _vx0 => v0 * cos(angleDeg * pi / 180.0);
  double get _vy0 => v0 * sin(angleDeg * pi / 180.0);
  double get _apex0 => _vy0 * _vy0 / (2 * g);

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _reset() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    final rad = angleDeg * pi / 180.0;
    setState(() {
      x = 0;
      y = 0;
      vx = v0 * cos(rad);
      vy = v0 * sin(rad);
      simTime = 0;
      bounces = 0;
      camX = 0;
      running = false;
      finished = false;
      trail
        ..clear()
        ..add(const Offset(0, 0));
    });
  }

  void _start() {
    if (running) return;
    if (finished) _reset();
    running = true;
    finished = false;
    _lastElapsed = Duration.zero;
    _ticker?.dispose();
    _ticker = createTicker(_onTick)..start();
    setState(() {});
  }

  void _pause() {
    running = false;
    _ticker?.stop();
    setState(() {});
  }

  void _toggle() => running ? _pause() : _start();

  void _onTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt > 0.033) dt = 0.033;

    const int subSteps = 6;
    for (int i = 0; i < subSteps; i++) {
      _step(dt / subSteps);
    }
    setState(() {});
  }

  void _step(double dt) {
    vy -= g * dt;
    x  += vx * dt;
    y  += vy * dt;
    simTime += dt;

    if (y <= 0 && vy < 0) {
      y = 0;
      vy = -vy * delta;
      bounces++;

      if (vy < 0.15) {
        vy = 0;
      }
    }

    trail.add(Offset(x, y));
    if (trail.length > 60000) {
      trail.removeRange(0, 20000);
    }

    final worldWidth = canvasW / pxPerMeter;
    final desired = x - worldWidth * 0.35;
    if (desired > camX) camX = desired;
    if (camX < 0) camX = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Полёт мяча с отскоками'),
        actions: [
          IconButton(
            tooltip: 'Сброс',
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildControls(),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, c) {
                  canvasW = c.maxWidth;
                  canvasH = c.maxHeight;
                  return GestureDetector(
                    onTap: _toggle,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(color: const Color(0xFF0A1220)),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _TrajectoryPainter(
                              trail: trail,
                              ball: Offset(x, y),
                              camX: camX,
                              pxPerMeter: pxPerMeter,
                              vx: vx,
                              vy: vy,
                              running: running,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                        Positioned(
                          left: 8,
                          top: 8,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '-g·t²/2 + v·t·sin φ - h = 0\n'
                                    'h_max = (v·sin φ)² / (2g)\n'
                                    'v_x = const,  v_y → δ·v_y',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _buildStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.black26,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          _slider(
            'v₀ (м/с)',
            v0, 1, 40, 39,
                (v) {
              setState(() => v0 = v);
              if (!running) _reset();
            },
            v0.toStringAsFixed(1),
          ),
          _slider(
            'Угол φ (°)',
            angleDeg, 1, 89, 88,
                (v) {
              setState(() => angleDeg = v);
              if (!running) _reset();
            },
            '${angleDeg.toStringAsFixed(0)}°',
          ),
          _slider(
            'δ (остаток v_y при отскоке)',
            delta, 0.10, 1.00, 18,
                (v) => setState(() => delta = v),
            delta.toStringAsFixed(2),
          ),
          _slider(
            'g (м/с²)',
            g, 1, 25, 24,
                (v) {
              setState(() => g = v);
              if (!running) _reset();
            },
            g.toStringAsFixed(1),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Апекс 1-й параболы: ${_apex0.toStringAsFixed(2)} м, '
                        'гориз. дальность 1-го полёта: '
                        '${(2 * _vx0 * _vy0 / g).toStringAsFixed(2)} м',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
      String label,
      double value,
      double min,
      double max,
      int divisions,
      ValueChanged<double> onChanged,
      String valueText,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 190,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              valueText,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    final v = sqrt(vx * vx + vy * vy);
    return Container(
      color: Colors.black38,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(
              running
                  ? Icons.pause
                  : (finished ? Icons.replay : Icons.play_arrow),
            ),
            color: Colors.orangeAccent,
          ),
          Expanded(
            child: Text(
              't=${simTime.toStringAsFixed(2)} с   '
                  'x=${x.toStringAsFixed(2)} м   '
                  'y=${y.toStringAsFixed(2)} м   '
                  'vx=${vx.toStringAsFixed(2)} м/с   '
                  'vy=${vy.toStringAsFixed(2)} м/с   '
                  'отскоков: $bounces',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  final List<Offset> trail;
  final Offset ball;
  final double camX;
  final double pxPerMeter;
  final double vx;
  final double vy;
  final bool running;

  _TrajectoryPainter({
    required this.trail,
    required this.ball,
    required this.camX,
    required this.pxPerMeter,
    required this.vx,
    required this.vy,
    required this.running,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset w2s(double wx, double wy) {
      final sx = (wx - camX) * pxPerMeter;
      final sy = size.height - wy * pxPerMeter;
      return Offset(sx, sy);
    }

    final groundY = size.height;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(color: Colors.white30, fontSize: 10);

    final startMeter = (camX / 5).floorToDouble() * 5.0;
    for (double m = startMeter; ; m += 5.0) {
      final sx = (m - camX) * pxPerMeter;
      if (sx > size.width + 60) break;
      if (sx < -60) continue;
      canvas.drawLine(Offset(sx, 0), Offset(sx, groundY), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${m.toInt()}м', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(sx + 3, groundY - 14));
    }

    final groundPaint = Paint()
      ..color = const Color(0xFF3C7A3C)
      ..strokeWidth = 2;
    canvas.drawLine(
        Offset(0, groundY - 1), Offset(size.width, groundY - 1), groundPaint);

    if (trail.length > 1) {
      final path = Path();
      final startIdx = _findFirstVisibleIndex();
      bool started = false;
      for (int i = startIdx; i < trail.length; i++) {
        final p = trail[i];
        final s = w2s(p.dx, p.dy);
        if (s.dx < -50) continue;
        if (s.dx > size.width + 50) break;
        if (!started) {
          path.moveTo(s.dx, s.dy);
          started = true;
        } else {
          path.lineTo(s.dx, s.dy);
        }
      }
      final trailPaint = Paint()
        ..color = const Color(0xFFFFB74D).withOpacity(0.9)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, trailPaint);
    }

    final ballScreen = w2s(ball.dx, ball.dy);
    _drawDashedLine(
      canvas,
      ballScreen,
      Offset(ballScreen.dx, groundY),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1,
      dash: 5,
      gap: 4,
    );

    if (running || vx.abs() + vy.abs() > 0.01) {
      const arrowScale = 6.0;
      final tip = ballScreen + Offset(vx * arrowScale, -vy * arrowScale);
      final arrowPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.9)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(ballScreen, tip, arrowPaint);
      final dir = (tip - ballScreen);
      final len = dir.distance;
      if (len > 8) {
        final u = dir / len;
        final perp = Offset(-u.dy, u.dx);
        final p1 = tip - u * 8 + perp * 4;
        final p2 = tip - u * 8 - perp * 4;
        final path = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close();
        canvas.drawPath(path, arrowPaint);
      }
    }

    canvas.drawCircle(
      ballScreen,
      14,
      Paint()..color = const Color(0xFFFF5252).withOpacity(0.25),
    );
    canvas.drawCircle(
      ballScreen,
      8,
      Paint()..color = const Color(0xFFFF5252),
    );
    canvas.drawCircle(
      ballScreen + const Offset(-2.5, -2.5),
      2.5,
      Paint()..color = Colors.white.withOpacity(0.9),
    );
  }

  int _findFirstVisibleIndex() {
    int lo = 0, hi = trail.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      final sx = (trail[mid].dx - camX) * pxPerMeter;
      if (sx < -50) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _drawDashedLine(
      Canvas canvas,
      Offset a,
      Offset b,
      Paint p, {
        double dash = 5,
        double gap = 4,
      }) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    double d = 0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * (d + dash).clamp(0, total);
      canvas.drawLine(s, e, p);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter old) => true;
}