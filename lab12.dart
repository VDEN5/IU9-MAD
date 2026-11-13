import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Messenger',
      theme: ThemeData(useMaterial3: false),
      home: const BluetoothMessengerPage(),
    );
  }
}

class BluetoothMessengerPage extends StatefulWidget {
  const BluetoothMessengerPage({super.key});

  @override
  State<BluetoothMessengerPage> createState() => _BluetoothMessengerPageState();
}

class _BluetoothMessengerPageState extends State<BluetoothMessengerPage> {
  static const platform = MethodChannel('bluetooth.messenger/channel');

  final TextEditingController _messageController = TextEditingController();
  final List<String> _receivedMessages = [];
  final ScrollController _scrollController = ScrollController();

  bool _isConnected = false;
  String _statusMessage = 'Disconnected';
  String? _connectedAddress;
  String? _connectedDevice;
  List<Map<String, dynamic>> _devices = [];
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _startListeningForEvents();
    _init();
  }

  Future<void> _init() async {
    await _initializeBluetooth();
    await _loadPairedDevices();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    try {
      final bool result = await platform.invokeMethod('initializeBluetooth');
      setState(() {
        _isConnected = result;
        _statusMessage = result ? 'Connected' : 'Waiting for connection...';
      });
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.message}';
      });
    }
  }

  Future<void> _loadPairedDevices() async {
    try {
      final raw = await platform.invokeMethod('getPairedDevices');
      if (raw is List) {
        final devices = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (!mounted) return;
        setState(() {
          _devices = devices;
        });
      }
    } on PlatformException catch (e) {
      _showSnackBar('Ошибка списка устройств: ${e.message}');
    }
  }

  void _startListeningForEvents() {
    const eventChannel = EventChannel('bluetooth.messenger/events');
    _messageSubscription = eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          if (event['type'] == 'message') {
            setState(() {
              _receivedMessages.add(event['data']?.toString() ?? '');
            });
            _scrollToBottom();
          } else if (event['type'] == 'connection') {
            final connected = event['connected'] == true;
            final device = event['device']?.toString();
            setState(() {
              _isConnected = connected;
              if (connected) {
                _connectedDevice = device;
                _connectedAddress = event['address']?.toString();
                _statusMessage = device != null
                    ? 'Connected: $device'
                    : 'Connected';
              } else {
                _connectedDevice = null;
                _connectedAddress = null;
                _statusMessage = 'Disconnected';
              }
            });
            _loadPairedDevices();
          } else if (event['type'] == 'error') {
            final message = event['message']?.toString() ?? 'Unknown error';
            setState(() {
              _statusMessage = 'Error: $message';
            });
            _showSnackBar(message);
          }
        }
      },
      onError: (dynamic error) {
        setState(() {
          _statusMessage = 'Error: $error';
        });
      },
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      final bool success = await platform.invokeMethod(
        'sendMessage',
        {'message': message},
      );
      if (success) {
        setState(() {
          _messageController.clear();
          _scrollToBottom();
        });
      } else {
        _showSnackBar('Не удалось отправить');
      }
    } on PlatformException catch (e) {
      _showSnackBar('Ошибка: ${e.message}');
    }
  }

  Future<void> _connectToDevice(String address) async {
    try {
      await platform.invokeMethod('connectToDevice', {'address': address});
    } on PlatformException catch (e) {
      _showSnackBar('Ошибка подключения: ${e.message}');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Messenger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить список',
            onPressed: _loadPairedDevices,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Сопряжённые устройства',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${_devices.length})',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _devices.isEmpty
                  ? const Center(
                      child: Text(
                        'Нет сопряжённых устройств',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _devices.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final d = _devices[index];
                        final name = d['name']?.toString() ?? 'Unknown';
                        final address = d['address']?.toString() ?? '';
                        final connected = d['connected'] == true;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.bluetooth,
                            color: connected ? Colors.blue : Colors.grey,
                            size: 20,
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontWeight: connected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            address,
                            style: const TextStyle(fontSize: 10),
                          ),
                          trailing: connected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20,
                                )
                              : TextButton(
                                  onPressed: () => _connectToDevice(address),
                                  child: const Text(
                                    'Connect',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                          onTap: connected
                              ? null
                              : () => _connectToDevice(address),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              enabled: _isConnected,
              onSubmitted: (_) => _sendMessage(),
            ),

            const SizedBox(height: 6),

            ElevatedButton(
              onPressed: _isConnected ? _sendMessage : null,
              child: const Text('Send'),
            ),

            const SizedBox(height: 8),

            Text(
              'Статус: $_statusMessage',
              style: TextStyle(
                fontSize: 13,
                color: _isConnected ? Colors.green : Colors.grey.shade700,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Сообщения:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),

            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _receivedMessages.isEmpty
                    ? const Center(
                        child: Text(
                          'Сообщений пока нет',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _receivedMessages.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(_receivedMessages[index]),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}