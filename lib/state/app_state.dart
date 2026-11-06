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

  T get t => T(config.lang);

  Future<void> init() async {
    config = await bridge.loadConfig();
    try {
      live = await bridge.status();
    } catch (_) {}
    await refreshPerms();
    await refreshTimeline();
    _sub = bridge.statusStream().listen((s) {
      live = s;
      if (s.mode != _lastMode) {
        _lastMode = s.mode;
        refreshTimeline();
      }
      notifyListeners();
    }, onError: (_) {});
    if (config.onboarded && config.engineOn) await bridge.startService();
    notifyListeners();
  }

  Future<void> refreshPerms() async {
    try {
      perms = await bridge.permissions();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshTimeline() async {
    final now = clock();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    try {
      today = Timeline.forDay(await store.eventsSince(start), now, now);
    } catch (_) {
      today = const [];
    }
    notifyListeners();
  }

  Future<void> update(Map<String, dynamic> changes) async {
    config = config.copyWith(changes);
    notifyListeners();
    await bridge.saveConfig(config);
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
    await bridge.startService();
  }

  Future<void> setEngine(bool on) async {
    await update({'engineOn': on});
    on ? await bridge.startService() : await bridge.stopService();
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
