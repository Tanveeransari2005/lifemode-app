// On-device storage (sqflite). Nothing ever leaves the phone.
//   mode_events : one row per mode change (the timeline)
//   suggestions : one row per suggestion shown (for rate limits)
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/models.dart';
import '../core/rule_engine.dart';
import '../core/timeline.dart';

abstract class LifeStore {
  Future<void> logMode(ModeEvent e);
  Future<void> logSuggestion(int atMs, Suggestion s);
  Future<List<ModeEvent>> eventsSince(int ms);
  Future<RuleHistory> ruleHistory();
  Future<List<int>> homeArrivals({int days = 14});
  Future<String> exportJson();
  Future<void> deleteAll();
}

class SqlLifeStore implements LifeStore {
  SqlLifeStore._(this._db);
  final Database _db;
  static SqlLifeStore? _instance;

  static Future<SqlLifeStore> open() async {
    if (_instance != null) return _instance!;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'lifemode.db'),
      version: 1,
      onConfigure: (db) async => db.rawQuery('PRAGMA busy_timeout = 3000'),
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE mode_events(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'start_ms INTEGER NOT NULL, mode TEXT NOT NULL, reason TEXT, manual INTEGER DEFAULT 0)');
        await db.execute('CREATE INDEX ix_mode_start ON mode_events(start_ms)');
        await db.execute('CREATE TABLE suggestions(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'at_ms INTEGER NOT NULL, rule TEXT NOT NULL, title TEXT, body TEXT)');
      },
    );
    return _instance = SqlLifeStore._(db);
  }

  @override
  Future<void> logMode(ModeEvent e) => _db.insert('mode_events', e.toRow());

  @override
  Future<void> logSuggestion(int atMs, Suggestion s) =>
      _db.insert('suggestions', {'at_ms': atMs, 'rule': s.id, 'title': s.title, 'body': s.body});

  @override
  Future<List<ModeEvent>> eventsSince(int ms) async {
    // Include the last event before [ms] so the period starts in a known mode.
    final before = await _db.query('mode_events',
        where: 'start_ms < ?', whereArgs: [ms], orderBy: 'start_ms DESC', limit: 1);
    final rows = await _db.query('mode_events', where: 'start_ms >= ?', whereArgs: [ms], orderBy: 'start_ms');
    return [...before.map(ModeEvent.fromRow), ...rows.map(ModeEvent.fromRow)];
  }

  @override
  Future<RuleHistory> ruleHistory() async {
    final rows = await _db.rawQuery('SELECT rule, MAX(at_ms) AS last FROM suggestions GROUP BY rule');
    final m = <String, int>{for (final r in rows) r['rule'] as String: (r['last'] as num).toInt()};
    final any = m.values.fold<int>(0, (a, b) => a > b ? a : b);
    return RuleHistory(lastAnyMs: any, lastByRule: m);
  }

  @override
  Future<List<int>> homeArrivals({int days = 14}) async {
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final rows = await _db.query('mode_events',
        where: "mode = 'home' AND manual = 0 AND start_ms >= ?", whereArgs: [since], orderBy: 'start_ms');
    final firstPerDay = <String, int>{};
    for (final r in rows) {
      final t = DateTime.fromMillisecondsSinceEpoch((r['start_ms'] as num).toInt());
      final m = t.hour * 60 + t.minute;
      if (m < 15 * 60) continue;
      firstPerDay.putIfAbsent('${t.year}-${t.month}-${t.day}', () => m);
    }
    return firstPerDay.values.toList();
  }

  @override
  Future<String> exportJson() async {
    final modes = await _db.query('mode_events', orderBy: 'start_ms');
    final sugg = await _db.query('suggestions', orderBy: 'at_ms');
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'LifeMode',
      'exportedAt': DateTime.now().toIso8601String(),
      'modeEvents': modes,
      'suggestions': sugg,
    });
  }

  @override
  Future<void> deleteAll() async {
    await _db.delete('mode_events');
    await _db.delete('suggestions');
  }
}

/// In-memory store for tests / screenshots.
class MemoryLifeStore implements LifeStore {
  final events = <ModeEvent>[];
  final sugg = <(int, Suggestion)>[];
  @override
  Future<void> logMode(ModeEvent e) async => events.add(e);
  @override
  Future<void> logSuggestion(int atMs, Suggestion s) async => sugg.add((atMs, s));
  @override
  Future<List<ModeEvent>> eventsSince(int ms) async {
    final sorted = [...events]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final before = sorted.where((e) => e.startMs < ms).toList();
    return [if (before.isNotEmpty) before.last, ...sorted.where((e) => e.startMs >= ms)];
  }

  @override
  Future<RuleHistory> ruleHistory() async {
    final m = <String, int>{};
    for (final (t, s) in sugg) {
      if ((m[s.id] ?? 0) < t) m[s.id] = t;
    }
    return RuleHistory(lastAnyMs: m.values.fold(0, (a, b) => a > b ? a : b), lastByRule: m);
  }

  @override
  Future<List<int>> homeArrivals({int days = 14}) async => const [];
  @override
  Future<String> exportJson() async => jsonEncode({'modeEvents': events.length});
  @override
  Future<void> deleteAll() async {
    events.clear();
    sugg.clear();
  }
}


/// v1.0.2: lets the UI start before the database is open. Opens [open] once with a
/// timeout; if that fails, falls back to an in-memory store so nothing ever blocks launch.
class DeferredLifeStore implements LifeStore {
  DeferredLifeStore(Future<LifeStore> Function() open, {Duration timeout = const Duration(seconds: 6)})
      : _store = _openSafely(open, timeout);
  final Future<LifeStore> _store;

  static Future<LifeStore> _openSafely(Future<LifeStore> Function() open, Duration timeout) async {
    try {
      return await open().timeout(timeout);
    } catch (_) {
      return MemoryLifeStore();
    }
  }

  @override
  Future<void> logMode(ModeEvent e) async => (await _store).logMode(e);
  @override
  Future<void> logSuggestion(int atMs, Suggestion s) async => (await _store).logSuggestion(atMs, s);
  @override
  Future<List<ModeEvent>> eventsSince(int ms) async => (await _store).eventsSince(ms);
  @override
  Future<RuleHistory> ruleHistory() async => (await _store).ruleHistory();
  @override
  Future<List<int>> homeArrivals({int days = 14}) async => (await _store).homeArrivals(days: days);
  @override
  Future<String> exportJson() async => (await _store).exportJson();
  @override
  Future<void> deleteAll() async => (await _store).deleteAll();
}
