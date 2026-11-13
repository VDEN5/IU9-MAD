import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_cube/flutter_cube.dart' as cube;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Earths',
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _countController =
      TextEditingController(text: '10');

  cube.Scene? _scene;
  final List<cube.Object> _earths = [];

  double camX = 0;
  double camY = 0;
  double camZ = 30;

  bool get _ready => _scene != null;

  void _onSceneCreated(cube.Scene scene) {
    _scene = scene;
    _scene!.camera.position.setFrom(cube.Vector3(camX, camY, camZ));
    _scene!.light.position.setFrom(cube.Vector3(50, 50, 50));
    _scene!.light.setColor(Colors.white, 0.3, 0.7, 0.5);
    _generateEarths();
  }

  void _generateEarths() {
    if (_scene == null) return;

    for (final s in _earths) {
      _scene!.world.remove(s);
    }
    _earths.clear();

    final count = int.tryParse(_countController.text) ?? 0;
    if (count <= 0) {
      _scene!.update();
      setState(() {});
      return;
    }

    final rng = Random();

    for (int i = 0; i < count; i++) {
      final radius = 0.5 + rng.nextDouble() * 2.5;
      final pos = cube.Vector3(
        (rng.nextDouble() - 0.5) * 60,
        (rng.nextDouble() - 0.5) * 60,
        (rng.nextDouble() - 0.5) * 60,
      );

      final earth = cube.Object(
        position: pos,
        scale: cube.Vector3(radius, radius, radius),
        lighting: true,
        fileName: 'assets/earth/earth.obj',
      );

      _scene!.world.add(earth);
      _earths.add(earth);
    }

    _scene!.update();
    setState(() {});
  }

  void _updateCamera() {
    if (_scene == null) return;
    _scene!.camera.position.setFrom(cube.Vector3(camX, camY, camZ));
    _scene!.update();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earths')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _countController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Количество сфер',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _ready ? _generateEarths : null,
                      child: const Text('Сгенерировать'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _axisSlider(
                  label: 'X',
                  value: camX,
                  min: -100,
                  max: 100,
                  onChanged: (v) {
                    camX = v;
                    _updateCamera();
                  },
                ),
                _axisSlider(
                  label: 'Y',
                  value: camY,
                  min: -100,
                  max: 100,
                  onChanged: (v) {
                    camY = v;
                    _updateCamera();
                  },
                ),
                _axisSlider(
                  label: 'Z',
                  value: camZ,
                  min: -100,
                  max: 100,
                  onChanged: (v) {
                    camZ = v;
                    _updateCamera();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: cube.Cube(onSceneCreated: _onSceneCreated),
          ),
        ],
      ),
    );
  }

  Widget _axisSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 24, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: 200,
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(value.toStringAsFixed(1), textAlign: TextAlign.right),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }
}