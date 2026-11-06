// Pure-Dart data types shared by the UI, the background brain and tests.
// No Flutter imports here, so everything in lib/core/ is unit-testable.

enum LifeMode { normal, driving, study, sleep, home }

extension LifeModeX on LifeMode {
  String get id => name;
  static LifeMode parse(String? s) =>
      LifeMode.values.firstWhere((m) => m.name == s, orElse: () => LifeMode.normal);
}

/// A study block from the user's own weekly schedule (no calendar needed).
class StudySlot {
  final int weekday; // 1 = Monday … 7 = Sunday (DateTime.weekday)
  final int startMin; // minutes from midnight
  final int endMin;
  const StudySlot(this.weekday, this.startMin, this.endMin);

  bool covers(DateTime t) {
    if (t.weekday != weekday) return false;
    final m = t.hour * 60 + t.minute;
    return m >= startMin && m < endMin;
  }

  Map<String, dynamic> toJson() => {'d': weekday, 's': startMin, 'e': endMin};
  factory StudySlot.fromJson(Map m) =>
      StudySlot((m['d'] as num).toInt(), (m['s'] as num).toInt(), (m['e'] as num).toInt());
}

/// Everything the user can configure. Stored natively (so the foreground
/// service can read it without Flutter) as one JSON blob.
class LifeConfig {
  final String lang; // 'hi' (Hinglish) | 'en'
  final bool engineOn;
  final bool iconSwitching;
  // Per-sensor toggles. Mic is OFF by default and only ever reads loudness.
  final Map<String, bool> sensors;
  final int incognitoUntilMs; // 0 = off
  final String overrideMode; // '' = auto
  final int overrideUntilMs;
  // Driving
  final List<String> blockDriving;
  final int drivingSpeedKmh;
  // Study
  final List<String> blockStudy;
  final List<StudySlot> studySlots;
  final int pomodoroMin;
  // Sleep
  final int sleepStartMin; // e.g. 23*60
  final int sleepEndMin; // e.g. 6*60+30
  // Home
  final double? homeLat;
  final double? homeLng;
  final int homeRadiusM;
  final String homeSsid;
  final String familyName;
  final String familyPhone; // with country code, digits only
  final String homeChannel; // 'whatsapp' | 'sms'
  final List<String> homeReminders;
  final bool onboarded;

  const LifeConfig({
    this.lang = 'hi',
    this.engineOn = true,
    this.iconSwitching = true,
    this.sensors = defaultSensors,
    this.incognitoUntilMs = 0,
    this.overrideMode = '',
    this.overrideUntilMs = 0,
    this.blockDriving = const ['com.instagram.android', 'com.google.android.youtube'],
    this.drivingSpeedKmh = 20,
    this.blockStudy = const ['com.instagram.android', 'com.google.android.youtube', 'com.snapchat.android'],
    this.studySlots = const [],
    this.pomodoroMin = 25,
    this.sleepStartMin = 23 * 60,
    this.sleepEndMin = 6 * 60 + 30,
    this.homeLat,
    this.homeLng,
    this.homeRadiusM = 150,
    this.homeSsid = '',
    this.familyName = 'Mummy',
    this.familyPhone = '',
    this.homeChannel = 'whatsapp',
    this.homeReminders = const ['Geyser band kiya?', 'Gate lock kiya?'],
    this.onboarded = false,
  });

  static const defaultSensors = <String, bool>{
    'location': true,
    'activity': true,
    'wifi': true,
    'motion': true,
    'light': true,
    'usage': true,
    'calendar': true,
    'mic': false,
  };

  bool sensor(String k) => sensors[k] ?? defaultSensors[k] ?? false;
  bool get hasHome => homeLat != null && homeLng != null || homeSsid.isNotEmpty;
  bool incognitoAt(int nowMs) => incognitoUntilMs > nowMs;
  LifeMode? overrideAt(int nowMs) =>
      overrideMode.isNotEmpty && (overrideUntilMs == 0 || overrideUntilMs > nowMs)
          ? LifeModeX.parse(overrideMode)
          : null;

  Map<String, dynamic> toJson() => {
        'lang': lang,
        'engineOn': engineOn,
        'iconSwitching': iconSwitching,
        'sensors': sensors,
        'incognitoUntilMs': incognitoUntilMs,
        'overrideMode': overrideMode,
        'overrideUntilMs': overrideUntilMs,
        'blockDriving': blockDriving,
        'drivingSpeedKmh': drivingSpeedKmh,
        'blockStudy': blockStudy,
        'studySlots': [for (final s in studySlots) s.toJson()],
        'pomodoroMin': pomodoroMin,
        'sleepStartMin': sleepStartMin,
        'sleepEndMin': sleepEndMin,
        'homeLat': homeLat,
        'homeLng': homeLng,
        'homeRadiusM': homeRadiusM,
        'homeSsid': homeSsid,
        'familyName': familyName,
        'familyPhone': familyPhone,
        'homeChannel': homeChannel,
        'homeReminders': homeReminders,
        'onboarded': onboarded,
      };

  factory LifeConfig.fromJson(Map? j) {
    if (j == null) return const LifeConfig();
    const d = LifeConfig();
    List<String> strs(Object? v, List<String> def) =>
        v is List ? [for (final x in v) x.toString()] : def;
    int i(Object? v, int def) => v is num ? v.toInt() : def;
    double? dbl(Object? v) => v is num ? v.toDouble() : null;
    final sens = Map<String, bool>.from(defaultSensors);
    if (j['sensors'] is Map) {
      (j['sensors'] as Map).forEach((k, v) => sens[k.toString()] = v == true);
    }
    return LifeConfig(
      lang: j['lang'] == 'en' ? 'en' : 'hi',
      engineOn: j['engineOn'] != false,
      iconSwitching: j['iconSwitching'] != false,
      sensors: sens,
      incognitoUntilMs: i(j['incognitoUntilMs'], 0),
      overrideMode: (j['overrideMode'] ?? '').toString(),
      overrideUntilMs: i(j['overrideUntilMs'], 0),
      blockDriving: strs(j['blockDriving'], d.blockDriving),
      drivingSpeedKmh: i(j['drivingSpeedKmh'], d.drivingSpeedKmh),
      blockStudy: strs(j['blockStudy'], d.blockStudy),
      studySlots: j['studySlots'] is List
          ? [for (final s in j['studySlots'] as List) if (s is Map) StudySlot.fromJson(s)]
          : const [],
      pomodoroMin: i(j['pomodoroMin'], d.pomodoroMin),
      sleepStartMin: i(j['sleepStartMin'], d.sleepStartMin),
      sleepEndMin: i(j['sleepEndMin'], d.sleepEndMin),
      homeLat: dbl(j['homeLat']),
      homeLng: dbl(j['homeLng']),
      homeRadiusM: i(j['homeRadiusM'], d.homeRadiusM),
      homeSsid: (j['homeSsid'] ?? '').toString(),
      familyName: (j['familyName'] ?? d.familyName).toString(),
      familyPhone: (j['familyPhone'] ?? '').toString(),
      homeChannel: j['homeChannel'] == 'sms' ? 'sms' : 'whatsapp',
      homeReminders: strs(j['homeReminders'], d.homeReminders),
      onboarded: j['onboarded'] == true,
    );
  }

  LifeConfig copyWith(Map<String, dynamic> changes) =>
      LifeConfig.fromJson({...toJson(), ...changes});
}

class CalEvent {
  final String title;
  final int beginMs;
  final int endMs;
  const CalEvent(this.title, this.beginMs, this.endMs);
  factory CalEvent.fromJson(Map m) => CalEvent((m['title'] ?? '').toString(),
      (m['beginMs'] as num?)?.toInt() ?? 0, (m['endMs'] as num?)?.toInt() ?? 0);
}

/// One reading of the phone's context, built by the native foreground
/// service every ~20 s. Unknown values are null.
class ContextSnapshot {
  final int nowMs;
  final double? speedKmh; // GPS speed
  final int fastSamples; // consecutive GPS samples above driving speed
  final int slowForSec; // how long speed has been < 8 km/h
  final String activity; // IN_VEHICLE, ON_BICYCLE, WALKING, RUNNING, STILL, ''
  final int activitySinceMs;
  final bool? insideHome; // geofence state
  final double? distanceHomeM;
  final String wifiSsid;
  final bool screenOn;
  final int screenOffForSec;
  final int screenOnForSec;
  final int stationaryForSec; // accelerometer still for
  final double? lux;
  final double? noiseDb;
  final int batteryPct;
  final bool charging;
  final List<CalEvent> calendarNow;
  final List<CalEvent> calendarTomorrow;
  final int? nextAlarmMs;
  final int appSwitches10m;
  final int nightScreenMin; // screen-on minutes since 23:00 (or sleep start)
  final String foregroundApp;
  final bool pomodoroRunning;
  final LifeMode currentMode;
  final int currentModeSinceMs;

  const ContextSnapshot({
    required this.nowMs,
    this.speedKmh,
    this.fastSamples = 0,
    this.slowForSec = 0,
    this.activity = '',
    this.activitySinceMs = 0,
    this.insideHome,
    this.distanceHomeM,
    this.wifiSsid = '',
    this.screenOn = true,
    this.screenOffForSec = 0,
    this.screenOnForSec = 0,
    this.stationaryForSec = 0,
    this.lux,
    this.noiseDb,
    this.batteryPct = 100,
    this.charging = false,
    this.calendarNow = const [],
    this.calendarTomorrow = const [],
    this.nextAlarmMs,
    this.appSwitches10m = 0,
    this.nightScreenMin = 0,
    this.foregroundApp = '',
    this.pomodoroRunning = false,
    this.currentMode = LifeMode.normal,
    this.currentModeSinceMs = 0,
  });

  DateTime get now => DateTime.fromMillisecondsSinceEpoch(nowMs);

  factory ContextSnapshot.fromJson(Map j) {
    double? d(Object? v) => v is num && v >= 0 ? v.toDouble() : null;
    int i(Object? v, [int def = 0]) => v is num ? v.toInt() : def;
    List<CalEvent> cal(Object? v) =>
        v is List ? [for (final e in v) if (e is Map) CalEvent.fromJson(e)] : const [];
    return ContextSnapshot(
      nowMs: i(j['nowMs'], DateTime.now().millisecondsSinceEpoch),
      speedKmh: d(j['speedKmh']),
      fastSamples: i(j['fastSamples']),
      slowForSec: i(j['slowForSec']),
      activity: (j['activity'] ?? '').toString(),
      activitySinceMs: i(j['activitySinceMs']),
      insideHome: j['insideHome'] is bool ? j['insideHome'] as bool : null,
      distanceHomeM: d(j['distanceHomeM']),
      wifiSsid: (j['wifiSsid'] ?? '').toString().replaceAll('"', ''),
      screenOn: j['screenOn'] != false,
      screenOffForSec: i(j['screenOffForSec']),
      screenOnForSec: i(j['screenOnForSec']),
      stationaryForSec: i(j['stationaryForSec']),
      lux: d(j['lux']),
      noiseDb: d(j['noiseDb']),
      batteryPct: i(j['batteryPct'], 100),
      charging: j['charging'] == true,
      calendarNow: cal(j['calendarNow']),
      calendarTomorrow: cal(j['calendarTomorrow']),
      nextAlarmMs: j['nextAlarmMs'] is num && (j['nextAlarmMs'] as num) > 0
          ? (j['nextAlarmMs'] as num).toInt()
          : null,
      appSwitches10m: i(j['appSwitches10m']),
      nightScreenMin: i(j['nightScreenMin']),
      foregroundApp: (j['foregroundApp'] ?? '').toString(),
      pomodoroRunning: j['pomodoroRunning'] == true,
      currentMode: LifeModeX.parse(j['currentMode']?.toString()),
      currentModeSinceMs: i(j['currentModeSinceMs']),
    );
  }
}

class ModeDecision {
  final LifeMode mode;
  final String reason; // the "why" line, e.g. "IN_VEHICLE + 32 km/h"
  final bool manual;
  const ModeDecision(this.mode, this.reason, {this.manual = false});
  @override
  String toString() => 'ModeDecision($mode, $reason${manual ? ', manual' : ''})';
}

class Suggestion {
  final String id; // rule id
  final String title;
  final String body;
  final String action; // native action key: battery_saver_share, sleep_now, …
  final bool critical;
  const Suggestion(this.id, this.title, this.body, {this.action = '', this.critical = false});
  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'body': body, 'action': action, 'critical': critical};
}
