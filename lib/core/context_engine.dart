// The context engine: ContextSnapshot + LifeConfig -> ModeDecision.
// Pure Dart, deterministic, unit-tested (test/context_engine_test.dart).
//
// Priority: incognito > manual override > Driving > Sleep > Study > Home > Normal.
// Hysteresis keeps a mode from flickering (e.g. a red light doesn't end Driving,
// checking the time at 3 am doesn't end Sleep).
import 'dart:math' as math;

import 'models.dart';

class ContextEngine {
  static const studyWords = [
    'study', 'class', 'lecture', 'exam', 'test', 'padhai', 'tuition', 'lab',
    'college', 'school', 'revision', 'quiz', 'practical', 'assignment', 'viva',
  ];

  static ModeDecision decide(ContextSnapshot c, LifeConfig cfg) {
    if (cfg.incognitoAt(c.nowMs)) {
      return ModeDecision(LifeMode.normal, _l(cfg, 'Incognito on: context ruka hua', 'Incognito on: context paused'));
    }
    final o = cfg.overrideAt(c.nowMs);
    if (o != null) return ModeDecision(o, 'Manual', manual: true);

    return driving(c, cfg) ??
        sleep(c, cfg) ??
        study(c, cfg) ??
        home(c, cfg) ??
        ModeDecision(LifeMode.normal, _l(cfg, 'Koi khaas signal nahi', 'No strong signal'));
  }

  static String _l(LifeConfig cfg, String hi, String en) => cfg.lang == 'en' ? en : hi;

  static String _kmh(double? v) => v == null ? '' : ' + ${v.round()} km/h';

  static ModeDecision? driving(ContextSnapshot c, LifeConfig cfg) {
    final inVehicle = cfg.sensor('activity') && c.activity == 'IN_VEHICLE';
    final gps = cfg.sensor('location');
    final speed = gps ? c.speedKmh : null;
    if (inVehicle) return ModeDecision(LifeMode.driving, 'IN_VEHICLE${_kmh(speed)}');
    // GPS fallback: 2+ consecutive fast samples (filters a single GPS jump).
    if (speed != null && speed >= cfg.drivingSpeedKmh && c.fastSamples >= 2) {
      return ModeDecision(LifeMode.driving, 'GPS ${speed.round()} km/h');
    }
    // Hysteresis: already driving -> stay until slow for 3 min or activity says
    // walking/still for real.
    if (c.currentMode == LifeMode.driving) {
      final leftVehicle = c.activity == 'WALKING' || c.activity == 'ON_FOOT' || c.activity == 'RUNNING';
      if (!leftVehicle && c.slowForSec < 180) {
        return ModeDecision(LifeMode.driving, '${_l(cfg, 'Ruke hue', 'Stopped')} ${c.slowForSec}s (signal?)${_kmh(speed)}');
      }
    }
    return null;
  }

  /// Minutes-of-day window that may wrap midnight.
  static bool inWindow(int minuteOfDay, int start, int end) =>
      start <= end ? minuteOfDay >= start && minuteOfDay < end : minuteOfDay >= start || minuteOfDay < end;

  static ModeDecision? sleep(ContextSnapshot c, LifeConfig cfg) {
    final t = c.now;
    final mod = t.hour * 60 + t.minute;
    // Night window = user's sleep time, widened by 1 h before it (early sleepers).
    final inSleepWindow = inWindow(mod, cfg.sleepStartMin, cfg.sleepEndMin);
    final nightish = inWindow(mod, (cfg.sleepStartMin - 60) % 1440, cfg.sleepEndMin);
    if (!nightish) return null;

    final dark = !cfg.sensor('light') || c.lux == null || c.lux! < 15;
    final still = !cfg.sensor('motion') || c.stationaryForSec >= 300;
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    if (c.currentMode == LifeMode.sleep) {
      // Stay asleep through short screen checks; wake on 5+ min of use or
      // once the window is over and the screen is on.
      if (c.screenOn && (c.screenOnForSec >= 300 || !inSleepWindow)) return null;
      return ModeDecision(LifeMode.sleep, _l(cfg, 'Raat $hhmm + sleep chal raha', 'Night $hhmm + still asleep'));
    }
    final offMin = c.screenOffForSec ~/ 60;
    if (!c.screenOn && c.screenOffForSec >= (inSleepWindow ? 600 : 1200) && dark && still) {
      final lux = c.lux == null ? '' : ' + ${c.lux!.round()} lux';
      return ModeDecision(LifeMode.sleep, '${_l(cfg, 'Raat', 'Night')} $hhmm + screen off ${offMin}m$lux');
    }
    return null;
  }

  static bool isStudyTitle(String title) {
    final l = title.toLowerCase();
    return studyWords.any((w) => RegExp('\\b$w').hasMatch(l));
  }

  static ModeDecision? study(ContextSnapshot c, LifeConfig cfg) {
    if (c.pomodoroRunning) return ModeDecision(LifeMode.study, _l(cfg, 'Focus timer chal raha', 'Focus timer running'));
    if (cfg.sensor('calendar')) {
      for (final e in c.calendarNow) {
        if (e.beginMs <= c.nowMs && e.endMs > c.nowMs && isStudyTitle(e.title)) {
          return ModeDecision(LifeMode.study, 'Calendar: ${e.title}');
        }
      }
    }
    for (final s in cfg.studySlots) {
      if (s.covers(c.now)) return ModeDecision(LifeMode.study, _l(cfg, 'Aapka study schedule', 'Your study schedule'));
    }
    return null;
  }

  static ModeDecision? home(ContextSnapshot c, LifeConfig cfg) {
    if (cfg.sensor('wifi') && cfg.homeSsid.isNotEmpty && c.wifiSsid == cfg.homeSsid) {
      return ModeDecision(LifeMode.home, 'Home WiFi "${cfg.homeSsid}"');
    }
    if (cfg.sensor('location')) {
      if (c.insideHome == true) return ModeDecision(LifeMode.home, _l(cfg, 'Home geofence ke andar', 'Inside home geofence'));
      final d = c.distanceHomeM;
      if (d != null && d <= cfg.homeRadiusM) {
        return ModeDecision(LifeMode.home, _l(cfg, 'Ghar se ${d.round()} m', '${d.round()} m from home'));
      }
      // Hysteresis for GPS drift at the boundary.
      if (c.currentMode == LifeMode.home && d != null && d <= cfg.homeRadiusM * 1.6) {
        return ModeDecision(LifeMode.home, _l(cfg, 'Ghar ke paas (${d.round()} m)', 'Near home (${d.round()} m)'));
      }
    }
    return null;
  }

  /// Haversine distance in metres.
  static double distanceM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(a.toDouble()));
  }
}
