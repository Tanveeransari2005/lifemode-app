// Proactive rule engine (on-device). Turns context into at most ONE small
// suggestion, rate-limited:
//   * max 1 suggestion per 30 min (critical ones may skip the gap)
//   * none during Sleep or Driving except critical
//   * every rule also has its own cooldown
import 'context_engine.dart';
import 'models.dart';

class RuleHistory {
  final int lastAnyMs;
  final Map<String, int> lastByRule;
  const RuleHistory({this.lastAnyMs = 0, this.lastByRule = const {}});
}

class RuleEngine {
  static const gapMs = 30 * 60 * 1000;
  static const cooldownMin = {
    'late_night_scroll': 60,
    'app_switching': 90,
    'battery_low_out': 120,
    'unusual_routine': 1440,
    'no_alarm': 1440,
  };

  static Suggestion? evaluate({
    required ContextSnapshot c,
    required ModeDecision d,
    required LifeConfig cfg,
    RuleHistory history = const RuleHistory(),
    int? usualHomeArrivalMin,
  }) {
    if (cfg.incognitoAt(c.nowMs)) return null;
    String l(String hi, String en) => cfg.lang == 'en' ? en : hi;
    final now = c.now;
    final mod = now.hour * 60 + now.minute;
    final candidates = <Suggestion>[];

    // 1. Battery <= 15% outside home (critical).
    if (c.batteryPct <= 15 && !c.charging && d.mode != LifeMode.home) {
      candidates.add(Suggestion(
        'battery_low_out',
        l('Battery ${c.batteryPct}% aur aap bahar ho', 'Battery ${c.batteryPct}% and you are out'),
        l('Power-saving on + location share karun?', 'Turn on power saving and share location?'),
        action: 'battery_saver_share',
        critical: true,
      ));
    }

    // 2. No alarm but an early event tomorrow (critical, evening/night only).
    if (ContextEngine.inWindow(mod, 20 * 60, 2 * 60) && c.calendarTomorrow.isNotEmpty) {
      final first = c.calendarTomorrow.reduce((a, b) => a.beginMs <= b.beginMs ? a : b);
      final t = DateTime.fromMillisecondsSinceEpoch(first.beginMs);
      final early = t.hour < 11;
      final alarmOk = c.nextAlarmMs != null && c.nextAlarmMs! < first.beginMs;
      if (early && !alarmOk) {
        final hhmm = '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
        candidates.add(Suggestion(
          'no_alarm',
          l('Kal $hhmm: ${first.title}', 'Tomorrow $hhmm: ${first.title}'),
          l('Alarm set nahi hai. Abhi laga dein?', 'No alarm is set. Set one now?'),
          action: 'set_alarm',
          critical: true,
        ));
      }
    }

    // 3. Late-night scrolling.
    final night = ContextEngine.inWindow(mod, cfg.sleepStartMin, cfg.sleepEndMin);
    if (night && c.screenOn && c.nightScreenMin >= 20 && d.mode != LifeMode.sleep) {
      candidates.add(Suggestion(
        'late_night_scroll',
        l('Ab so jao', 'Time to sleep'),
        l('${c.nightScreenMin} min se scroll chal raha hai. Sleep mode on karun?',
            "You've been scrolling for ${c.nightScreenMin} min. Turn on Sleep mode?"),
        action: 'sleep_now',
      ));
    }

    // 4. Excessive app switching.
    if (c.appSwitches10m >= 25 && d.mode != LifeMode.driving) {
      candidates.add(Suggestion(
        'app_switching',
        l('Bahut app switching ho rahi hai', 'Lots of app switching'),
        l('10 min me ${c.appSwitches10m} baar. 25 min focus try karein?',
            '${c.appSwitches10m} switches in 10 min. Try a 25 min focus?'),
        action: 'start_focus',
      ));
    }

    // 5. Unusual routine: much later than the usual home arrival.
    if (usualHomeArrivalMin != null &&
        d.mode != LifeMode.home &&
        d.mode != LifeMode.driving &&
        mod >= usualHomeArrivalMin + 120 &&
        mod < 24 * 60 &&
        cfg.hasHome) {
      candidates.add(Suggestion(
        'unusual_routine',
        l('Aaj ghar aane me late?', 'Running late today?'),
        l('Aap usually ${_hm(usualHomeArrivalMin)} tak ghar hoti ho. ${cfg.familyName} ko update bhejein?',
            'You are usually home by ${_hm(usualHomeArrivalMin)}. Update ${cfg.familyName}?'),
        action: 'send_late_msg',
      ));
    }

    for (final s in candidates) {
      final last = history.lastByRule[s.id] ?? 0;
      if (c.nowMs - last < (cooldownMin[s.id] ?? 60) * 60000) continue;
      final quietMode = d.mode == LifeMode.sleep || d.mode == LifeMode.driving;
      if (quietMode && !s.critical) continue;
      if (!s.critical && c.nowMs - history.lastAnyMs < gapMs) continue;
      return s;
    }
    return null;
  }

  static String _hm(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';

  /// Median of the first afternoon/evening Home arrival per day (minutes from
  /// midnight). Needs 3+ days so one odd day isn't "usual".
  static int? usualHomeArrival(List<int> arrivalMinutes) {
    final xs = arrivalMinutes.where((m) => m >= 15 * 60).toList()..sort();
    if (xs.length < 3) return null;
    return xs[xs.length ~/ 2];
  }
}

class FocusMath {
  /// Focus % for a day: share of Study-mode time NOT spent in blocked apps.
  static int percent(int studySec, int distractedSec) {
    if (studySec <= 0) return 0;
    final p = 100 * (1 - distractedSec.clamp(0, studySec) / studySec);
    return p.round();
  }
}
