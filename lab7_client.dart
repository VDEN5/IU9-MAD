import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:ditredi/ditredi.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:web_socket_channel/web_socket_channel.dart';

const String kServerHost = '45.9.75.158';
const int    kServerPort = 8062;

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  WebSocketChannel? _channel;
  bool _connected = false;
  String _status = 'Не подключено';
  int _myPlayer = -1;

  final List<double> _angle   = [0, 0];
  final List<double> _grab    = [1, 1];
  final List<double> _offsetX = [0, 0];
  final List<double> _offsetY = [0, 0];
  final List<double> _offsetZ = [0, 0];

  double bx = 0, by = 0, bz = 0;

  double camX = 0, camY = 0, camZ = 0;

  final _controller = DiTreDiController(
    rotationX: -40,
    rotationY: 30,
    light: vm.Vector3(-0.5, -0.5, 0.5),
  );

  final Future<List<Mesh3D>> handFuture = _generateHand();

  static const double wallX = -8;
  static const double wallH = 10;
  static const double wallD = 8;
  static const double handleLen = 1.5;
  static const double racketR = 1.0;
  static const double ballR = 0.15;

  static const List<List<double>> racketBases = [
    [5.0, -3.0, -1.0],
    [5.0,  3.0, -1.0],
  ];

  bool _handHolds(int i) => _grab[i] >= 0.99;

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  void _connect(int playerId) {
    setState(() {
      _myPlayer = playerId;
      _status = 'Подключение к $kServerHost:$kServerPort...';
    });
    try {
      final url = 'ws://$kServerHost:$kServerPort';
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
            (msg) {
          final data = jsonDecode(msg as String) as Map<String, dynamic>;
          if (data['type'] == 'welcome') {
            setState(() {
              _connected = true;
              _status = 'Игрок $_myPlayer';
            });
            _sendInput(_myPlayer);
          } else if (data['type'] == 'state') {
            setState(() {
              bx = (data['bx'] as num).toDouble();
              by = (data['by'] as num).toDouble();
              bz = (data['bz'] as num?)?.toDouble() ?? 0;
              for (final r in (data['rackets'] as List)) {
                final id = r['id'] as int;
                if (id < 0 || id > 1) continue;
                _angle[id]   = (r['angle']   as num).toDouble();
                _grab[id]    = (r['grab']    as num).toDouble();
                _offsetX[id] = (r['offsetX'] as num?)?.toDouble() ?? 0;
                _offsetY[id] = (r['offsetY'] as num?)?.toDouble() ?? 0;
                _offsetZ[id] = (r['offsetZ'] as num?)?.toDouble() ?? 0;
              }
            });
          }
        },
        onDone: () => setState(() {
          _connected = false;
          _status = 'Отключено';
        }),
        onError: (e) => setState(() {
          _connected = false;
          _status = 'Ошибка: $e';
        }),
      );
    } catch (e) {
      setState(() => _status = 'Ошибка: $e');
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() {
      _connected = false;
      _myPlayer = -1;
      _status = 'Не подключено';
    });
  }

  void _sendInput(int racketId) {
    if (_channel == null || !_connected) return;
    _channel!.sink.add(jsonEncode({
      'type': 'input',
      'racketId': racketId,
      'racketAngle': _angle[racketId],
      'grabAmount':  _grab[racketId],
      'offsetX':     _offsetX[racketId],
      'offsetY':     _offsetY[racketId],
      'offsetZ':     _offsetZ[racketId],
    }));
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
    final c2 = c + d * hl;
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
    return MaterialApp(
      darkTheme: ThemeData.dark(),
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        body: SafeArea(
          child: _connected ? _buildGame() : _buildMenu(),
        ),
      ),
    );
  }

  Widget _buildMenu() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_tennis, size: 80, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('Pong 3D',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Сервер: $kServerHost:$kServerPort',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text('Выберите игрока', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.looks_one, color: Colors.white),
                label: const Text('Игрок 0 (нижняя ракетка)',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                onPressed: () => _connect(0),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.looks_two, color: Colors.white),
                label: const Text('Игрок 1 (верхняя ракетка)',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                onPressed: () => _connect(1),
              ),
            ),
            const SizedBox(height: 24),
            if (_status != 'Не подключено')
              Text(_status, style: const TextStyle(color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }

  Widget _buildGame() {
    final sceneShift = Matrix4.identity()..translate(-camX, -camY, -camZ);

    final wall = _box(
      vm.Vector3(wallX, 0, 0),
      vm.Vector3(0.3, wallH, wallD),
      const Color(0xFF8B6A3F),
    );
    final ball = _box(
      vm.Vector3(bx, by, bz),
      vm.Vector3(ballR * 2, ballR * 2, ballR * 2),
      const Color(0xFFFF4444),
    );

    final figures = <Model3D>[
      TransformModifier3D(wall, sceneShift),
      TransformModifier3D(ball, sceneShift),
    ];

    for (int i = 0; i < 2; i++) {
      final base = racketBases[i];
      final baseX = base[0] + _offsetX[i];
      final baseY = base[1] + _offsetY[i];
      final baseZ = _offsetZ[i];
      final dirSign = base[2];
      final theta = _angle[i] * pi / 180;
      final ax = cos(theta) * dirSign;
      final ay = sin(theta);

      final handleCenter = vm.Vector3(
        baseX + ax * handleLen / 2,
        baseY + ay * handleLen / 2,
        baseZ,
      );
      final handle = _cylinder(
        handleCenter,
        vm.Vector3(ax, ay, 0),
        handleLen, 0.1,
        const Color(0xFF654321),
      );

      final diskCenter = vm.Vector3(
        baseX + ax * (handleLen + racketR),
        baseY + ay * (handleLen + racketR),
        baseZ,
      );
      final diskNormal = vm.Vector3(-ay, ax, 0);
      final head = _disk(diskCenter, diskNormal, racketR, const Color(0xFFFFAA00));

      figures.add(TransformModifier3D(handle, sceneShift));
      figures.add(TransformModifier3D(head, sceneShift));
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _myPlayer == 0 ? Colors.orange.shade900 : Colors.cyan.shade900,
          child: Row(
            children: [
              Icon(_myPlayer == 0 ? Icons.looks_one : Icons.looks_two,
                  color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Игрок $_myPlayer  |  Мяч: (${bx.toStringAsFixed(1)}, ${by.toStringAsFixed(1)}, ${bz.toStringAsFixed(1)})',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Отключиться',
                onPressed: _disconnect,
                icon: const Icon(Icons.logout, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: FutureBuilder<List<Mesh3D>>(
            future: handFuture,
            builder: (ctx, snap) {
              if (snap.hasData) {
                for (int i = 0; i < 2; i++) {
                  final base = racketBases[i];
                  final baseX = base[0] + _offsetX[i];
                  final baseY = base[1] + _offsetY[i];
                  final baseZ = _offsetZ[i];
                  final dirSign = base[2];
                  final theta = _angle[i] * pi / 180;
                  final ax = cos(theta) * dirSign;
                  final ay = sin(theta);

                  final handX = baseX + ax * handleLen;
                  final handY = baseY + ay * handleLen;
                  final awayX = (1 - _grab[i]) * -6;
                  final awayY = (1 - _grab[i]) * -6;

                  final handBase = Matrix4.identity()
                    ..translate(handX + awayX, handY + awayY, baseZ)
                    ..rotateZ(theta * dirSign)
                    ..scale(0.15);

                  final fingerCurl = _grab[i] * 12;

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

                  for (int j = 0; j < snap.data!.length; j++) {
                    figures.add(TransformModifier3D(
                      snap.data![j],
                      sceneShift * handBase * origTransforms[j],
                    ));
                  }
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
        Expanded(
          flex: 5,
          child: Container(
            color: Colors.black.withOpacity(0.3),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader(
                    _myPlayer == 0 ? 'Управление игрока 0' : 'Управление игрока 1',
                    _myPlayer == 0 ? Colors.orange : Colors.cyan,
                  ),

                  _sliderRow(
                    'Захват',
                    _grab[_myPlayer], 0, 1, 20,
                        (v) {
                      setState(() => _grab[_myPlayer] = v);
                      _sendInput(_myPlayer);
                    },
                    _grab[_myPlayer].toStringAsFixed(2),
                  ),

                  _sliderRow(
                    'Угол ракетки',
                    _angle[_myPlayer], -180, 180, 72,
                    _handHolds(_myPlayer)
                        ? (v) {
                      setState(() => _angle[_myPlayer] = v);
                      _sendInput(_myPlayer);
                    }
                        : null,
                    '${_angle[_myPlayer].toStringAsFixed(0)}°',
                  ),

                  _sliderRow(
                    'Сдвиг X (влево/вправо)',
                    _offsetX[_myPlayer], -5, 5, 100,
                    _handHolds(_myPlayer)
                        ? (v) {
                      setState(() => _offsetX[_myPlayer] = v);
                      _sendInput(_myPlayer);
                    }
                        : null,
                    _offsetX[_myPlayer].toStringAsFixed(2),
                  ),

                  _sliderRow(
                    'Сдвиг Y (вверх/вниз)',
                    _offsetY[_myPlayer], -5, 5, 100,
                    _handHolds(_myPlayer)
                        ? (v) {
                      setState(() => _offsetY[_myPlayer] = v);
                      _sendInput(_myPlayer);
                    }
                        : null,
                    _offsetY[_myPlayer].toStringAsFixed(2),
                  ),

                  _sliderRow(
                    'Сдвиг Z (вперёд/назад)',
                    _offsetZ[_myPlayer], -4, 4, 80,
                    _handHolds(_myPlayer)
                        ? (v) {
                      setState(() => _offsetZ[_myPlayer] = v);
                      _sendInput(_myPlayer);
                    }
                        : null,
                    _offsetZ[_myPlayer].toStringAsFixed(2),
                  ),

                  const Divider(height: 20),

                  _sectionHeader('Камера (локально)', Colors.grey),
                  _sliderRow('Кам X', camX, -20, 20, 80,
                          (v) => setState(() => camX = v), camX.toStringAsFixed(1)),
                  _sliderRow('Кам Y', camY, -20, 20, 80,
                          (v) => setState(() => camY = v), camY.toStringAsFixed(1)),
                  _sliderRow('Кам Z', camZ, -20, 20, 80,
                          (v) => setState(() => camZ = v), camZ.toStringAsFixed(1)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
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
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? Colors.white : Colors.grey,
              ),
            ),
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
            width: 46,
            child: Text(
              valueText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? Colors.white : Colors.grey,
              ),
            ),
          ),
        ],
      ),
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