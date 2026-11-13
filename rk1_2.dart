import 'dart:async';
import 'dart:math';
import 'package:ditredi/ditredi.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  double bx = 0, by = 2;
  double bvx = 3, bvy = -1.2;
  final double bSpeed = 3.5;

  double racketAngle = 0;   
  double grabAmount = 1;    

  double camX = 0, camY = 0, camZ = 0;

  Timer? _timer;

  final _controller = DiTreDiController(
    rotationX: -50,
    rotationY: 20,
    light: vm.Vector3(-0.5, -0.5, 0.5),
  );

  final Future<List<Mesh3D>> handFuture = _generateHand();

  static const double wallX = -8;
  static const double wallH = 10;
  static const double wallD = 4;
  static const double racketBaseX = 3;
  static const double racketBaseY = -3;
  static const double handleLen = 1.5;
  static const double racketR = 1.0;
  static const double ballR = 0.15;

  bool get _handHolds => grabAmount >= 0.99;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    const dt = 0.02;
    double nx = bx + bvx * dt;
    double ny = by + bvy * dt;

    if (nx < wallX + 0.3) {
      nx = wallX + 0.3;
      bvx = bvx.abs();
    }
    if (ny > wallH / 2) { ny = wallH / 2; bvy = -bvy.abs(); }
    if (ny < -wallH / 2) { ny = -wallH / 2; bvy = bvy.abs(); }
    if (nx > 8) { nx = 8; bvx = -bvx.abs(); }

    final theta = racketAngle * pi / 180;
    final tipX = racketBaseX + cos(theta) * (handleLen + racketR);
    final tipY = racketBaseY + sin(theta) * (handleLen + racketR);

    final d = _distToSegment(nx, ny, racketBaseX, racketBaseY, tipX, tipY);
    if (d < racketR + ballR) {
      final nxn = -sin(theta), nyn = cos(theta);
      final dot = bvx * nxn + bvy * nyn;
      if (dot < 0) {
        bvx -= 2 * dot * nxn;
        bvy -= 2 * dot * nyn;
      }
      nx += nxn * (racketR + ballR - d + 0.05);
      ny += nyn * (racketR + ballR - d + 0.05);
    }

    final sp = sqrt(bvx * bvx + bvy * bvy);
    if (sp > 0.001) {
      bvx = bvx / sp * bSpeed;
      bvy = bvy / sp * bSpeed;
    }

    bx = nx;
    by = ny;
    setState(() {});
  }

  double _distToSegment(double px, double py, double x1, double y1, double x2, double y2) {
    final dx = x2 - x1, dy = y2 - y1;
    final l2 = dx * dx + dy * dy;
    double t = l2 == 0 ? 0 : ((px - x1) * dx + (py - y1) * dy) / l2;
    t = t.clamp(0.0, 1.0);
    final qx = x1 + t * dx, qy = y1 + t * dy;
    return sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
  }

  Mesh3D _box(vm.Vector3 c, vm.Vector3 s, Color col) {
    final hx = s.x / 2, hy = s.y / 2, hz = s.z / 2;
    final p = [
      c + vm.Vector3(-hx, -hy, -hz), c + vm.Vector3(hx, -hy, -hz),
      c + vm.Vector3(hx, hy, -hz),   c + vm.Vector3(-hx, hy, -hz),
      c + vm.Vector3(-hx, -hy, hz),  c + vm.Vector3(hx, -hy, hz),
      c + vm.Vector3(hx, hy, hz),    c + vm.Vector3(-hx, hy, hz),
    ];
    final f = <Face3D>[];
    void q(int a, int b, int cc, int d) {
      f.add(Face3D.fromVertices(p[a], p[b], p[cc], color: col));
      f.add(Face3D.fromVertices(p[a], p[cc], p[d], color: col));
    }
    q(0, 1, 2, 3); q(4, 7, 6, 5);
    q(0, 4, 5, 1); q(1, 5, 6, 2);
    q(2, 6, 7, 3); q(3, 7, 4, 0);
    return Mesh3D(f);
  }

  Mesh3D _cylinder(vm.Vector3 c, vm.Vector3 dir, double len, double rad, Color col) {
    final f = <Face3D>[];
    final d = dir.normalized();
    var up = vm.Vector3(0, 1, 0);
    if (d.dot(up).abs() > 0.9) up = vm.Vector3(0, 0, 1);
    final r = d.cross(up).normalized();
    final u = r.cross(d).normalized();
    const N = 12;
    final hl = len / 2;
    vm.Vector3 pt(double a, double b, double cc) => c + d * a + r * b + u * cc;
    for (int i = 0; i < N; i++) {
      final a1 = 2 * pi * i / N, a2 = 2 * pi * (i + 1) / N;
      final y1 = rad * cos(a1), z1 = rad * sin(a1);
      final y2 = rad * cos(a2), z2 = rad * sin(a2);
      f.add(Face3D.fromVertices(pt(-hl, y1, z1), pt(hl, y1, z1), pt(hl, y2, z2), color: col));
      f.add(Face3D.fromVertices(pt(-hl, y1, z1), pt(hl, y2, z2), pt(-hl, y2, z2), color: col));
    }
    final c1 = c + d * (-hl);
    final c2 = c + d * (hl);
    for (int i = 0; i < N; i++) {
      final a1 = 2 * pi * i / N, a2 = 2 * pi * (i + 1) / N;
      final p1 = c1 + r * (rad * cos(a1)) + u * (rad * sin(a1));
      final p2 = c1 + r * (rad * cos(a2)) + u * (rad * sin(a2));
      f.add(Face3D.fromVertices(c1, p1, p2, color: col));
      final p3 = c2 + r * (rad * cos(a1)) + u * (rad * sin(a1));
      final p4 = c2 + r * (rad * cos(a2)) + u * (rad * sin(a2));
      f.add(Face3D.fromVertices(c2, p4, p3, color: col));
    }
    return Mesh3D(f);
  }

  Mesh3D _disk(vm.Vector3 c, vm.Vector3 normal, double rad, Color col) {
    final f = <Face3D>[];
    final n = normal.normalized();
    var up = vm.Vector3(0, 1, 0);
    if (n.dot(up).abs() > 0.9) up = vm.Vector3(1, 0, 0);
    final u = up.cross(n).normalized();
    final v = n.cross(u).normalized();
    const N = 24;
    for (int i = 0; i < N; i++) {
      final a1 = 2 * pi * i / N, a2 = 2 * pi * (i + 1) / N;
      final p1 = c + u * (rad * cos(a1)) + v * (rad * sin(a1));
      final p2 = c + u * (rad * cos(a2)) + v * (rad * sin(a2));
      f.add(Face3D.fromVertices(c, p1, p2, color: col));
      f.add(Face3D.fromVertices(c, p2, p1, color: col));
    }
    return Mesh3D(f);
  }

  @override
  Widget build(BuildContext context) {
    final theta = racketAngle * pi / 180;
    final sceneShift = Matrix4.identity()..translate(-camX, -camY, -camZ);

    final wall = _box(
      vm.Vector3(wallX, 0, 0),
      vm.Vector3(0.3, wallH, wallD),
      const Color(0xFF8B6A3F),
    );

    final ball = _box(
      vm.Vector3(bx, by, 0),
      vm.Vector3(ballR * 2, ballR * 2, ballR * 2),
      const Color(0xFFFF4444),
    );

    final handleCenter = vm.Vector3(
      racketBaseX + cos(theta) * handleLen / 2,
      racketBaseY + sin(theta) * handleLen / 2,
      0,
    );
    final handle = _cylinder(
      handleCenter,
      vm.Vector3(cos(theta), sin(theta), 0),
      handleLen, 0.1,
      const Color(0xFF654321),
    );

    final diskCenter = vm.Vector3(
      racketBaseX + cos(theta) * (handleLen + racketR),
      racketBaseY + sin(theta) * (handleLen + racketR),
      0,
    );
    final diskNormal = vm.Vector3(-sin(theta), cos(theta), 0);
    final head = _disk(diskCenter, diskNormal, racketR, const Color(0xFFFFAA00));

    final figures = <Model3D>[
      TransformModifier3D(wall, sceneShift),
      TransformModifier3D(ball, sceneShift),
      TransformModifier3D(handle, sceneShift),
      TransformModifier3D(head, sceneShift),
    ];

    return MaterialApp(
      darkTheme: ThemeData.dark(),
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: FutureBuilder<List<Mesh3D>>(
                  future: handFuture,
                  builder: (ctx, snap) {
                    if (snap.hasData) {
                      final handX = racketBaseX + cos(theta) * handleLen;
                      final handY = racketBaseY + sin(theta) * handleLen;

                      final awayX = (1 - grabAmount) * -6;
                      final awayY = (1 - grabAmount) * -6;

                      final handBase = Matrix4.identity()
                        ..translate(handX + awayX, handY + awayY, 0)
                        ..rotateZ(theta)
                        ..scale(0.15);

                      final fingerCurl = grabAmount * 12;

                      final origTransforms = [
                        Matrix4.identity()..rotateX(-pi / 2),
                        Matrix4.identity()
                          ..rotateX(-pi / 2)
                          ..translate(3.05, 1.15, 8.75)
                          ..translate(-0.2, -0.25, -2.2)
                          ..rotateX(-(fingerCurl * pi / 18))
                          ..translate(0.2, 0.25, 2.2),
                        Matrix4.identity()
                          ..rotateX(-pi / 2)
                          ..translate(0.7, 0.0, 9.75)
                          ..translate(0.0, -0.5, -2.25)
                          ..rotateX(-(fingerCurl * pi / 18))
                          ..translate(0.0, 0.5, 2.25),
                        Matrix4.identity()
                          ..rotateX(-pi / 2)
                          ..translate(-2.0, -0.56, 9.1)
                          ..translate(0.0, -0.25, -2.2)
                          ..rotateX(-(fingerCurl * pi / 18))
                          ..translate(0.0, 0.25, 2.2),
                        Matrix4.identity()
                          ..rotateX(-pi / 2)
                          ..translate(-4.65, -1.0, 7.15)
                          ..translate(0.0, 0.0, -1.25)
                          ..rotateX(-(fingerCurl * pi / 18))
                          ..translate(0.0, 0.0, 1.25),
                      ];

                      for (int i = 0; i < snap.data!.length; i++) {
                        figures.add(TransformModifier3D(
                          snap.data![i],
                          sceneShift * handBase * origTransforms[i],
                        ));
                      }
                    }
                    return DiTreDiDraggable(
                      controller: _controller,
                      child: DiTreDi(
                        figures: figures,
                        controller: _controller,
                      ),
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _sliderRow(
                      'Угол',
                      racketAngle,
                      -180,
                      180,
                      72,
                      _handHolds
                          ? (v) => setState(() => racketAngle = v)
                          : null,
                      '${racketAngle.toStringAsFixed(0)}°',
                    ),
                    _sliderRow(
                      'Захват',
                      grabAmount,
                      0,
                      1,
                      20,
                      (v) => setState(() => grabAmount = v),
                      grabAmount.toStringAsFixed(2),
                    ),
                    _sliderRow('Кам X', camX, -20, 20, 80,
                            (v) => setState(() => camX = v),
                        camX.toStringAsFixed(1)),
                    _sliderRow('Кам Y', camY, -20, 20, 80,
                            (v) => setState(() => camY = v),
                        camY.toStringAsFixed(1)),
                    _sliderRow('Кам Z', camZ, -20, 20, 80,
                            (v) => setState(() => camZ = v),
                        camZ.toStringAsFixed(1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double>? onChanged, 
    String valueText,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text('$label: $valueText'),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

Future<List<Mesh3D>> _generateHand() async {
  return [
    Mesh3D(await ObjParser().loadFromResources("assets/hand/hand.obj")),
    Mesh3D(await ObjParser().loadFromResources("assets/hand/index.obj")),
    Mesh3D(await ObjParser().loadFromResources("assets/hand/middle.obj")),
    Mesh3D(await ObjParser().loadFromResources("assets/hand/ring.obj")),
    Mesh3D(await ObjParser().loadFromResources("assets/hand/pinky.obj")),
  ];
}