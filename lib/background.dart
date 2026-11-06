// Headless Dart entrypoint run by the native foreground service
// (ContextService.kt -> BgEngine.kt). The service sends a context snapshot on
// every tick; we answer with the decided mode + notification content, and log
// mode changes / suggestions on-device.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'core/brain.dart';
import 'core/models.dart';
import 'core/rule_engine.dart';
import 'core/timeline.dart';
import 'data/db.dart';

const _channel = MethodChannel('lifemode/bg');

@pragma('vm:entry-point')
void backgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'tick') {
      final args = call.arguments is String ? jsonDecode(call.arguments as String) as Map : call.arguments as Map;
      return jsonEncode(await handleTick(args));
    }
    return null;
  });
  _channel.invokeMethod('ready');
}

LifeStore? _store;
int? _usualArrival;
int _usualArrivalAt = 0;

Future<Map<String, dynamic>> handleTick(Map args, {LifeStore? store}) async {
  final cfg = LifeConfig.fromJson(args['config'] as Map?);
  final snap = ContextSnapshot.fromJson(args['snapshot'] as Map? ?? const {});
  LifeStore? db = store;
  try {
    db ??= _store ??= await SqlLifeStore.open();
  } catch (_) {
    db = null; // storage failure must never stop mode switching
  }
  RuleHistory history = const RuleHistory();
  if (db != null) {
    try {
      history = await db.ruleHistory();
      if (snap.nowMs - _usualArrivalAt > 3600 * 1000) {
        _usualArrival = RuleEngine.usualHomeArrival(await db.homeArrivals());
        _usualArrivalAt = snap.nowMs;
      }
    } catch (_) {}
  }
  final r = Brain.tick(snap, cfg, history: history, usualHomeArrivalMin: _usualArrival);
  final incognito = cfg.incognitoAt(snap.nowMs);
  if (db != null && !incognito) {
    try {
      if (r.changed) {
        await db.logMode(ModeEvent(snap.nowMs, r.decision.mode, r.decision.reason, manual: r.decision.manual));
      }
      if (r.suggestion != null) await db.logSuggestion(snap.nowMs, r.suggestion!);
    } catch (_) {}
  }
  return r.toJson();
}
