import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ftpconnect/ftpconnect.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FTP / SSH Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('FTP / SSH Client'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.folder_outlined), text: 'FTP'),
              Tab(icon: Icon(Icons.terminal), text: 'SSH'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FtpScreen(),
            SshScreen(),
          ],
        ),
      ),
    );
  }
}

class FtpScreen extends StatefulWidget {
  const FtpScreen({super.key});

  @override
  State<FtpScreen> createState() => _FtpScreenState();
}

class _FtpScreenState extends State<FtpScreen> {
  final _hostCtrl = TextEditingController(text: 'students.yss.su');
  final _portCtrl = TextEditingController(text: '21');
  final _userCtrl = TextEditingController(text: 'ftpiu8');
  final _passCtrl = TextEditingController(text: '3Ru7yOTA');
  final _dirCtrl = TextEditingController(text: 'vden');
  final _scrollCtrl = ScrollController();

  FTPConnect? _ftp;
  bool _connecting = false;
  bool _connected = false;
  bool _busy = false;
  String _cwd = '/';
  List<FTPEntry> _entries = [];
  String _log = '';

  @override
  void dispose() {
    final ftp = _ftp;
    if (ftp != null) {
      ftp.disconnect().catchError((_) => false);
    }
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _dirCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _append(String text) {
    if (!mounted) return;
    setState(() => _log += '$text\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }


  Future<void> _connect() async {
    if (_connecting || _connected || _busy) return;

    final host = _hostCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final port = int.tryParse(_portCtrl.text.trim());
    final startDir = _dirCtrl.text.trim();

    if (host.isEmpty || user.isEmpty) {
      _append('[!] Host and username are required.');
      return;
    }
    if (port == null) {
      _append('[!] Port must be a number.');
      return;
    }

    setState(() {
      _connecting = true;
      _log = '';
      _entries = [];
      _cwd = '/';
    });
    _append('[*] Connecting to $host:$port ...');

    try {
      final ftp =
      FTPConnect(host, user: user, pass: pass, port: port, timeout: 30);
      await ftp.connect();
      _ftp = ftp;
      if (mounted) setState(() => _connected = true);
      _append('[+] Connected.');

      if (startDir.isNotEmpty) {
        try {
          await ftp.changeDirectory(startDir);
          _append('[+] cwd -> $startDir');
        } catch (e) {
          _append('[!] cd $startDir failed: $e');
        }
      }
      await _refresh();
    } catch (e) {
      _append('[x] Connect failed: $e');
      _ftp = null;
      if (mounted) setState(() => _connected = false);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    final ftp = _ftp;
    _ftp = null;
    if (mounted) {
      setState(() {
        _connected = false;
        _entries = [];
        _cwd = '/';
      });
    }
    try {
      await ftp?.disconnect();
    } catch (_) {}
    _append('[*] Disconnected.');
  }


  Future<void> _refresh() async {
    final ftp = _ftp;
    if (ftp == null) return;
    if (mounted) setState(() => _busy = true);
    try {
      final cwd = await ftp.currentDirectory();
      final raw = await ftp.listDirectoryContent();
      final list = raw.where((e) => e.name != '.' && e.name != '..').toList();
      list.sort((a, b) {
        final aDir = a.type == FTPEntryType.dir;
        final bDir = b.type == FTPEntryType.dir;
        if (aDir != bDir) return aDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _cwd = cwd;
        _entries = list;
      });
    } catch (e) {
      _append('[x] List failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeDir(String target) async {
    final ftp = _ftp;
    if (ftp == null || _busy) return;
    if (mounted) setState(() => _busy = true);
    try {
      await ftp.changeDirectory(target);
      await _refresh();
    } catch (e) {
      _append('[x] cd $target failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _pickAndUpload() async {
    final ftp = _ftp;
    if (ftp == null || _busy) return;

    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null) {
        _append('[!] No file selected.');
        return;
      }
      final path = result.files.single.path;
      if (path == null) {
        _append('[!] Could not resolve local path.');
        return;
      }
      await _uploadFile(File(path));
    } catch (e) {
      _append('[x] Pick failed: $e');
    }
  }


  Future<void> _uploadMock() async {
    final ftp = _ftp;
    if (ftp == null || _busy) return;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final local = File('${Directory.systemTemp.path}/mock_$stamp.txt');
      await local.writeAsString('Hello from Flutter at ${DateTime.now()}');
      await _uploadFile(local);
    } catch (e) {
      _append('[x] Mock failed: $e');
    }
  }

  Future<void> _uploadFile(File local) async {
    final ftp = _ftp;
    if (ftp == null) return;

    if (mounted) setState(() => _busy = true);
    _append('[*] Uploading ${local.uri.pathSegments.last} -> $_cwd');
    try {
      final ok = await ftp.uploadFileWithRetry(local, pRetryCount: 2);
      _append(ok
          ? '[+] Uploaded: ${local.uri.pathSegments.last}'
          : '[x] Upload failed.');
      await _refresh();
    } catch (e) {
      _append('[x] Upload error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _download(FTPEntry entry) async {
    final ftp = _ftp;
    if (ftp == null || _busy) return;

    if (mounted) setState(() => _busy = true);
    _append('[*] Downloading ${entry.name} ...');

    try {
      final tempFile = File('${Directory.systemTemp.path}/${entry.name}');
      final ok = await ftp.downloadFileWithRetry(
        entry.name,
        tempFile,
        pRetryCount: 2,
      );
      if (!ok) {
        _append('[x] Download failed.');
        return;
      }

      final bytes = await tempFile.readAsBytes();
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${entry.name}',
        fileName: entry.name,
        bytes: bytes,
      );

      if (savedPath == null) {
        _append('[!] Save cancelled.');
        return;
      }

      _append('[+] Saved: $savedPath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: $savedPath')),
        );
      }
    } catch (e) {
      _append('[x] Download error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final locked = _connected || _connecting;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostCtrl,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'Host',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portCtrl,
                          enabled: !locked,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _userCtrl,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _passCtrl,
                          enabled: !locked,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _dirCtrl,
                    enabled: !locked,
                    decoration: const InputDecoration(
                      labelText: 'Start directory',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.folder_open),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _connecting || _busy
                              ? null
                              : _connected
                              ? _disconnect
                              : _connect,
                          icon: Icon(_connected ? Icons.link_off : Icons.link),
                          label: Text(
                            _connecting
                                ? 'Connecting...'
                                : _connected
                                ? 'Disconnect'
                                : 'Connect',
                          ),
                        ),
                      ),
                      if (_connected) ...[
                        const SizedBox(width: 8),
                        const Chip(
                          label: Text('connected'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          if (_connected)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickAndUpload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload file'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _uploadMock,
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Upload test .txt'),
                  ),
                ),
              ],
            ),

          if (_connected)
            Row(
              children: [
                IconButton(
                  tooltip: 'Up',
                  onPressed: _busy ? null : () => _changeDir('..'),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
                Expanded(
                  child: Text(
                    _cwd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),

          Expanded(
            child: !_connected
                ? const Center(
              child: Text(
                'Not connected.\nFill the form and press Connect.',
                textAlign: TextAlign.center,
              ),
            )
                : _busy && _entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                ? const Center(child: Text('Empty directory.'))
                : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) =>
              const Divider(height: 1),
              itemBuilder: (context, i) {
                final e = _entries[i];
                final isDir = e.type == FTPEntryType.dir;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isDir
                        ? Icons.folder
                        : Icons.insert_drive_file_outlined,
                    color: isDir ? Colors.amber : null,
                  ),
                  title: Text(e.name),
                  subtitle:
                  isDir ? null : Text('${e.size ?? '?'} B'),
                  trailing: isDir
                      ? const Icon(Icons.chevron_right)
                      : const Icon(Icons.download),
                  onTap: _busy
                      ? null
                      : () async {
                    if (isDir) {
                      await _changeDir(e.name);
                    } else {
                      await _download(e);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          Container(
            height: 110,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1114),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: SelectableText(
                _log.isEmpty ? '[log will appear here]' : _log,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                  color: _log.isEmpty
                      ? Colors.white38
                      : const Color(0xFFB9F6CA),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class SshScreen extends StatefulWidget {
  const SshScreen({super.key});

  @override
  State<SshScreen> createState() => _SshScreenState();
}

class _SshScreenState extends State<SshScreen> {
  final _hostCtrl = TextEditingController(text: 'net11.yss.su');
  final _portCtrl = TextEditingController(text: '9092');
  final _userCtrl = TextEditingController(text: 'root');
  final _passCtrl = TextEditingController(text: '123');
  final _cmdCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  SSHSocket? _socket;
  SSHClient? _client;
  bool _connecting = false;
  bool _connected = false;
  bool _running = false;
  String _output = '';

  @override
  void dispose() {
    try {
      _client?.close();
    } catch (_) {}
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _cmdCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _append(String text) {
    if (!mounted) return;
    setState(() => _output += text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _connect() async {
    if (_connecting || _connected) return;

    final host = _hostCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final port = int.tryParse(_portCtrl.text.trim());

    if (host.isEmpty || user.isEmpty) {
      _append('[!] Host and username are required.\n');
      return;
    }
    if (port == null) {
      _append('[!] Port must be a number.\n');
      return;
    }

    setState(() {
      _connecting = true;
      _output = '';
    });
    _append('[*] Connecting to $host:$port ...\n');

    try {
      final socket = await SSHSocket.connect(host, port,
          timeout: const Duration(seconds: 20));
      final client = SSHClient(socket,
          username: user, onPasswordRequest: () => pass);
      await client.authenticated;

      _socket = socket;
      _client = client;
      if (mounted) setState(() => _connected = true);
      _append('[+] Connected.\n');

      try {
        final uname = await client.run('uname -a');
        final text = utf8.decode(uname, allowMalformed: true).trim();
        if (text.isNotEmpty) _append('[server] $text\n');
      } catch (_) {}
    } catch (e) {
      _append('[x] Connection failed: $e\n');
      try {
        _socket?.close();
      } catch (_) {}
      _socket = null;
      _client = null;
      if (mounted) setState(() => _connected = false);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    final client = _client;
    _client = null;
    _socket = null;
    if (mounted) setState(() => _connected = false);
    try {
      client?.close();
      await client?.done;
    } catch (_) {}
    _append('\n[*] Disconnected.\n');
  }

  Future<void> _runCommand() async {
    final client = _client;
    if (client == null || _running) return;
    final cmd = _cmdCtrl.text.trim();
    if (cmd.isEmpty) return;

    _cmdCtrl.clear();
    if (mounted) setState(() => _running = true);
    _append('\n\$ $cmd\n');

    try {
      final bytes = await client.run(cmd);
      final text = utf8.decode(bytes, allowMalformed: true);
      _append(text);
      if (text.isNotEmpty && !text.endsWith('\n')) _append('\n');
    } catch (e) {
      _append('[x] Command failed: $e\n');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _connected || _connecting;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostCtrl,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'Host',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portCtrl,
                          enabled: !locked,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _userCtrl,
                          enabled: !locked,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _passCtrl,
                          enabled: !locked,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _connecting
                              ? null
                              : _connected
                              ? _disconnect
                              : _connect,
                          icon: Icon(_connected ? Icons.link_off : Icons.link),
                          label: Text(
                            _connecting
                                ? 'Connecting...'
                                : _connected
                                ? 'Disconnect'
                                : 'Connect',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_connected)
                        const Chip(
                          label: Text('connected'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmdCtrl,
                  enabled: _connected && !_running,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _runCommand(),
                  decoration: const InputDecoration(
                    hintText: 'Command (ls, uptime, pwd, ping ...)',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.chevron_right),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _connected && !_running ? _runCommand : null,
                child: _running
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('Run'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0E1114),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                child: SelectableText(
                  _output.isEmpty ? '[output will appear here]' : _output,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.35,
                    color: _output.isEmpty
                        ? Colors.white38
                        : const Color(0xFFB9F6CA),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}