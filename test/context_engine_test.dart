import 'package:flutter_test/flutter_test.dart';
import 'package:lifemode/core/context_engine.dart';
import 'package:lifemode/core/models.dart';

int at(int h, [int m = 0, int day = 9]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;

void main() {
  const cfg = LifeConfig(homeLat: 25.18, homeLng: 75.83, homeSsid: 'Ansari_Home', lang: 'en');

  group('driving', () {
    test('IN_VEHICLE wins and why-line shows speed', () {
      final d = ContextEngine.decide(ContextSnapshot(nowMs: at(10), activity: 'IN_VEHICLE', speedKmh: 32.4), cfg);
      expect(d.mode, LifeMode.driving);
      expect(d.reason, 'IN_VEHICLE + 32 km/h');
    });
    test('GPS fallback needs 2 fast samples', () {
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(10), speedKmh: 40, fastSamples: 1), cfg).mode, LifeMode.normal);
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(10), speedKmh: 40, fastSamples: 2), cfg).mode, LifeMode.driving);
    });
    test('red light keeps driving, 3 min stop ends it', () {
      final base = ContextSnapshot(nowMs: at(10), speedKmh: 0, currentMode: LifeMode.driving, slowForSec: 60);
      expect(ContextEngine.decide(base, cfg).mode, LifeMode.driving);
      final stopped = ContextSnapshot(nowMs: at(10), speedKmh: 0, currentMode: LifeMode.driving, slowForSec: 200);
      expect(ContextEngine.decide(stopped, cfg).mode, LifeMode.normal);
    });
    test('walking ends driving immediately', () {
      final s = ContextSnapshot(nowMs: at(10), activity: 'WALKING', currentMode: LifeMode.driving, slowForSec: 10);
      expect(ContextEngine.decide(s, cfg).mode, LifeMode.normal);
    });
    test('activity sensor off ignores IN_VEHICLE', () {
      final off = cfg.copyWith({'sensors': {...cfg.sensors, 'activity': false}});
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(10), activity: 'IN_VEHICLE'), off).mode, LifeMode.normal);
    });
  });

  group('sleep', () {
    test('night + screen off + dark + still', () {
      final s = ContextSnapshot(nowMs: at(23, 40), screenOn: false, screenOffForSec: 900, lux: 2, stationaryForSec: 900);
      final d = ContextEngine.decide(s, cfg);
      expect(d.mode, LifeMode.sleep);
      expect(d.reason, contains('screen off 15m'));
    });
    test('bright room does not sleep', () {
      final s = ContextSnapshot(nowMs: at(23, 40), screenOn: false, screenOffForSec: 900, lux: 200, stationaryForSec: 900);
      expect(ContextEngine.decide(s, cfg).mode, isNot(LifeMode.sleep));
    });
    test('daytime never sleeps', () {
      final s = ContextSnapshot(nowMs: at(15), screenOn: false, screenOffForSec: 9000, lux: 0, stationaryForSec: 9000);
      expect(ContextEngine.decide(s, cfg).mode, isNot(LifeMode.sleep));
    });
    test('quick time check at 3am keeps sleep', () {
      final s = ContextSnapshot(nowMs: at(3), screenOn: true, screenOnForSec: 40, currentMode: LifeMode.sleep);
      expect(ContextEngine.decide(s, cfg).mode, LifeMode.sleep);
    });
    test('5 min of use wakes', () {
      final s = ContextSnapshot(nowMs: at(3), screenOn: true, screenOnForSec: 400, currentMode: LifeMode.sleep);
      expect(ContextEngine.decide(s, cfg).mode, isNot(LifeMode.sleep));
    });
    test('window wrapping midnight', () {
      expect(ContextEngine.inWindow(23 * 60 + 30, 23 * 60, 390), isTrue);
      expect(ContextEngine.inWindow(200, 23 * 60, 390), isTrue);
      expect(ContextEngine.inWindow(12 * 60, 23 * 60, 390), isFalse);
    });
  });

  group('study', () {
    test('calendar class event', () {
      final s = ContextSnapshot(nowMs: at(11), calendarNow: [CalEvent('DBMS Class', at(10, 30), at(12))]);
      final d = ContextEngine.decide(s, cfg);
      expect(d.mode, LifeMode.study);
      expect(d.reason, 'Calendar: DBMS Class');
    });
    test('non-study event ignored', () {
      final s = ContextSnapshot(nowMs: at(11), calendarNow: [CalEvent('Birthday party', at(10), at(12))]);
      expect(ContextEngine.decide(s, cfg).mode, LifeMode.normal);
    });
    test('title matching', () {
      expect(ContextEngine.isStudyTitle('Maths exam prep'), isTrue);
      expect(ContextEngine.isStudyTitle('Padhai'), isTrue);
      expect(ContextEngine.isStudyTitle('Contest night'), isFalse);
    });
    test('weekly schedule slot', () {
      final c = cfg.copyWith({'studySlots': [const StudySlot(1, 18 * 60, 20 * 60).toJson()]});
      // 2026-11-09 is a Monday.
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(19)), c).mode, LifeMode.study);
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(19, 0, 10)), c).mode, LifeMode.normal);
    });
    test('study beats home', () {
      final s = ContextSnapshot(nowMs: at(19), pomodoroRunning: true, wifiSsid: 'Ansari_Home');
      expect(ContextEngine.decide(s, cfg).mode, LifeMode.study);
    });
  });

  group('home', () {
    test('home wifi', () {
      final d = ContextEngine.decide(ContextSnapshot(nowMs: at(17), wifiSsid: 'Ansari_Home'), cfg);
      expect(d.mode, LifeMode.home);
      expect(d.reason, contains('Ansari_Home'));
    });
    test('geofence distance with drift hysteresis', () {
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(17), distanceHomeM: 80), cfg).mode, LifeMode.home);
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(17), distanceHomeM: 200), cfg).mode, LifeMode.normal);
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(17), distanceHomeM: 200, currentMode: LifeMode.home), cfg).mode,
          LifeMode.home);
    });
    test('haversine', () {
      final d = ContextEngine.distanceM(25.18, 75.83, 25.19, 75.83);
      expect(d, closeTo(1112, 5));
    });
  });

  group('priority', () {
    test('manual override beats everything until it expires', () {
      final c = cfg.copyWith({'overrideMode': 'study', 'overrideUntilMs': at(12)});
      final s = ContextSnapshot(nowMs: at(11), activity: 'IN_VEHICLE');
      expect(ContextEngine.decide(s, c), isA<ModeDecision>().having((d) => d.manual, 'manual', true));
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(13), activity: 'IN_VEHICLE'), c).mode, LifeMode.driving);
    });
    test('incognito pauses detection', () {
      final c = cfg.copyWith({'incognitoUntilMs': at(12)});
      expect(ContextEngine.decide(ContextSnapshot(nowMs: at(11), activity: 'IN_VEHICLE'), c).mode, LifeMode.normal);
    });
    test('config json round trip', () {
      final c = cfg.copyWith({'familyPhone': '919876543210', 'sensors': {'mic': true}});
      final back = LifeConfig.fromJson(c.toJson());
      expect(back.familyPhone, '919876543210');
      expect(back.sensor('mic'), isTrue);
      expect(back.sensor('location'), isTrue);
      expect(const LifeConfig().sensor('mic'), isFalse, reason: 'mic is off by default');
    });
  });
}
