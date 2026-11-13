import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:yandex_mapkit/yandex_mapkit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Лаба 6 — Яндекс.Карты',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.red),
      home: const MapScreen(),
    );
  }
}

class Place {
  final String name;
  final String address;
  final String tel;
  final double lat;
  final double lon;

  Place({
    required this.name,
    required this.address,
    required this.tel,
    required this.lat,
    required this.lon,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    final gps = (json['gps'] as String).split(',');
    return Place(
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      tel: json['tel'] ?? '',
      lat: double.parse(gps[0].trim()),
      lon: double.parse(gps[1].trim()),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const String _dataUrl =
      'http://pstgu.yss.su/iu9/mobiledev/lab4_yandex_map/2023.php?x=var08';

  YandexMapController? _controller;
  List<Place> _places = [];
  BitmapDescriptor? _markerIcon;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _markerIcon = await _buildMarkerPng();
    await _load();
  }

  Future<BitmapDescriptor> _buildMarkerPng() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(32, 32);

    canvas.drawCircle(center, 28, Paint()..color = const Color(0xFFE53935));
    canvas.drawCircle(center, 12, Paint()..color = Colors.white);

    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 64);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  Future<void> _load() async {
    try {
      final response = await http.get(Uri.parse(_dataUrl));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      final places = list
          .map((e) => Place.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _places = places;
        _loading = false;
      });
      await _fitCamera();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fitCamera() async {
    final controller = _controller;
    if (controller == null || _places.isEmpty) return;
    final lats = _places.map((p) => p.lat);
    final lons = _places.map((p) => p.lon);
    final centerLat = (lats.reduce(math.min) + lats.reduce(math.max)) / 2;
    final centerLon = (lons.reduce(math.min) + lons.reduce(math.max)) / 2;

    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: Point(latitude: centerLat, longitude: centerLon),
          zoom: 11.0,
          azimuth: 0.0,
          tilt: 0.0,
        ),
      ),
    );
  }

  void _showDetails(Place p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.place_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(p.address)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.phone_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(p.tel)),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Заведения (вариант 9)')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Ошибка:\n$_error',
                    textAlign: TextAlign.center),
              ),
            )
          : Stack(
              children: [
                YandexMap(
                  onMapCreated: (controller) async {
                    _controller = controller;
                    await _fitCamera();
                  },
                  mapObjects: [
                    if (_markerIcon != null)
                      for (var i = 0; i < _places.length; i++)
                        PlacemarkMapObject(
                          mapId: MapObjectId('place_$i'),
                          point: Point(
                            latitude: _places[i].lat,
                            longitude: _places[i].lon,
                          ),
                          opacity: 1.0,
                          consumeTapEvents: true,
                          icon: PlacemarkIcon.single(
                            PlacemarkIconStyle(
                              image: _markerIcon!,
                              scale: 0.5,
                              anchor: const Offset(0.5, 1.0),
                            ),
                          ),
                          onTap: (_, __) => _showDetails(_places[i]),
                        ),
                  ],
                ),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }
}