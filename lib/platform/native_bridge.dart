// Flutter <-> Kotlin bridge. Channel names must match MainActivity.kt.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/models.dart';

/// Live status pushed by the foreground service.
class LiveStatus {
  final LifeMode mode;
  final String reason;
  final bool manual;
  final bool serviceRunning;
  final Map<String, dynamic> snapshot;
  final int focusStudySec;
  final int focusDistractedSec;
  final int pomodoroEndMs;
  const LiveStatus({
    this.mode = LifeMode.normal,
    this.reason = '',
    this.manual = false,
    this.serviceRunning = false,
    this.snapshot = const {},
    this.focusStudySec = 0,
    this.focusDistractedSec = 0,
    this.pomodoroEndMs = 0,
  });

  factory LiveStatus.fromMap(Map m) => LiveStatus(
        mode: LifeModeX.parse(m['mode']?.toString()),
        reason: (m['reason'] ?? '').toString(),
        manual: m['manual'] == true,
        serviceRunning: m['serviceRunning'] == true,
        snapshot: m['snapshot'] is Map ? Map<String, dynamic>.from(m['snapshot'] as Map) : const {},
        focusStudySec: (m['focusStudySec'] as num?)?.toInt() ?? 0,
        focusDistractedSec: (m['focusDistractedSec'] as num?)?.toInt() ?? 0,
        pomodoroEndMs: (m['pomodoroEndMs'] as num?)?.toInt() ?? 0,
      );
}

class AppInfo {
  final String package;
  final String label;
  const AppInfo(this.package, this.label);
}

/// Everything platform-specific goes through this interface so the UI can run
/// in tests/screenshots with [FakeBridge].
abstract class Bridge {
  Future<LifeConfig> loadConfig();
  Future<void> saveConfig(LifeConfig c);
  Future<Map<String, bool>> permissions();
  Future<void> requestPermission(String key);
  Future<void> startService();
  Future<void> stopService();
  Future<LiveStatus> status();
  Stream<LiveStatus> statusStream();
  Future<void> tickNow();
  Future<List<AppInfo>> launchableApps();
  Future<Map<String, dynamic>?> currentPlace(); // {lat,lng,ssid}
  Future<void> startPomodoro(int minutes);
  Future<void> stopPomodoro();
  Future<void> openWhatsAppOrSms(String phone, String text, String channel);
  Future<void> shareText(String fileName, String text);
  Future<void> setIconSwitching(bool on);
  Future<void> openMaps();
}

class NativeBridge implements Bridge {
  static const _m = MethodChannel('lifemode/native');
  static const _e = EventChannel('lifemode/status');

  @override
  Future<LifeConfig> loadConfig() async {
    final s = await _m.invokeMethod<String>('getConfig');
    if (s == null || s.isEmpty) return const LifeConfig();
    try {
      return LifeConfig.fromJson(jsonDecode(s) as Map);
    } catch (_) {
      return const LifeConfig();
    }
  }

  @override
  Future<void> saveConfig(LifeConfig c) => _m.invokeMethod('saveConfig', jsonEncode(c.toJson()));

  @override
  Future<Map<String, bool>> permissions() async {
    final m = await _m.invokeMapMethod<String, bool>('permissions');
    return m ?? {};
  }

  @override
  Future<void> requestPermission(String key) => _m.invokeMethod('requestPermission', key);
  @override
  Future<void> startService() => _m.invokeMethod('startService');
  @override
  Future<void> stopService() => _m.invokeMethod('stopService');

  @override
  Future<LiveStatus> status() async {
    final m = await _m.invokeMapMethod<String, dynamic>('status');
    return LiveStatus.fromMap(m ?? const {});
  }

  @override
  Stream<LiveStatus> statusStream() =>
      _e.receiveBroadcastStream().map((e) => LiveStatus.fromMap(e is Map ? e : const {}));

  @override
  Future<void> tickNow() => _m.invokeMethod('tickNow');

  @override
  Future<List<AppInfo>> launchableApps() async {
    final l = await _m.invokeListMethod<Map>('apps') ?? const [];
    return [for (final a in l) AppInfo(a['package'].toString(), a['label'].toString())];
  }

  @override
  Future<Map<String, dynamic>?> currentPlace() => _m.invokeMapMethod<String, dynamic>('currentPlace');
  @override
  Future<void> startPomodoro(int minutes) => _m.invokeMethod('startPomodoro', minutes);
  @override
  Future<void> stopPomodoro() => _m.invokeMethod('stopPomodoro');
  @override
  Future<void> openWhatsAppOrSms(String phone, String text, String channel) =>
      _m.invokeMethod('sendFamily', {'phone': phone, 'text': text, 'channel': channel});
  @override
  Future<void> shareText(String fileName, String text) =>
      _m.invokeMethod('shareFile', {'name': fileName, 'text': text});
  @override
  Future<void> setIconSwitching(bool on) => _m.invokeMethod('iconSwitching', on);
  @override
  Future<void> openMaps() => _m.invokeMethod('openMaps');
}

class FakeBridge implements Bridge {
  FakeBridge({LifeConfig? config, this.live = const LiveStatus(), this.perms = const {}})
      : config = config ?? const LifeConfig(onboarded: true);
  LifeConfig config;
  LiveStatus live;
  Map<String, bool> perms;
  final _ctl = StreamController<LiveStatus>.broadcast();

  @override
  Future<LifeConfig> loadConfig() async => config;
  @override
  Future<void> saveConfig(LifeConfig c) async => config = c;
  @override
  Future<Map<String, bool>> permissions() async => perms;
  @override
  Future<void> requestPermission(String key) async {}
  @override
  Future<void> startService() async {}
  @override
  Future<void> stopService() async {}
  @override
  Future<LiveStatus> status() async => live;
  @override
  Stream<LiveStatus> statusStream() => _ctl.stream;
  @override
  Future<void> tickNow() async {}
  @override
  Future<List<AppInfo>> launchableApps() async => const [
        AppInfo('com.instagram.android', 'Instagram'),
        AppInfo('com.google.android.youtube', 'YouTube'),
        AppInfo('com.snapchat.android', 'Snapchat'),
        AppInfo('com.whatsapp', 'WhatsApp'),
      ];
  @override
  Future<Map<String, dynamic>?> currentPlace() async => {'lat': 25.18, 'lng': 75.83, 'ssid': 'Ansari_Home'};
  @override
  Future<void> startPomodoro(int minutes) async {}
  @override
  Future<void> stopPomodoro() async {}
  @override
  Future<void> openWhatsAppOrSms(String phone, String text, String channel) async {}
  @override
  Future<void> shareText(String fileName, String text) async {}
  @override
  Future<void> setIconSwitching(bool on) async {}
  @override
  Future<void> openMaps() async {}
}
