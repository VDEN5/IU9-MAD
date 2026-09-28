import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Покоординатный спуск',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Покоординатный спуск'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Заготовка'),
                Tab(text: 'Экли'),
                Tab(text: 'Букин N.6'),
                Tab(text: 'Леви N.13'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              ParaboloidTab(),
              AckleyTab(),
              BukinTab(),
              LevyTab(),
            ],
          ),
        ),
      ),
    );
  }
}


class Mini3DView extends StatefulWidget {
  final double Function(double x, double y) f;
  final double xMin, xMax, yMin, yMax;
  final int gridN;
  final List<vm.Vector3> trajectory;
  final double axisXLen, axisYLen, axisZLen;
  final double minZ, maxZ;
  final vm.Vector3? axisOrigin;
  final double cutZ;

  const Mini3DView({
    Key? key,
    required this.f,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    this.gridN = 20,
    required this.trajectory,
    required this.axisXLen,
    required this.axisYLen,
    required this.axisZLen,
    required this.minZ,
    required this.maxZ,
    this.axisOrigin,
    required this.cutZ,
  }) : super(key: key);

  @override
  State<Mini3DView> createState() => _Mini3DViewState();
}

class _Mini3DViewState extends State<Mini3DView> {
  double _rotX = -0.5;
  double _rotY = 0.5;
  double _zoom = 1.0;
  double _lastScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (_) => _lastScale = 1.0,
      onScaleUpdate: (d) {
        setState(() {
          _rotX += d.focalPointDelta.dy * 0.008;
          _rotY += d.focalPointDelta.dx * 0.008;
          if (d.scale != 1.0) {
            final delta = d.scale / _lastScale;
            _zoom = (_zoom * delta).clamp(0.2, 5.0);
            _lastScale = d.scale;
          }
        });
      },
      child: ClipRect(
        child: CustomPaint(
          painter: _Mini3DPainter(
            f: widget.f,
            xMin: widget.xMin,
            xMax: widget.xMax,
            yMin: widget.yMin,
            yMax: widget.yMax,
            gridN: widget.gridN,
            trajectory: widget.trajectory,
            axisXLen: widget.axisXLen,
            axisYLen: widget.axisYLen,
            axisZLen: widget.axisZLen,
            minZ: widget.minZ,
            maxZ: widget.maxZ,
            axisOrigin: widget.axisOrigin ?? vm.Vector3(0, 0, 0),
            rotX: _rotX,
            rotY: _rotY,
            zoom: _zoom,
            cutZ: widget.cutZ,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Mini3DPainter extends CustomPainter {
  final double Function(double x, double y) f;
  final double xMin, xMax, yMin, yMax;
  final int gridN;
  final List<vm.Vector3> trajectory;
  final double axisXLen, axisYLen, axisZLen;
  final double minZ, maxZ;
  final vm.Vector3 axisOrigin;
  final double rotX, rotY, zoom;
  final double cutZ;

  _Mini3DPainter({
    required this.f,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.gridN,
    required this.trajectory,
    required this.axisXLen,
    required this.axisYLen,
    required this.axisZLen,
    required this.minZ,
    required this.maxZ,
    required this.axisOrigin,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.cutZ,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final m = vm.Matrix4.identity()
      ..rotateX(rotX)
      ..rotateY(rotY);

    final scale = size.shortestSide * zoom / 12.0;
    final zRange = (maxZ - minZ).abs() < 1e-12 ? 1.0 : (maxZ - minZ);
    final zScale = axisZLen / zRange;

    Offset proj(vm.Vector3 p) {
      final scaled = vm.Vector3(p.x, (p.y - minZ) * zScale, p.z);
      final v = m.transformed3(scaled);
      return Offset(
        size.width / 2 + v.x * scale,
        size.height / 2 - v.y * scale,
      );
    }

    Color colorFor(double z) {
      final t = ((z - minZ) / zRange).clamp(0.0, 1.0);
      return Color.lerp(Colors.blue, Colors.red, t)!;
    }

    final dx = (xMax - xMin) / gridN;
    final dy = (yMax - yMin) / gridN;

    for (int j = 0; j <= gridN; j++) {
      final y = yMin + j * dy;
      for (int i = 0; i < gridN; i++) {
        final x1 = xMin + i * dx;
        final x2 = xMin + (i + 1) * dx;
        final z1 = f(x1, y);
        final z2 = f(x2, y);
        final p1 = proj(vm.Vector3(x1, z1, y));
        final p2 = proj(vm.Vector3(x2, z2, y));
        final zMid = (z1 + z2) / 2;
        canvas.drawLine(p1, p2, Paint()..color = colorFor(zMid).withAlpha(150)..strokeWidth = 1);
      }
    }
    for (int i = 0; i <= gridN; i++) {
      final x = xMin + i * dx;
      for (int j = 0; j < gridN; j++) {
        final y1 = yMin + j * dy;
        final y2 = yMin + (j + 1) * dy;
        final z1 = f(x, y1);
        final z2 = f(x, y2);
        final p1 = proj(vm.Vector3(x, z1, y1));
        final p2 = proj(vm.Vector3(x, z2, y2));
        final zMid = (z1 + z2) / 2;
        canvas.drawLine(p1, p2, Paint()..color = colorFor(zMid).withAlpha(150)..strokeWidth = 1);
      }
    }

    final p1 = proj(vm.Vector3(xMin, cutZ, yMin));
    final p2 = proj(vm.Vector3(xMax, cutZ, yMin));
    final p3 = proj(vm.Vector3(xMax, cutZ, yMax));
    final p4 = proj(vm.Vector3(xMin, cutZ, yMax));
    final planePath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();
    canvas.drawPath(planePath, Paint()..color = Colors.orange.withAlpha(50)..style = PaintingStyle.fill);
    canvas.drawPath(planePath, Paint()..color = Colors.orange.withAlpha(220)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final o = proj(axisOrigin);
    final xEnd = proj(axisOrigin + vm.Vector3(axisXLen, 0, 0));
    final yEnd = proj(axisOrigin + vm.Vector3(0, 0, axisYLen));
    final zEnd = proj(axisOrigin + vm.Vector3(0, minZ + zRange, 0));
    final axisPaint = Paint()..color = Colors.black..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawLine(o, xEnd, axisPaint);
    canvas.drawLine(o, yEnd, axisPaint);
    canvas.drawLine(o, zEnd, axisPaint);

    if (trajectory.isNotEmpty) {
      final trajPaint = Paint()..color = Colors.green.withAlpha(160)..strokeWidth = 2..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < trajectory.length; i++) {
        final p = proj(trajectory[i]);
        if (i == 0) path.moveTo(p.dx, p.dy);
        else path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, trajPaint);
      final greenPaint = Paint()..color = Colors.green;
      final redPaint = Paint()..color = Colors.red;
      for (int i = 0; i < trajectory.length; i++) {
        final p = proj(trajectory[i]);
        final isLast = i == trajectory.length - 1;
        canvas.drawCircle(p, isLast ? 7 : 4, isLast ? redPaint : greenPaint);
      }
    }

    _drawLabel(canvas, xEnd, 'X');
    _drawLabel(canvas, yEnd, 'Y');
    _drawLabel(canvas, zEnd, 'Z');
  }

  void _drawLabel(Canvas canvas, Offset center, String text) {
    const r = 11.0;
    canvas.drawCircle(center, r, Paint()..color = Colors.black);
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_Mini3DPainter old) =>
      old.rotX != rotX || old.rotY != rotY || old.zoom != zoom ||
      old.trajectory != trajectory || old.cutZ != cutZ;
}


class ContourView2D extends StatelessWidget {
  final double Function(double x, double y) f;
  final double xMin, xMax, yMin, yMax;
  final double cutZ;
  final List<vm.Vector3> trajectory;

  const ContourView2D({
    Key? key,
    required this.f,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.cutZ,
    required this.trajectory,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _Contour2DPainter(
        f: f,
        xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax,
        cutZ: cutZ,
        trajectory: trajectory,
      ),
      size: Size.infinite,
    );
  }
}

class _Contour2DPainter extends CustomPainter {
  final double Function(double x, double y) f;
  final double xMin, xMax, yMin, yMax;
  final double cutZ;
  final List<vm.Vector3> trajectory;

  static const double _pad = 30.0;

  _Contour2DPainter({
    required this.f,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.cutZ,
    required this.trajectory,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _pad * 2;
    final h = size.height - _pad * 2;
    if (w <= 0 || h <= 0) return;

    final dx = xMax - xMin;
    final dy = yMax - yMin;

    Offset toScreen(double x, double y) {
      return Offset(
        _pad + (x - xMin) / dx * w,
        _pad + h - (y - yMin) / dy * h,
      );
    }

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(_pad, _pad, w, h), bgPaint);

    const int n = 120;
    final stepX = dx / n;
    final stepY = dy / n;

    final values = List.generate(
      n + 1,
      (i) => List.generate(n + 1, (j) {
        return f(xMin + i * stepX, yMin + j * stepY) - cutZ;
      }),
    );

    final contourPaint = Paint()
      ..color = Colors.deepOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        final v00 = values[i][j];
        final v10 = values[i + 1][j];
        final v11 = values[i + 1][j + 1];
        final v01 = values[i][j + 1];

        int idx = 0;
        if (v00 > 0) idx |= 1;
        if (v10 > 0) idx |= 2;
        if (v11 > 0) idx |= 4;
        if (v01 > 0) idx |= 8;
        if (idx == 0 || idx == 15) continue;

        final x0 = xMin + i * stepX;
        final x1 = xMin + (i + 1) * stepX;
        final y0 = yMin + j * stepY;
        final y1 = yMin + (j + 1) * stepY;

        double t(double va, double vb) => va / (va - vb);

        final b = Offset(x0 + stepX * t(v00, v10), y0);
        final r = Offset(x1, y0 + stepY * t(v10, v11));
        final tp = Offset(x0 + stepX * t(v01, v11), y1);
        final l = Offset(x0, y0 + stepY * t(v00, v01));

        List<List<Offset>> segs;
        switch (idx) {
          case 1:
          case 14:
            segs = [[l, b]];
            break;
          case 2:
          case 13:
            segs = [[b, r]];
            break;
          case 3:
          case 12:
            segs = [[l, r]];
            break;
          case 4:
          case 11:
            segs = [[r, tp]];
            break;
          case 6:
          case 9:
            segs = [[b, tp]];
            break;
          case 7:
          case 8:
            segs = [[l, tp]];
            break;
          case 5:
            segs = [[l, b], [r, tp]];
            break;
          case 10:
            segs = [[l, tp], [b, r]];
            break;
          default:
            segs = [];
        }

        for (final s in segs) {
          canvas.drawLine(toScreen(s[0].dx, s[0].dy), toScreen(s[1].dx, s[1].dy), contourPaint);
        }
      }
    }

    if (trajectory.isNotEmpty) {
      final greenPaint = Paint()..color = Colors.green;
      final redPaint = Paint()..color = Colors.red;
      for (int i = 0; i < trajectory.length; i++) {
        final p = toScreen(trajectory[i].x, trajectory[i].z);
        final isLast = i == trajectory.length - 1;
        canvas.drawCircle(p, isLast ? 5 : 3, isLast ? redPaint : greenPaint);
      }
      final linePaint = Paint()..color = Colors.green.withAlpha(150)..strokeWidth = 1.5;
      final path = Path();
      for (int i = 0; i < trajectory.length; i++) {
        final p = toScreen(trajectory[i].x, trajectory[i].z);
        if (i == 0) path.moveTo(p.dx, p.dy);
        else path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    canvas.drawRect(
      Rect.fromLTWH(_pad, _pad, w, h),
      Paint()..color = Colors.black..strokeWidth = 1.5..style = PaintingStyle.stroke,
    );

    _drawText(canvas, Offset(_pad + w + 6, _pad + h - 8), 'X', Colors.black, 12);
    _drawText(canvas, Offset(_pad - 22, _pad - 8), 'Y', Colors.black, 12);

    final title = 'Срез z = ${cutZ.toStringAsFixed(2)}';
    _drawText(canvas, Offset(_pad, _pad - 22), title, Colors.deepOrange, 12);
  }

  void _drawText(Canvas canvas, Offset pos, String text, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_Contour2DPainter old) =>
      old.cutZ != cutZ || old.trajectory != trajectory || old.f != f;
}


List<vm.Vector3> coordinateDescent({
  required double Function(double x, double y) f,
  required double initialX,
  required double initialY,
  required double h,
  required double eps,
  int maxIter = 1000,
}) {
  final pts = <vm.Vector3>[];
  double x = initialX, y = initialY, z = f(x, y);
  pts.add(vm.Vector3(x, z, y));
  for (int i = 0; i < maxIter; i++) {
    final candidates = <List<double>>[
      [x + h, y], [x - h, y], [x, y + h], [x, y - h],
    ];
    double bx = x, by = y, bz = z;
    for (final c in candidates) {
      final cz = f(c[0], c[1]);
      if (cz < bz) {
        bz = cz; bx = c[0]; by = c[1];
      }
    }
    if (bz >= z) break;
    final diff = (z - bz).abs();
    x = bx; y = by; z = bz;
    pts.add(vm.Vector3(x, z, y));
    if (diff < eps) break;
  }
  return pts;
}

({double minZ, double maxZ}) computeMinMax(
  double Function(double, double) f,
  double xMin, double xMax,
  double yMin, double yMax, {
  int n = 40,
}) {
  double minZ = double.infinity;
  double maxZ = double.negativeInfinity;
  final dx = (xMax - xMin) / n;
  final dy = (yMax - yMin) / n;
  for (int i = 0; i <= n; i++) {
    final x = xMin + i * dx;
    for (int j = 0; j <= n; j++) {
      final y = yMin + j * dy;
      final z = f(x, y);
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }
  }
  return (minZ: minZ, maxZ: maxZ);
}


class FunctionTab extends StatefulWidget {
  final String title;
  final double Function(double, double) f;
  final double xMin, xMax, yMin, yMax;
  final double initialX, initialY;
  final double h, eps;
  final double axisXLen, axisYLen, axisZLen;
  final int gridN;
  final int maxIter;
  final vm.Vector3? axisOrigin;

  const FunctionTab({
    Key? key,
    required this.title,
    required this.f,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.initialX,
    required this.initialY,
    required this.h,
    required this.eps,
    required this.axisXLen,
    required this.axisYLen,
    required this.axisZLen,
    this.gridN = 20,
    this.maxIter = 1000,
    this.axisOrigin,
  }) : super(key: key);

  @override
  State<FunctionTab> createState() => _FunctionTabState();
}

class _FunctionTabState extends State<FunctionTab> {
  late ({double minZ, double maxZ}) _range;
  late List<vm.Vector3> _trajectory;
  double _cutZ = 0.0;

  @override
  void initState() {
    super.initState();
    _range = computeMinMax(widget.f, widget.xMin, widget.xMax, widget.yMin, widget.yMax);
    _trajectory = coordinateDescent(
      f: widget.f,
      initialX: widget.initialX, initialY: widget.initialY,
      h: widget.h, eps: widget.eps, maxIter: widget.maxIter,
    );
    _cutZ = (_range.minZ + _range.maxZ) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: Mini3DView(
            f: widget.f,
            xMin: widget.xMin, xMax: widget.xMax,
            yMin: widget.yMin, yMax: widget.yMax,
            gridN: widget.gridN,
            trajectory: _trajectory,
            axisXLen: widget.axisXLen, axisYLen: widget.axisYLen, axisZLen: widget.axisZLen,
            minZ: _range.minZ, maxZ: _range.maxZ,
            axisOrigin: widget.axisOrigin ?? vm.Vector3(0, 0, 0),
            cutZ: _cutZ,
          ),
        ),
        Expanded(
          flex: 2,
          child: ContourView2D(
            f: widget.f,
            xMin: widget.xMin, xMax: widget.xMax,
            yMin: widget.yMin, yMax: widget.yMax,
            cutZ: _cutZ,
            trajectory: _trajectory,
          ),
        ),
        _CutSlider(
          value: _cutZ,
          min: _range.minZ,
          max: _range.maxZ,
          onChanged: (v) => setState(() => _cutZ = v),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: Text(
            '${widget.title}. Зелёные — спуск, красная — минимум',
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}


class _CutSlider extends StatelessWidget {
  final double value, min, max;
  final ValueChanged<double> onChanged;

  const _CutSlider({
    Key? key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text('z =', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}


class ParaboloidTab extends StatefulWidget {
  const ParaboloidTab({Key? key}) : super(key: key);
  @override
  State<ParaboloidTab> createState() => _ParaboloidTabState();
}

class _ParaboloidTabState extends State<ParaboloidTab> {
  final _aText = TextEditingController(text: '1.0');
  final _bText = TextEditingController(text: '1.0');
  double _a = 1.0, _b = 1.0;
  double _cutZ = 1.0;

  @override
  void dispose() {
    _aText.dispose();
    _bText.dispose();
    super.dispose();
  }

  double _f(double x, double y) => _a * x * x + _b * y * y;

  @override
  Widget build(BuildContext context) {
    final range = computeMinMax(_f, -2, 2, -2, 2);
    final trajectory = coordinateDescent(
      f: _f, initialX: 1.5, initialY: 1.5, h: 0.1, eps: 0.001,
    );
    final clamped = _cutZ.clamp(range.minZ, range.maxZ);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _aText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'a', isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) {
                    final p = double.tryParse(v.replaceAll(',', '.'));
                    if (p != null) setState(() => _a = p);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _bText,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'b', isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) {
                    final p = double.tryParse(v.replaceAll(',', '.'));
                    if (p != null) setState(() => _b = p);
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Mini3DView(
            f: _f,
            xMin: -2, xMax: 2, yMin: -2, yMax: 2,
            gridN: 20,
            trajectory: trajectory,
            axisXLen: 4, axisYLen: 4, axisZLen: 10,
            minZ: range.minZ, maxZ: range.maxZ,
            cutZ: clamped,
          ),
        ),
        Expanded(
          flex: 2,
          child: ContourView2D(
            f: _f,
            xMin: -2, xMax: 2, yMin: -2, yMax: 2,
            cutZ: clamped,
            trajectory: trajectory,
          ),
        ),
        _CutSlider(
          value: clamped,
          min: range.minZ,
          max: range.maxZ,
          onChanged: (v) => setState(() => _cutZ = v),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: Text(
            'z = ${_a.toStringAsFixed(2)}·x² + ${_b.toStringAsFixed(2)}·y²',
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}


class AckleyTab extends StatelessWidget {
  const AckleyTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double f(double x, double y) {
      const e = 2.718281828459045;
      return -20 * exp(-0.2 * sqrt(0.5 * (x * x + y * y))) -
          exp(0.5 * (cos(2 * pi * x) + cos(2 * pi * y))) + 20 + e;
    }

    return FunctionTab(
      title: 'Функция Экли',
      f: f,
      xMin: -10, xMax: 10, yMin: -10, yMax: 10,
      initialX: 3, initialY: 3,
      h: 0.1, eps: 0.001,
      axisXLen: 10, axisYLen: 10, axisZLen: 10,
      gridN: 30,
    );
  }
}


class BukinTab extends StatelessWidget {
  const BukinTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double f(double x, double y) =>
        100 * sqrt((y - 0.01 * x * x).abs()) + 0.01 * (x + 10).abs();

    return FunctionTab(
      title: 'Функция Букина N.6',
      f: f,
      xMin: -15, xMax: -5, yMin: -3, yMax: 3,
      initialX: -12, initialY: 2,
      h: 0.05, eps: 0.0001,
      axisXLen: 10, axisYLen: 6, axisZLen: 10,
      gridN: 30,
      maxIter: 2000,
      axisOrigin: vm.Vector3(-10, 0, 0),
    );
  }
}


class LevyTab extends StatelessWidget {
  const LevyTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double f(double x, double y) {
      final t1 = pow(sin(3 * pi * x), 2);
      final t2 = (x - 1) * (x - 1) * (1 + pow(sin(3 * pi * y), 2));
      final t3 = (y - 1) * (y - 1) * (1 + pow(sin(2 * pi * y), 2));
      return t1 + t2 + t3;
    }

    return FunctionTab(
      title: 'Функция Леви N.13',
      f: f,
      xMin: -10, xMax: 10, yMin: -10, yMax: 10,
      initialX: 3, initialY: 3,
      h: 0.1, eps: 0.001,
      axisXLen: 10, axisYLen: 10, axisZLen: 10,
      gridN: 30,
    );
  }
}