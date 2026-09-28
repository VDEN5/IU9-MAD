import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Счётчик + iocontrol',
      theme: ThemeData(useMaterial3: true),
      home: const CounterPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
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
        print('Ошибка загрузки: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка загрузки: $e');
    }
    setState(() => _isLoading = false);
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
        print('Счётчик обновлён: $newValue');
        await _loadCounter();
      } else {
        print('Ошибка обновления: ${response.statusCode}');
        await _loadCounter();
      }
    } catch (e) {
      print('Ошибка обновления: $e');
      await _loadCounter();
    }
    setState(() => _isLoading = false);
  }

  void _onSliderChangeEnd(double newValue) {
    _updateCounter(newValue.round());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Счётчик (iocontrol)'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadCounter,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Текущее значение:',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                Text(
                  '$_counter',
                  style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 40),

              Row(
                children: [
                  Text('$_minValue'),
                  Expanded(
                    child: Slider(
                      value: _counter.toDouble().clamp(_minValue.toDouble(), _maxValue.toDouble()),
                      min: _minValue.toDouble(),
                      max: _maxValue.toDouble(),
                      divisions: (_maxValue - _minValue).abs(),
                      label: _counter.toString(),
                      onChanged: _isLoading
                          ? null
                          : (newValue) {
                              setState(() {
                                _counter = newValue.round();
                              });
                            },
                      onChangeEnd: _isLoading ? null : _onSliderChangeEnd,
                    ),
                  ),
                  Text('$_maxValue'),
                ],
              ),
              const SizedBox(height: 12),

              Text(
                'Последнее обновление    : $_lastUpdate',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}