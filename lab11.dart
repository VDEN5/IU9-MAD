import 'dart:async';
import 'dart:convert' show HtmlEscape, base64Decode, utf8, latin1;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:mysql1/mysql1.dart';

void main() => runApp(const MyApp());

class SmtpConfig {
  static const String smtpHost = 'smtp.mail.ru';
  static const int    smtpPort = 465;
  static const String imapHost = 'imap.mail.ru';
  static const int    imapPort = 993;
  static const String username = 'voronov.denis.2005@mail.ru';
  static const String apiKey = '5eGjFdnFTlHQtwQQk7mi';

  static SmtpServer buildSmtp() => SmtpServer(
    smtpHost, port: smtpPort, ssl: true,
    username: username, password: apiKey,
  );
}

class DbConfig {
  static const String host     = 'students.yss.su';
  static const int    port     = 3306;
  static const String user     = 'iu9mobile';
  static const String password = 'bmstubmstu123';
  static const String db       = 'iu9mobile';

  static const String tSubs     = 'vden_smtp_andro';
  static const String tSettings = 'vden_smtp_settings';
}

String fmtDate(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} '
      '${two(t.hour)}:${two(t.minute)}';
}

String fmtTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String fmtMysql(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

class Db {
  static MySqlConnection? _conn;

  static Future<MySqlConnection> get() async {
    if (_conn != null) {
      try {
        await _conn!.query('SELECT 1');
        return _conn!;
      } catch (_) {
        try { await _conn!.close(); } catch (_) {}
        _conn = null;
      }
    }
    _conn = await MySqlConnection.connect(ConnectionSettings(
      host: DbConfig.host, port: DbConfig.port,
      user: DbConfig.user, password: DbConfig.password, db: DbConfig.db,
    ));
    return _conn!;
  }

  static Future<void> _try(MySqlConnection c, String sql,
      {Set<int> ignore = const {}}) async {
    try {
      await c.query(sql);
    } on MySqlException catch (e) {
      if (ignore.contains(e.errorNumber)) return;
      rethrow;
    }
  }

  static Future<void> ensureTables() async {
    final c = await get();

    await _try(c, '''
      CREATE TABLE IF NOT EXISTS ${DbConfig.tSubs} (
        name TEXT, surname TEXT, email TEXT,
        `if` INT(11) NOT NULL DEFAULT 0
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ''');
    await _try(c,
        'ALTER TABLE ${DbConfig.tSubs} MODIFY COLUMN `if` INT(11) NOT NULL DEFAULT 0');
    await _try(c,
        'ALTER TABLE ${DbConfig.tSubs} ADD COLUMN last_sent_at DATETIME NULL',
        ignore: {1060});
    await _try(c,
        'ALTER TABLE ${DbConfig.tSubs} ADD UNIQUE INDEX ux_email (email(255))',
        ignore: {1061, 1062});

    await c.query('''
      CREATE TABLE IF NOT EXISTS ${DbConfig.tSettings} (
        setting_key VARCHAR(64) NOT NULL PRIMARY KEY,
        setting_value VARCHAR(255) NOT NULL
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ''');
    await c.query(
      'INSERT IGNORE INTO ${DbConfig.tSettings} (setting_key, setting_value) VALUES '
          "('global_interval_minutes','60'),('local_interval_minutes','30')",
    );
  }

  static Future<void> close() async {
    try { await _conn?.close(); } catch (_) {}
    _conn = null;
  }
}

class Subscriber {
  final String lastName, firstName, email;
  bool isReplied;
  DateTime? lastSentAt;
  Subscriber({
    required this.lastName, required this.firstName, required this.email,
    this.isReplied = false, this.lastSentAt,
  });
  String get fullName => '$lastName $firstName';
  String get id => email;
}

class MailItem {
  final int? uid;
  final String from, fromName, subject, body;
  final DateTime receivedAt;
  final bool isHtml, isSpam;
  MailItem({
    this.uid,
    required this.from, required this.fromName,
    required this.subject, required this.body,
    required this.receivedAt, this.isHtml = false, this.isSpam = false,
  });
}

class EmailDecoder {
  static String decodeSubject(MimeMessage m) {
    String? candidate;
    try {
      candidate = m.decodeSubject();
    } catch (_) {}

    if (candidate == null || candidate.isEmpty) {
      try {
        final raw = m.getHeaderValue('subject');
        if (raw != null && raw.isNotEmpty) {
          candidate = _decodeMimeWords(raw);
        }
      } catch (_) {}
    }

    if (candidate == null || candidate.isEmpty) return '(без темы)';
    return _fixMojibake(candidate);
  }

  static ({String text, bool isHtml}) decodeBody(MimeMessage m) {
    final html = _tryDecode(() => m.decodeTextHtmlPart());
    final plain = _tryDecode(() => m.decodeTextPlainPart());

    if (html != null && html.isNotEmpty) {
      return (text: _fixMojibake(html), isHtml: true);
    }
    if (plain != null && plain.isNotEmpty) {
      return (text: _fixMojibake(plain), isHtml: false);
    }
    return (text: '(пустое письмо)', isHtml: false);
  }

  static String? _tryDecode(String? Function() f) {
    try { return f(); } catch (_) { return null; }
  }

  static String _decodeMimeWords(String raw) {
    final re = RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]*)\?=');
    return raw.replaceAllMapped(re, (match) {
      final charset = match.group(1)!.toLowerCase().trim();
      final encoding = match.group(2)!.toUpperCase();
      final text = match.group(3)!;
      try {
        List<int> bytes;
        if (encoding == 'B') {
          bytes = base64Decode(text);
        } else {
          final out = <int>[];
          for (var i = 0; i < text.length; i++) {
            final c = text[i];
            if (c == '_') {
              out.add(0x20);
            } else if (c == '=' && i + 2 < text.length) {
              out.add(int.parse(text.substring(i + 1, i + 3), radix: 16));
              i += 2;
            } else {
              out.add(c.codeUnitAt(0));
            }
          }
          bytes = out;
        }
        return _decodeBytes(bytes, charset);
      } catch (_) {
        return match.group(0) ?? '';
      }
    });
  }

  static String _decodeBytes(List<int> bytes, String charset) {
    final cs = charset.toLowerCase().replaceAll('_', '-');
    switch (cs) {
      case 'utf-8':
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'koi8-r':
      case 'koi8r':
        return _decodeKoi8r(bytes);
      case 'windows-1251':
      case 'cp1251':
      case 'win-1251':
        return _decodeCp1251(bytes);
      case 'iso-8859-1':
      case 'latin1':
      case 'latin-1':
        try {
          return utf8.decode(bytes, allowMalformed: false);
        } catch (_) {
          return latin1.decode(bytes, allowInvalid: true);
        }
      default:
        try {
          return utf8.decode(bytes, allowMalformed: false);
        } catch (_) {
          return latin1.decode(bytes, allowInvalid: true);
        }
    }
  }

  static String _decodeCp1251(List<int> bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.writeCharCode(b < 0x80 ? b : _cp1251[b - 0x80]);
    }
    return buf.toString();
  }

  static String _decodeKoi8r(List<int> bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.writeCharCode(b < 0x80 ? b : _koi8r[b - 0x80]);
    }
    return buf.toString();
  }

  static String _fixMojibake(String s) {
    if (s.isEmpty || !_looksLikeMojibake(s)) return s;

    final bytes = _stringToBytes(s);
    if (bytes.isEmpty) return s;

    try {
      final fixed = utf8.decode(bytes, allowMalformed: false);
      if (_hasCyrillic(fixed)) return fixed;
    } catch (_) {}

    try {
      final fixed = _decodeCp1251(bytes);
      if (_hasCyrillic(fixed) && !_looksLikeMojibake(fixed)) return fixed;
    } catch (_) {}

    return s;
  }

  static bool _hasCyrillic(String s) =>
      RegExp(r'[а-яА-ЯёЁ]').hasMatch(s);

  static bool _looksLikeMojibake(String s) {
    const markers = ['Ð', 'Ñ', 'Ã', 'Â', 'â€', 'Ï', 'ð'];
    for (final m in markers) {
      if (s.contains(m)) return true;
    }
    return false;
  }

  static List<int> _stringToBytes(String s) {
    final out = <int>[];
    for (final cu in s.codeUnits) {
      if (cu < 0x100) {
        out.add(cu);
      } else {
        final b = _cp1252Reverse[cu];
        if (b != null) {
          out.add(b);
        } else {
          return const [];
        }
      }
    }
    return out;
  }

  static const Map<int, int> _cp1252Reverse = {
    0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
    0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
    0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
    0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
    0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
    0x017E: 0x9E, 0x0178: 0x9F,
  };

  static const List<int> _cp1251 = [
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
    0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
    0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
    0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
    0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
    0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
    0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
    0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
    0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
    0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
    0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
    0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
  ];

  static const List<int> _koi8r = [
    0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518, 0x251C, 0x2524,
    0x252C, 0x2534, 0x253C, 0x2580, 0x2584, 0x2588, 0x258C, 0x2590,
    0x2591, 0x2592, 0x2593, 0x2320, 0x25A0, 0x2219, 0x221A, 0x2248,
    0x2264, 0x2265, 0x00A0, 0x2321, 0x00B0, 0x00B2, 0x00B7, 0x00F7,
    0x2550, 0x2551, 0x2552, 0x0451, 0x2553, 0x2554, 0x2555, 0x2556,
    0x2557, 0x2558, 0x2559, 0x255A, 0x255B, 0x255C, 0x255D, 0x255E,
    0x255F, 0x2560, 0x2561, 0x0401, 0x2562, 0x2563, 0x2564, 0x2565,
    0x2566, 0x2567, 0x2568, 0x2569, 0x256A, 0x256B, 0x256C, 0x00A9,
    0x044E, 0x0430, 0x0431, 0x0446, 0x0434, 0x0435, 0x0444, 0x0433,
    0x0445, 0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E,
    0x043F, 0x044F, 0x0440, 0x0441, 0x0442, 0x0443, 0x0436, 0x0432,
    0x044C, 0x044B, 0x0437, 0x0448, 0x044D, 0x0449, 0x0447, 0x044A,
    0x042E, 0x0410, 0x0411, 0x0426, 0x0414, 0x0415, 0x0424, 0x0413,
    0x0425, 0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E,
    0x041F, 0x042F, 0x0420, 0x0421, 0x0422, 0x0423, 0x0416, 0x0412,
    0x042C, 0x042B, 0x0417, 0x0428, 0x042D, 0x0429, 0x0427, 0x042A,
  ];
}

class ImapService {
  static Future<List<InternetAddress>> resolveWithRetry(
      String host, void Function(String) log, {int maxAttempts = 5}) async {
    const delays = [
      Duration(seconds: 1), Duration(seconds: 2),
      Duration(seconds: 3), Duration(seconds: 5),
    ];
    Object? lastError;
    for (var i = 1; i <= maxAttempts; i++) {
      try {
        final a = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 15));
        if (a.isEmpty) throw Exception('DNS: пусто для $host');
        log('DNS: $host -> ${a.map((x) => x.address).join(", ")}');
        return a;
      } catch (e) {
        lastError = e;
        log('DNS: $host попытка $i/$maxAttempts — $e');
        if (i < maxAttempts) await Future.delayed(delays[i - 1]);
      }
    }
    throw Exception('DNS не резолвит $host: $lastError');
  }

  static Future<List<MailItem>> fetchLast({
    required int count, required bool spam,
    required void Function(String) log,
  }) async {
    log('IMAP: fetch spam=$spam count=$count');
    if (SmtpConfig.apiKey.isEmpty) throw Exception('apiKey пуст');
    await resolveWithRetry(SmtpConfig.imapHost, log);

    final client = ImapClient(isLogEnabled: false);
    var connected = false;
    try {
      await client.connectToServer(
          SmtpConfig.imapHost, SmtpConfig.imapPort, isSecure: true);
      connected = true;
      await client.login(SmtpConfig.username, SmtpConfig.apiKey);
      log('IMAP: logged in');

      final boxes = await client.listMailboxes();
      int exists;
      if (spam) {
        final spamBox = boxes.firstWhere(
          (b) {
            final n = b.name.toLowerCase();
            return n.contains('spam') || n.contains('спам') ||
                n.contains('junk') || n.contains('нежелат');
          },
          orElse: () => throw Exception('Папка «Спам» не найдена: '
              '${boxes.map((b) => b.name).join(", ")}'),
        );
        final box = await client.selectMailbox(spamBox);
        exists = box?.messagesExists ?? 0;
      } else {
        final box = await client.selectInbox();
        exists = box?.messagesExists ?? 0;
      }
      log('IMAP: exists=$exists');
      if (exists == 0) return [];

      final start = math.max(1, exists - count + 1);
      final result = await client.fetchMessages(
          MessageSequence.fromRange(start, exists), '(UID BODY.PEEK[])');

      final items = <MailItem>[];
      for (final m in result.messages) {
        try {
          final fromAddr = (m.from?.isNotEmpty ?? false) ? m.from!.first : null;
          final body = EmailDecoder.decodeBody(m);
          final subject = EmailDecoder.decodeSubject(m);
          items.add(MailItem(
            uid: m.uid,
            from: fromAddr?.email ?? '?',
            fromName: fromAddr?.personalName ?? '',
            subject: subject,
            body: body.text,
            receivedAt: m.decodeDate() ?? DateTime.now(),
            isHtml: body.isHtml, isSpam: spam,
          ));
        } catch (e) { log('IMAP: parse warn $e'); }
      }
      items.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      log('IMAP: parsed ${items.length}');
      return items;
    } finally {
      if (connected) {
        try { await client.logout(); } catch (_) {}
        try { client.disconnect(); } catch (_) {}
      }
    }
  }

  static Future<bool> deleteFromServer({
    required int uid, required bool spam,
    required void Function(String) log,
  }) async {
    log('IMAP delete: uid=$uid spam=$spam');
    if (SmtpConfig.apiKey.isEmpty) { log('apiKey пуст'); return false; }
    await resolveWithRetry(SmtpConfig.imapHost, log);

    final client = ImapClient(isLogEnabled: false);
    var connected = false;
    try {
      await client.connectToServer(
          SmtpConfig.imapHost, SmtpConfig.imapPort, isSecure: true);
      connected = true;
      await client.login(SmtpConfig.username, SmtpConfig.apiKey);

      if (spam) {
        final boxes = await client.listMailboxes();
        final spamBox = boxes.firstWhere(
          (b) {
            final n = b.name.toLowerCase();
            return n.contains('spam') || n.contains('спам') ||
                n.contains('junk') || n.contains('нежелат');
          },
          orElse: () => throw Exception('Папка «Спам» не найдена'),
        );
        await client.selectMailbox(spamBox);
      } else {
        await client.selectInbox();
      }

      await client.uidStore(MessageSequence.fromRange(uid, uid), ['\\Deleted']);
      await client.expunge();
      log('IMAP delete: OK uid=$uid');
      return true;
    } catch (e) {
      log('IMAP delete: FAIL $e');
      return false;
    } finally {
      if (connected) {
        try { await client.logout(); } catch (_) {}
        try { client.disconnect(); } catch (_) {}
      }
    }
  }
}

enum DbStatus { connecting, ready, error }

class AppState extends ChangeNotifier {
  DbStatus dbStatus = DbStatus.connecting;
  String? dbError;

  final List<Subscriber> subscribers = [];
  final List<MailItem> inbox = [];
  final List<MailItem> spam = [];

  int globalIntervalMinutes = 60;
  int localIntervalMinutes = 30;

  int sendTotal = 0;
  int sendDone = 0;
  int sendSkipped = 0;
  int sendErrors = 0;
  bool isSending = false;

  bool isLoadingInbox = false;
  bool isLoadingSpam = false;
  bool isDiagnosing = false;

  String? lastError;
  String _lastSubject = 'Информационное письмо';
  String _lastTemplateText = '''
Это тестовое сообщение от нашей команды.

С уважением,
команда лаборатории.
''';

  Timer? _globalTimer;
  DateTime? _nextAutoSendAt;

  DateTime? get nextAutoSendAt => _nextAutoSendAt;
  bool get isAutoSendActive => _globalTimer?.isActive ?? false;

  final List<String> imapLog = [];

  bool get isReady => dbStatus == DbStatus.ready;

  void _log(String msg) {
    final line = '[${fmtTime(DateTime.now())}] $msg';
    imapLog.add(line);
    if (imapLog.length > 1000) imapLog.removeAt(0);
    print('[APP] $msg');
  }

  void clearLog() { imapLog.clear(); notifyListeners(); }

  String _fmtClock(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Future<void> connectDb() async {
    dbStatus = DbStatus.connecting;
    dbError = null;
    notifyListeners();
    try {
      _log('DB connect ${DbConfig.host}:${DbConfig.port}/${DbConfig.db}');
      await Db.get();
      await Db.ensureTables();
      await _loadSettings();
      await _loadSubscribers();
      dbStatus = DbStatus.ready;
      _log('DB ready. table=${DbConfig.tSubs}');
      _restartGlobalTimer();
      unawaited(_autoRefreshMails());
    } catch (e) {
      dbStatus = DbStatus.error;
      dbError = '$e';
      _log('DB error: $e');
    }
    notifyListeners();
  }

  Future<void> _autoRefreshMails() async {
    await refreshMails(spam: false);
    await refreshMails(spam: true);
  }

  @override
  void dispose() {
    _globalTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final c = await Db.get();
    final rows = await c.query(
        'SELECT setting_key, setting_value FROM ${DbConfig.tSettings}');
    for (final r in rows) {
      final k = r[0].toString();
      final v = int.tryParse(r[1].toString()) ?? 60;
      if (k == 'global_interval_minutes') globalIntervalMinutes = v;
      if (k == 'local_interval_minutes') localIntervalMinutes = v;
    }
  }

  Future<void> setGlobalInterval(int minutes) async {
    if (minutes <= 0) return;
    globalIntervalMinutes = minutes;
    _restartGlobalTimer();
    notifyListeners();
    try {
      final c = await Db.get();
      await c.query(
          "UPDATE ${DbConfig.tSettings} SET setting_value=? "
              "WHERE setting_key='global_interval_minutes'", ['$minutes']);
    } catch (e) { lastError = 'Сохранение настроек: $e'; }
  }

  Future<void> setLocalInterval(int minutes) async {
    if (minutes < 0) return;
    localIntervalMinutes = minutes;
    notifyListeners();
    try {
      final c = await Db.get();
      await c.query(
          "UPDATE ${DbConfig.tSettings} SET setting_value=? "
              "WHERE setting_key='local_interval_minutes'", ['$minutes']);
    } catch (e) { lastError = 'Сохранение настроек: $e'; }
  }

  void _restartGlobalTimer() {
    _globalTimer?.cancel();
    final interval = Duration(minutes: globalIntervalMinutes);
    _nextAutoSendAt = DateTime.now().add(interval);
    _globalTimer = Timer.periodic(interval, (_) {
      _nextAutoSendAt = DateTime.now().add(interval);
      unawaited(autoSendAll());
      notifyListeners();
    });
    _log('Auto-timer: каждые ${globalIntervalMinutes} мин, '
        'следующий в ${_fmtClock(_nextAutoSendAt!)}');
    notifyListeners();
  }

  void resetAutoTimer() => _restartGlobalTimer();

  Future<void> _loadSubscribers() async {
    final c = await Db.get();
    final rows = await c.query(
        'SELECT name, surname, email, `if`, last_sent_at '
            'FROM ${DbConfig.tSubs} ORDER BY surname, name');
    subscribers
      ..clear()
      ..addAll(rows.map((r) => Subscriber(
        firstName: r[0]?.toString() ?? '',
        lastName:  r[1]?.toString() ?? '',
        email:     r[2]?.toString() ?? '',
        isReplied: (r[3] is num && (r[3] as num).toInt() == 1),
        lastSentAt: r[4] is DateTime ? r[4] as DateTime : null,
      )));
    _log('subscribers loaded: ${subscribers.length}');
  }

  Future<void> addSubscriber(String lastName, String firstName, String email) async {
    if (!isReady) return;
    lastError = null;
    try {
      final c = await Db.get();
      final existing = await c.query(
          'SELECT email FROM ${DbConfig.tSubs} WHERE email=? LIMIT 1', [email]);
      if (existing.isNotEmpty) {
        lastError = 'Абонент с email $email уже существует';
        notifyListeners();
        return;
      }
      await c.query(
        'INSERT INTO ${DbConfig.tSubs} (name, surname, email, `if`, last_sent_at) '
            'VALUES (?, ?, ?, 0, NULL)',
        [firstName, lastName, email],
      );
      await _loadSubscribers();
    } catch (e) { lastError = 'DB: $e'; }
    notifyListeners();
  }

  Future<void> removeSubscriber(String email) async {
    if (!isReady) return;
    try {
      final c = await Db.get();
      await c.query('DELETE FROM ${DbConfig.tSubs} WHERE email=?', [email]);
      await _loadSubscribers();
    } catch (e) { lastError = 'DB: $e'; }
    notifyListeners();
  }

  Future<void> resetSendMarks() async {
    if (!isReady) return;
    try {
      final c = await Db.get();
      await c.query('UPDATE ${DbConfig.tSubs} SET `if`=0, last_sent_at=NULL');
      await _loadSubscribers();
      lastError = null;
      _log('Send marks reset for all subscribers');
    } catch (e) { lastError = 'DB: $e'; }
    notifyListeners();
  }

  Subscriber? findSubscriberByEmail(String email) {
    final lower = email.toLowerCase();
    for (final s in subscribers) {
      if (s.email.toLowerCase() == lower) return s;
    }
    return null;
  }

  void setTemplate(String subject, String textBody) {
    _lastSubject = subject;
    _lastTemplateText = textBody;
  }

  String _fmtRuDate(DateTime t) {
    const months = [
      'января','февраля','марта','апреля','мая','июня',
      'июля','августа','сентября','октября','ноября','декабря',
    ];
    return '${t.day} ${months[t.month - 1]} ${t.year} г.';
  }

  String _buildHtml(String firstName, String textBody) {
    const esc = HtmlEscape();
    final name = esc.convert(firstName.trim());
    final greeting = name.isEmpty ? 'Привет!' : 'Привет, $name!';
    final body = esc.convert(textBody).trim().replaceAll('\n', '<br>');
    final dateStr = _fmtRuDate(DateTime.now());

    return '''
<div style="margin:0;padding:0;background-color:#f4f6f8;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#f4f6f8;padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;background-color:#ffffff;border-radius:14px;overflow:hidden;box-shadow:0 4px 16px rgba(15,23,42,0.06);">
        <tr><td style="background-color:#4f46e5;background-image:linear-gradient(135deg,#3b82f6 0%,#6366f1 100%);padding:28px 32px;">
          <div style="font-size:12px;letter-spacing:1.5px;text-transform:uppercase;color:rgba(255,255,255,0.8);font-weight:600;">Рассылка</div>
          <div style="font-size:22px;line-height:1.3;color:#ffffff;font-weight:700;margin-top:8px;">$greeting</div>
        </td></tr>
        <tr><td style="padding:28px 32px 8px 32px;">
          <div style="font-size:15px;line-height:1.65;color:#1f2937;">$body</div>
        </td></tr>
        <tr><td style="padding:24px 32px 0 32px;">
          <div style="border-top:1px solid #e5e7eb;"></div>
        </td></tr>
        <tr><td style="padding:16px 32px 24px 32px;">
          <div style="font-size:12px;line-height:1.5;color:#9ca3af;">Письмо отправлено автоматически. Пожалуйста, не отвечайте на него.</div>
          <div style="font-size:12px;line-height:1.5;color:#9ca3af;margin-top:4px;">$dateStr</div>
        </td></tr>
      </table>
    </td></tr>
  </table>
</div>
''';
  }

  Future<void> sendToAll(String subject, String textBody,
      {bool force = false}) async {
    if (!isReady || isSending) return;
    if (subscribers.isEmpty) {
      lastError = 'Нет абонентов';
      notifyListeners();
      return;
    }
    if (SmtpConfig.apiKey.isEmpty) {
      lastError = 'SMTP apiKey не задан';
      notifyListeners();
      return;
    }

    isSending = true;
    lastError = null;
    sendTotal = subscribers.length;
    sendDone = 0;
    sendSkipped = 0;
    sendErrors = 0;
    notifyListeners();

    _log('sendToAll(force=$force): старт, абонентов=${subscribers.length}');

    final now = DateTime.now();
    for (final sub in List<Subscriber>.from(subscribers)) {
      if (!force &&
          localIntervalMinutes > 0 &&
          sub.lastSentAt != null) {
        final since = now.difference(sub.lastSentAt!).inMinutes;
        if (since < localIntervalMinutes) {
          sendSkipped++;
          sendDone++;
          _log('skip ${sub.email}: прошло $since мин, нужно $localIntervalMinutes');
          notifyListeners();
          continue;
        }
      }
      try {
        final html = _buildHtml(sub.firstName, textBody);
        final msg = mailer.Message()
          ..from = mailer.Address(SmtpConfig.username, 'Lab Robot')
          ..recipients.add(sub.email)
          ..subject = subject
          ..text = textBody
          ..html = html;
        await mailer.send(msg, SmtpConfig.buildSmtp());

        final c = await Db.get();
        await c.query(
          'UPDATE ${DbConfig.tSubs} SET `if`=1, last_sent_at=? WHERE email=?',
          [fmtMysql(DateTime.now()), sub.email],
        );
        sub.isReplied = true;
        sub.lastSentAt = DateTime.now();
        _log('sent ${sub.email}: OK');
      } catch (e) {
        sendErrors++;
        lastError = 'Отправка на ${sub.email}: $e';
        _log('send ${sub.email}: FAIL $e');
      }
      sendDone++;
      notifyListeners();
      await Future.delayed(const Duration(seconds: 1));
    }
    isSending = false;
    _log('sendToAll: done, отправлено=${sendDone - sendSkipped - sendErrors}, '
        'пропущено=$sendSkipped, ошибок=$sendErrors');
    notifyListeners();
  }

  Future<void> autoSendAll() async {
    if (!isReady) { _log('AUTO skip: БД не готова'); return; }
    if (_lastTemplateText.isEmpty || _lastSubject.isEmpty) {
      _log('AUTO skip: пустой шаблон'); return;
    }
    if (isSending) { _log('AUTO skip: предыдущая идёт'); return; }
    if (subscribers.isEmpty) { _log('AUTO skip: нет абонентов'); return; }
    _log('AUTO send: старт по таймеру, абонентов=${subscribers.length}');
    await sendToAll(_lastSubject, _lastTemplateText);
    _log('AUTO send: завершено');
  }

  Future<void> refreshMails({required bool spam}) async {
    if (!isReady) return;
    if (spam) { isLoadingSpam = true; } else { isLoadingInbox = true; }
    notifyListeners();
    try {
      final items = await ImapService.fetchLast(
          count: 10, spam: spam, log: _log);
      if (spam) { this.spam..clear()..addAll(items); }
      else      { inbox..clear()..addAll(items); }
      lastError = null;
      _log('refreshMails(${spam ? "spam" : "inbox"}) OK: ${items.length}');
    } catch (e) {
      lastError = 'IMAP (${spam ? "спам" : "входящие"}): $e';
      _log('refreshMails FAIL: $e');
    }
    if (spam) { isLoadingSpam = false; } else { isLoadingInbox = false; }
    notifyListeners();
  }

  Future<void> deleteMail(MailItem m) async {
    if (!isReady) return;
    if (m.uid == null) {
      lastError = 'Нет UID — удалить с сервера нельзя';
      notifyListeners();
      return;
    }
    lastError = null;
    notifyListeners();
    final ok = await ImapService.deleteFromServer(
        uid: m.uid!, spam: m.isSpam, log: _log);
    if (ok) {
      if (m.isSpam) spam.removeWhere((x) => x.uid == m.uid);
      else inbox.removeWhere((x) => x.uid == m.uid);
      _log('deleteMail uid=${m.uid} OK');
    } else {
      lastError = 'Не удалось удалить с сервера. Письмо осталось в списке.';
    }
    notifyListeners();
  }

  Future<void> runDiagnostics() async {
    if (isDiagnosing) return;
    isDiagnosing = true;
    clearLog();
    _log('=== Diagnostics start ===');
    notifyListeners();

    _log('--- DB ---');
    try {
      final c = await Db.get();
      final v = await c.query('SELECT VERSION()');
      _log('DB OK: ${v.first[0]}');
      final cnt = await c.query('SELECT COUNT(*) AS n FROM ${DbConfig.tSubs}');
      _log('DB rowcount: ${cnt.first[0]}');
    } catch (e) { _log('DB FAIL: $e'); }

    _log('--- DNS ---');
    for (final host in [DbConfig.host, SmtpConfig.imapHost,
      SmtpConfig.smtpHost, 'google.com']) {
      try {
        final a = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 10));
        _log('DNS $host: ${a.map((x) => x.address).join(", ")}');
      } catch (e) { _log('DNS $host FAIL: $e'); }
    }

    _log('--- SMTP ---');
    if (SmtpConfig.apiKey.isEmpty) {
      _log('SMTP SKIP: apiKey пуст');
    } else {
      try {
        final msg = mailer.Message()
          ..from = mailer.Address(SmtpConfig.username, 'Diag')
          ..recipients.add(SmtpConfig.username)
          ..subject = 'Diag ${DateTime.now().toIso8601String()}'
          ..text = 'test'
          ..html = '<b>test</b>';
        await mailer.send(msg, SmtpConfig.buildSmtp());
        _log('SMTP OK');
      } catch (e) { _log('SMTP FAIL: $e'); }
    }

    _log('--- IMAP inbox ---');
    try {
      final items = await ImapService.fetchLast(count: 3, spam: false, log: _log);
      _log('IMAP inbox OK: ${items.length}');
    } catch (e) { _log('IMAP inbox FAIL: $e'); }

    _log('--- IMAP spam ---');
    try {
      final items = await ImapService.fetchLast(count: 3, spam: true, log: _log);
      _log('IMAP spam OK: ${items.length}');
    } catch (e) { _log('IMAP spam FAIL: $e'); }

    _log('=== Diagnostics done ===');
    isDiagnosing = false;
    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Рассылка',
    theme: ThemeData(useMaterial3: true),
    home: const RootPage(),
    debugShowCheckedModeBanner: false,
  );
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState();
    _state.connectDb();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        switch (_state.dbStatus) {
          case DbStatus.connecting:
            return const Scaffold(
              body: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Подключение к БД…'),
                ],
              )),
            );
          case DbStatus.error:
            return Scaffold(body: Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Не удалось подключиться к БД',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SelectableText('${_state.dbError}',
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _state.connectDb,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Повторить'),
                ),
              ]),
            )));
          case DbStatus.ready:
            return HomePage(state: _state);
        }
      },
    );
  }
}

class HomePage extends StatefulWidget {
  final AppState state;
  const HomePage({super.key, required this.state});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.state.resetAutoTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Рассылка'),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const Icon(Icons.storage, color: Colors.green, size: 20),
                const SizedBox(width: 6),
                Text('${DbConfig.host}/${DbConfig.tSubs}',
                    style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ],
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Абоненты'),
            Tab(text: 'Рассылка'),
            Tab(text: 'Входящие'),
            Tab(text: 'Спам'),
            Tab(text: 'Ответы'),
            Tab(text: 'Настройки'),
          ]),
        ),
        body: TabBarView(children: [
          SubscribersTab(state: widget.state),
          SendTab(state: widget.state),
          InboxTab(state: widget.state, spam: false),
          InboxTab(state: widget.state, spam: true),
          RepliesTab(state: widget.state),
          SettingsTab(state: widget.state),
        ]),
      ),
    );
  }
}

class SubscribersTab extends StatefulWidget {
  final AppState state;
  const SubscribersTab({super.key, required this.state});
  @override
  State<SubscribersTab> createState() => _SubscribersTabState();
}

class _SubscribersTabState extends State<SubscribersTab> {
  final _formKey = GlobalKey<FormState>();
  final _lastNameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _lastNameCtrl.dispose();
    _firstNameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await widget.state.addSubscriber(
      _lastNameCtrl.text.trim(),
      _firstNameCtrl.text.trim(),
      _emailCtrl.text.trim(),
    );
    if (widget.state.lastError == null) {
      _lastNameCtrl.clear();
      _firstNameCtrl.clear();
      _emailCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Сохранено в БД')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final subs = widget.state.subscribers;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Form(key: _formKey, child: Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                SizedBox(width: 180, child: TextFormField(
                  controller: _lastNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Фамилия', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Укажите фамилию' : null,
                )),
                SizedBox(width: 180, child: TextFormField(
                  controller: _firstNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Имя', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Укажите имя' : null,
                )),
                SizedBox(width: 260, child: TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Укажите email';
                    final t = v.trim();
                    if (!t.contains('@') || !t.contains('.')) return 'Некорректный email';
                    return null;
                  },
                )),
                SizedBox(height: 48, child: ElevatedButton.icon(
                  onPressed: _busy ? null : _add,
                  icon: _busy
                      ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add),
                  label: const Text('Добавить'),
                )),
              ],
            )),
          ),
          if (widget.state.lastError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.state.lastError!,
                  style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text('Абонентов: ${subs.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              Text('Отправлено: ${subs.where((s) => s.isReplied).length}',
                  style: TextStyle(color: Colors.grey[700])),
              const Spacer(),
              Text('Таблица: ${DbConfig.tSubs}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12)),
            ]),
          ),
          const Divider(),
          Expanded(child: subs.isEmpty
              ? const Center(child: Text('Пока нет абонентов'))
              : ListView.separated(
            itemCount: subs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = subs[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(s.lastName.isNotEmpty
                      ? s.lastName[0].toUpperCase() : '?'),
                ),
                title: Text(s.fullName),
                subtitle: Text(s.email),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (s.isReplied)
                    const Tooltip(
                      message: 'Письмо отправлено',
                      child: Icon(Icons.check_circle,
                          color: Colors.green, size: 20),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDelete(s),
                  ),
                ]),
                onTap: () => _showDetails(s),
              );
            },
          )),
        ]);
      },
    );
  }

  void _showDetails(Subscriber s) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(s.fullName),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Email: ${s.email}'),
            const SizedBox(height: 8),
            Text('Письмо отправлено: ${s.isReplied ? "да" : "нет"}'),
            if (s.lastSentAt != null) ...[
              const SizedBox(height: 8),
              Text('Последняя отправка: ${fmtDate(s.lastSentAt!)}'),
            ],
          ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () {
            Navigator.pop(context);
            widget.state.removeSubscriber(s.email);
          },
          child: const Text('Удалить'),
        ),
      ],
    ));
  }

  void _confirmDelete(Subscriber s) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Удалить абонента?'),
      content: Text('${s.fullName} (${s.email})'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () {
            Navigator.pop(context);
            widget.state.removeSubscriber(s.email);
          },
          child: const Text('Удалить'),
        ),
      ],
    ));
  }
}

class SendTab extends StatefulWidget {
  final AppState state;
  const SendTab({super.key, required this.state});
  @override
  State<SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<SendTab> {
  final _subjectCtrl = TextEditingController(text: 'Информационное письмо');
  final _textCtrl = TextEditingController(text: '''
Это тестовое сообщение от нашей команды.

С уважением,
команда лаборатории.
''');

  DateTime? _lastManualSendAt;
  static const Duration _manualCooldown = Duration(seconds: 3);

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  String _fmtClock(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Future<void> _send() async {
    final s = widget.state;
    if (s.isSending) return;

    final now = DateTime.now();
    if (_lastManualSendAt != null &&
        now.difference(_lastManualSendAt!) < _manualCooldown) {
      final left = _manualCooldown - now.difference(_lastManualSendAt!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Подождите ${left.inSeconds + 1} с перед повторной отправкой'),
        ));
      }
      return;
    }

    if (s.subscribers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              'Нет абонентов — добавьте на вкладке «Абоненты»')));
      return;
    }

    _lastManualSendAt = now;
    s.setTemplate(_subjectCtrl.text, _textCtrl.text);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Рассылка запущена: ${s.subscribers.length} абонентов'),
    ));

    await s.sendToAll(_subjectCtrl.text, _textCtrl.text, force: true);
    s.resetAutoTimer();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Готово: отправлено '
            '${s.sendDone - s.sendSkipped - s.sendErrors} из ${s.sendTotal}'),
      ));
    }
  }

  Future<void> _resetMarks() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить метки отправки?'),
        content: const Text('У всех абонентов будут сброшены «Отправлено» '
            'и «Последняя отправка».'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.state.resetSendMarks();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        final progress = s.sendTotal == 0 ? 0.0 : s.sendDone / s.sendTotal;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: s.isAutoSendActive
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                border: Border.all(
                  color: s.isAutoSendActive
                      ? Colors.green.shade200
                      : Colors.orange.shade300,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(
                  s.isAutoSendActive
                      ? Icons.autorenew
                      : Icons.pause_circle_outline,
                  color: s.isAutoSendActive
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  s.isAutoSendActive
                      ? 'Авторассылка: каждые ${s.globalIntervalMinutes} мин\n'
                      'Следующая: '
                      '${s.nextAutoSendAt != null ? _fmtClock(s.nextAutoSendAt!) : "—"}'
                      : 'Авторассылка не активна',
                  style: TextStyle(
                    color: s.isAutoSendActive
                        ? Colors.green.shade900
                        : Colors.orange.shade900,
                    fontSize: 13,
                    height: 1.4,
                  ),
                )),
              ]),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(
                labelText: 'Тема письма', border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.subject),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              minLines: 8, maxLines: 18,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Текст письма',
                helperText: 'Письмо начнётся с «Привет, {имя}!» в шапке-карточке.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            if (s.isSending) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                'Обработано ${s.sendDone} из ${s.sendTotal}'
                    ' • пропущено: ${s.sendSkipped}'
                    ' • ошибок: ${s.sendErrors}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Text(
                'Абонентов: ${s.subscribers.length}. '
                    'Отправлено (по флагу в БД): '
                    '${s.subscribers.where((x) => x.isReplied).length}.',
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 12),
            ],

            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: s.isSending ? null : _send,
                icon: s.isSending
                    ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: Text(s.isSending
                    ? 'Отправка...' : 'Отправить всем абонентам'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: s.isSending ? null : _resetMarks,
              icon: const Icon(Icons.restore),
              label: const Text('Сбросить метки отправки'),
            ),

            if (s.lastError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(s.lastError!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ],

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Пример того, что увидит абонент:',
                      style: TextStyle(
                          color: Colors.grey[700], fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text('Привет, Иван!',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(_textCtrl.text.isEmpty ? '…' : _textCtrl.text,
                      style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Text(
              'Глобальный интервал: раз в ${s.globalIntervalMinutes} мин\n'
                  'Локальный интервал: не чаще раза в ${s.localIntervalMinutes} мин '
                  '(0 — без ограничений)',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ]),
        );
      },
    );
  }
}

class InboxTab extends StatefulWidget {
  final AppState state;
  final bool spam;
  const InboxTab({super.key, required this.state, required this.spam});
  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.state.refreshMails(spam: widget.spam);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        final items = widget.spam ? s.spam : s.inbox;
        final loading = widget.spam ? s.isLoadingSpam : s.isLoadingInbox;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Text(
                widget.spam
                    ? 'Спам (последние 10)'
                    : 'Входящие (последние 10)',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Логи',
                icon: const Icon(Icons.bug_report),
                onPressed: () {
                  showDialog(context: context,
                      builder: (_) => _LogDialog(state: s));
                },
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => s.refreshMails(spam: widget.spam),
                ),
            ]),
          ),
          if (s.lastError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(s.lastError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(loading
                ? 'Загрузка...'
                : 'Писем нет. Нажмите «Обновить».'))
                : RefreshIndicator(
              onRefresh: () => s.refreshMails(spam: widget.spam),
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final m = items[i];
                  return ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(m.subject,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${m.from} • ${fmtDate(m.receivedAt)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmDelete(context, m),
                    ),
                    onTap: () {
                      showDialog(context: context,
                          builder: (_) => _MailViewDialog(mail: m));
                    },
                  );
                },
              ),
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, MailItem m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить письмо?'),
        content: Text('${m.from}\n«${m.subject}»\n\n'
            'Письмо будет удалено с почтового ящика (mail.ru).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.state.deleteMail(m);
  }
}

class RepliesTab extends StatelessWidget {
  final AppState state;
  const RepliesTab({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final replies = state.inbox
            .where((m) => state.findSubscriberByEmail(m.from) != null)
            .toList();
        if (replies.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Пока нет писем от известных абонентов.\n\n'
                    'Проверьте вкладку «Входящие» и нажмите «Обновить».',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              const Text('Ответы абонентов',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${replies.length} шт.',
                  style: TextStyle(color: Colors.grey[700])),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: replies.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = replies[i];
                final sub = state.findSubscriberByEmail(m.from)!;
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(sub.lastName.isNotEmpty
                        ? sub.lastName[0].toUpperCase() : '?'),
                  ),
                  title: Text(m.subject,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${sub.fullName} <${m.from}> • ${fmtDate(m.receivedAt)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Удалить ответ',
                    onPressed: () => _confirmDelete(context, m, sub),
                  ),
                  onTap: () {
                    showDialog(context: context,
                        builder: (_) =>
                            _MailViewDialog(mail: m, subscriber: sub));
                  },
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, MailItem m, Subscriber sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить ответ?'),
        content: Text('${sub.fullName} <${m.from}>\n«${m.subject}»\n\n'
            'Письмо будет удалено с почтового ящика (mail.ru), '
            'а также из «Ответов» и «Входящих».'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) await state.deleteMail(m);
  }
}

class _MailViewDialog extends StatelessWidget {
  final MailItem mail;
  final Subscriber? subscriber;
  const _MailViewDialog({required this.mail, this.subscriber});

  @override
  Widget build(BuildContext context) {
    final fromLine = subscriber != null
        ? '${subscriber!.fullName} <${mail.from}>'
        : (mail.fromName.isNotEmpty
        ? '${mail.fromName} <${mail.from}>'
        : mail.from);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(children: [
                const Icon(Icons.mail_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mail.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('От: $fromLine',
                      style: TextStyle(color: Colors.grey[800], fontSize: 13)),
                  Text('Дата: ${fmtDate(mail.receivedAt)}',
                      style: TextStyle(color: Colors.grey[800], fontSize: 13)),
                  if (mail.isHtml)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('HTML',
                            style: TextStyle(color: Colors.blue, fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: mail.isHtml
                    ? HtmlWidget(
                  mail.body,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.black87,
                  ),
                )
                    : SelectableText(
                  mail.body,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogDialog extends StatelessWidget {
  final AppState state;
  const _LogDialog({required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final lines = state.imapLog;
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.bug_report),
            const SizedBox(width: 8),
            const Text('Логи'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: state.clearLog,
            ),
          ]),
          content: SizedBox(
            width: 720, height: 480,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(8),
              child: lines.isEmpty
                  ? const Center(
                  child: Text('Пусто.',
                      style: TextStyle(
                          color: Colors.white54,
                          fontFamily: 'monospace',
                          fontSize: 12)))
                  : SingleChildScrollView(
                child: SelectableText(
                  lines.join('\n'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }
}

class SettingsTab extends StatefulWidget {
  final AppState state;
  const SettingsTab({super.key, required this.state});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _globalCtrl;
  late final TextEditingController _localCtrl;

  @override
  void initState() {
    super.initState();
    _globalCtrl = TextEditingController(
        text: '${widget.state.globalIntervalMinutes}');
    _localCtrl = TextEditingController(
        text: '${widget.state.localIntervalMinutes}');
  }

  @override
  void dispose() {
    _globalCtrl.dispose();
    _localCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final g = int.tryParse(_globalCtrl.text.trim());
    final l = int.tryParse(_localCtrl.text.trim());
    if (g == null || g <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Некорректный глобальный интервал')));
      return;
    }
    if (l == null || l < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Некорректный локальный интервал')));
      return;
    }
    await widget.state.setGlobalInterval(g);
    await widget.state.setLocalInterval(l);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранено в БД')));
    }
  }

  Future<void> _preset(int global, int local, String msg) async {
    _globalCtrl.text = '$global';
    _localCtrl.text = '$local';
    await widget.state.setGlobalInterval(global);
    await widget.state.setLocalInterval(local);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _diagnose() {
    widget.state.runDiagnostics();
    showDialog(context: context,
        builder: (_) => _LogDialog(state: widget.state));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _globalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Глобальный интервал (мин)',
                    helperText: 'Раз в это время автоматически рассылаем всем',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.schedule),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _localCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Локальный интервал (мин)',
                    helperText: 'Одному абоненту не чаще раза в это время '
                        '(0 — без ограничений)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => _preset(1, 0,
                        'Тест: авто каждую минуту, без локального лимита'),
                    icon: const Icon(Icons.speed),
                    label: const Text('Тест: раз в минуту'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => _preset(60, 30,
                        'Продакшн: авто 60 мин, локально 30 мин'),
                    icon: const Icon(Icons.tune),
                    label: const Text('60 / 30'),
                  )),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Сохранить в БД'),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Диагностика',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'Проверит БД, DNS, SMTP и IMAP по INBOX и Спаму. Всё в журнале.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: widget.state.isDiagnosing ? null : _diagnose,
                      icon: widget.state.isDiagnosing
                          ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.health_and_safety),
                      label: Text(widget.state.isDiagnosing
                          ? 'Выполняется…' : 'Проверить БД/SMTP/IMAP'),
                    ),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Показать журнал',
                    onPressed: () {
                      showDialog(context: context,
                          builder: (_) => _LogDialog(state: widget.state));
                    },
                    icon: const Icon(Icons.bug_report),
                  ),
                ]),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    'Интервалы (в ${DbConfig.tSettings}):\n'
                        '• Глобальный — ${widget.state.globalIntervalMinutes} мин\n'
                        '• Локальный — ${widget.state.localIntervalMinutes} мин\n\n'
                        'Письма не хранятся в БД:\n'
                        '• Входящие/Спам/Ответы каждый раз тянутся с mail.ru\n'
                        '• «Удалить» → IMAP uidStore \\Deleted + EXPUNGE\n'
                        '• HTML-письма рендерятся (flutter_widget_from_html_core)\n'
                        '• Кодировки писем: UTF-8, CP1251, KOI8-R, mojibake\n\n'
                        'В БД только:\n'
                        '• ${DbConfig.tSubs} — абоненты\n'
                        '• ${DbConfig.tSettings} — интервалы\n'
                        'Хост: ${DbConfig.host}/${DbConfig.db}',
                    style: TextStyle(
                        color: Colors.blue.shade900, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}