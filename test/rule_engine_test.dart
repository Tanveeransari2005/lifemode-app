import 'package:flutter_test/flutter_test.dart';
import 'package:lifemode/core/brain.dart';
import 'package:lifemode/core/icon_schedule.dart';
import 'package:lifemode/core/models.dart';
import 'package:lifemode/core/rule_engine.dart';
import 'package:lifemode/core/timeline.dart';

int at(int h, [int m = 0, int day = 9]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;
const cfg = LifeConfig(homeSsid: 'Ansari_Home');

Suggestion? run(ContextSnapshot c, {RuleHistory h = const RuleHistory(), int? usual, LifeConfig config = cfg}) {
  return Brain.tick(c, config, history: h, usualHomeArrivalMin: usual).suggestion;
}

void main() {
  group('rules', () {
    test('late night scrolling nudge', () {
      final s = run(ContextSnapshot(nowMs: at(23, 50), screenOn: true, nightScreenMin: 35));
      expect(s?.id, 'late_night_scroll');
      expect(s?.title, 'Ab so jao');
    });
    test('battery 12% outside home is critical with share action', () {
      final s = run(ContextSnapshot(nowMs: at(14), batteryPct: 12));
      expect(s?.id, 'battery_low_out');
      expect(s?.critical, isTrue);
      expect(s?.body, contains('location share karun'));
    });
    test('no battery nudge at home or while charging', () {
      expect(run(ContextSnapshot(nowMs: at(14), batteryPct: 12, wifiSsid: 'Ansari_Home')), isNull);
      expect(run(ContextSnapshot(nowMs: at(14), batteryPct: 12, charging: true)), isNull);
    });
    test('app switching', () {
      expect(run(ContextSnapshot(nowMs: at(14), appSwitches10m: 30))?.id, 'app_switching');
      expect(run(ContextSnapshot(nowMs: at(14), appSwitches10m: 10)), isNull);
    });
    test('max one per 30 min (non-critical)', () {
      final h = RuleHistory(lastAnyMs: at(13, 45));
      expect(run(ContextSnapshot(nowMs: at(14), appSwitches10m: 30), h: h), isNull);
      expect(run(ContextSnapshot(nowMs: at(14, 20), appSwitches10m: 30), h: h)?.id, 'app_switching');
    });
    test('critical skips the 30 min gap but not its own cooldown', () {
      final h = RuleHistory(lastAnyMs: at(13, 50));
      expect(run(ContextSnapshot(nowMs: at(14), batteryPct: 10), h: h)?.id, 'battery_low_out');
      final h2 = RuleHistory(lastAnyMs: at(13, 50), lastByRule: {'battery_low_out': at(13, 50)});
      expect(run(ContextSnapshot(nowMs: at(14), batteryPct: 10), h: h2), isNull);
    });
    test('nothing non-critical during sleep', () {
      final s = ContextSnapshot(nowMs: at(1), screenOn: true, screenOnForSec: 30, appSwitches10m: 40, currentMode: LifeMode.sleep);
      expect(run(s), isNull);
    });
    test('no alarm before an early event tomorrow', () {
      final s = ContextSnapshot(nowMs: at(22), calendarTomorrow: [CalEvent('Maths exam', at(9, 0, 10), at(11, 0, 10))]);
      final r = run(s);
      expect(r?.id, 'no_alarm');
      final ok = ContextSnapshot(nowMs: at(22), nextAlarmMs: at(7, 0, 10), calendarTomorrow: [CalEvent('Maths exam', at(9, 0, 10), at(11, 0, 10))]);
      expect(run(ok), isNull);
    });
    test('unusual routine', () {
      expect(run(ContextSnapshot(nowMs: at(21)), usual: 18 * 60)?.id, 'unusual_routine');
      expect(run(ContextSnapshot(nowMs: at(19)), usual: 18 * 60), isNull);
      expect(RuleEngine.usualHomeArrival([1080, 1110, 1050, 600]), 1080);
      expect(RuleEngine.usualHomeArrival([1080, 1110]), isNull);
    });
    test('incognito silences rules', () {
      final c = cfg.copyWith({'incognitoUntilMs': at(15)});
      expect(run(ContextSnapshot(nowMs: at(14), batteryPct: 5), config: c), isNull);
    });
  });

  group('brain content', () {
    test('sleep shows alarm + tomorrow tasks', () {
      final s = ContextSnapshot(nowMs: at(23, 30), screenOn: false, screenOffForSec: 900, lux: 1, stationaryForSec: 900,
          nextAlarmMs: at(6, 30, 10), calendarTomorrow: [CalEvent('DBMS viva', at(10, 0, 10), at(11, 0, 10))]);
      final r = Brain.tick(s, cfg);
      expect(r.decision.mode, LifeMode.sleep);
      expect(r.changed, isTrue);
      expect(r.lines, contains('Alarm ready: 6:30'));
      expect(r.lines.last, contains('Kal ke important kaam: 10:00 DBMS viva'));
    });
    test('home shows charger reminder under 40%', () {
      final r = Brain.tick(ContextSnapshot(nowMs: at(18), wifiSsid: 'Ansari_Home', batteryPct: 31), cfg);
      expect(r.decision.mode, LifeMode.home);
      expect(r.lines.first, contains('charger'));
      expect(r.lines, contains('Gate lock kiya?'));
    });
    test('english toggle', () {
      final r = Brain.tick(ContextSnapshot(nowMs: at(18), wifiSsid: 'Ansari_Home'), cfg.copyWith({'lang': 'en'}));
      expect(r.title, 'You are home!');
    });
  });

  group('icon schedule', () {
    test('variants at boundaries', () {
      expect(IconSchedule.variantAt(DateTime(2026, 1, 1, 5, 59)), IconVariant.night);
      expect(IconSchedule.variantAt(DateTime(2026, 1, 1, 6)), IconVariant.morning);
      expect(IconSchedule.variantAt(DateTime(2026, 1, 1, 12)), IconVariant.afternoon);
      expect(IconSchedule.variantAt(DateTime(2026, 1, 1, 17)), IconVariant.evening);
      expect(IconSchedule.variantAt(DateTime(2026, 1, 1, 20)), IconVariant.night);
    });
    test('next switch', () {
      expect(IconSchedule.nextSwitch(DateTime(2026, 1, 1, 7)), DateTime(2026, 1, 1, 12));
      expect(IconSchedule.nextSwitch(DateTime(2026, 1, 1, 21)), DateTime(2026, 1, 2, 6));
      expect(IconSchedule.nextSwitch(DateTime(2026, 12, 31, 22)), DateTime(2027, 1, 1, 6));
    });
  });

  group('timeline + focus', () {
    test('segments clipped to day and merged', () {
      final ev = [
        ModeEvent(at(22, 0, 8), LifeMode.sleep, 'night'),
        ModeEvent(at(7), LifeMode.normal, ''),
        ModeEvent(at(9), LifeMode.driving, 'IN_VEHICLE'),
        ModeEvent(at(9, 30), LifeMode.study, 'class'),
        ModeEvent(at(10), LifeMode.study, 'class 2'),
      ];
      final segs = Timeline.forDay(ev, DateTime(2026, 11, 9), DateTime(2026, 11, 9, 11));
      expect(segs.first.mode, LifeMode.sleep);
      expect(segs.first.start, DateTime(2026, 11, 9));
      expect(segs.last.mode, LifeMode.study);
      expect(segs.last.duration, const Duration(minutes: 90));
      expect(Timeline.totals(segs)[LifeMode.driving], const Duration(minutes: 30));
    });
    test('focus percent', () {
      expect(FocusMath.percent(3600, 360), 90);
      expect(FocusMath.percent(0, 0), 0);
      expect(FocusMath.percent(100, 500), 0);
    });
  });
}
