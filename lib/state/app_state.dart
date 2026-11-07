import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/i18n.dart';
import '../core/models.dart';
import '../core/timeline.dart';
import '../data/db.dart';
import '../platform/native_bridge.dart';

class AppState extends ChangeNotifier {
  AppState(this.bridge, this.store, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final Bridge bridge;
  final LifeStore store;
  final DateTime Function() clock;

  LifeConfig config = const LifeConfig();
  LiveStatus live = const LiveStatus();
  Map<String, bool> perms = const {};
  List<Segment> today = const [];
  StreamSubscription<LiveStatus>? _sub;
  LifeMode _lastMode = LifeMode.normal;

  /// False until [init] has finished (or given up); the app shows a splash meanwhile.
  bool ready = false;

  /// Crash log from previous runs (v1.0.2). safeMode = last run crashed, engine not auto-started.
  CrashInfo crash = const CrashInfo();

  T get t => T(config.lang);

  static const _step = Duration(seconds: 4);

  /// Every step is guarded and time-limited: a failing or hanging platform call can never
  /// keep the app on a blank screen. Worst case the user sees onboarding with defaults.
  Future<void> init() async {
    try {
      await _init();
    } catch (e) {
      _report('init', e);
    } finally {
      if (!ready) {
        ready = true;
        notifyListeners();
      }
    }
  }

  Future<void> _init() async {
    try {
      config = await bridge.loadConfig().timeout(_step);
    } catch (e) {
      _report('init.loadConfig', e);
    }
    try {
      crash = await bridge.crashLog().timeout(_step);
    } catch (_) {}
    try {
      live = await bridge.status().timeout(_step);
    } catch (_) {}
    await refreshPerms();
    await refreshTimeline();
    try {
      _sub = bridge.statusStream().listen((s) {
        live = s;
        if (s.mode != _lastMode) {
          _lastMode = s.mode;
          refreshTimeline();
        }
        notifyListeners();
      }, onError: (_) {});
    } catch (e) {
      _report('init.statusStream', e);
    }
    ready = true;
    notifyListeners();
    if (config.onboarded && config.engineOn && !crash.safeMode) {
      try {
        await bridge.startService().timeout(_step);
      } catch (e) {
        _report('init.startService', e);
      }
    }
  }

  void _report(String where, Object e) {
    try {
      bridge.logError('$where: $e').catchError((_) {});
    } catch (_) {}
  }

  Future<void> refreshCrash() async {
    try {
      crash = await bridge.crashLog().timeout(_step);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> clearCrashLog() async {
    try {
      await bridge.clearCrashLog();
    } catch (_) {}
    crash = const CrashInfo();
    notifyListeners();
  }

  Future<void> shareCrashLog() async {
    try {
      await bridge.shareText('lifemode-crash-log.txt', crash.log);
    } catch (_) {}
  }

  /// Leave safe mode and try the context engine again.
  Future<void> retryEngine() async {
    try {
      await bridge.exitSafeMode();
      crash = CrashInfo(log: crash.log, fatal: crash.fatal);
      if (config.onboarded && config.engineOn) await bridge.startService();
    } catch (e) {
      _report('retryEngine', e);
    }
    notifyListeners();
  }

  Future<void> refreshPerms() async {
    try {
      perms = await bridge.permissions().timeout(_step);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshTimeline() async {
    final now = clock();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    try {
      today = Timeline.forDay(await store.eventsSince(start).timeout(_step), now, now);
    } catch (_) {
      today = const [];
    }
    notifyListeners();
  }

  Future<void> update(Map<String, dynamic> changes) async {
    config = config.copyWith(changes);
    notifyListeners();
    try {
      await bridge.saveConfig(config);
    } catch (e) {
      _report('saveConfig', e);
    }
  }

  Future<void> setOverride(LifeMode? m, {int minutes = 120}) async {
    if (m == null) {
      await update({'overrideMode': '', 'overrideUntilMs': 0});
    } else {
      final until = clock().add(Duration(minutes: minutes)).millisecondsSinceEpoch;
      await update({'overrideMode': m.name, 'overrideUntilMs': until});
    }
    await bridge.tickNow();
  }

  Future<void> setIncognito(Duration? d) async {
    final now = clock();
    int until = 0;
    if (d != null) {
      until = d == Duration.zero
          ? DateTime(now.year, now.month, now.day + 1, 6).millisecondsSinceEpoch // "until tomorrow"
          : now.add(d).millisecondsSinceEpoch;
    }
    await update({'incognitoUntilMs': until});
    await bridge.tickNow();
  }

  bool get incognito => config.incognitoAt(clock().millisecondsSinceEpoch);

  Future<void> finishOnboarding() async {
    await update({'onboarded': true, 'engineOn': true});
    try {
      await bridge.startService();
    } catch (e) {
      _report('finishOnboarding.startService', e);
    }
  }

  Future<void> setEngine(bool on) async {
    await update({'engineOn': on});
    try {
      on ? await bridge.startService() : await bridge.stopService();
    } catch (e) {
      _report('setEngine', e);
    }
  }

  Future<String> exportData() async {
    final data = await store.exportJson();
    await bridge.shareText('lifemode-export.json', data);
    return data;
  }

  Future<void> deleteData() async {
    await store.deleteAll();
    await refreshTimeline();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
