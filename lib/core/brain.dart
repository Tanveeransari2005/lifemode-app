// The "brain" glues the engines together for one tick and produces the
// localized notification content the native service shows. Pure Dart.
import 'context_engine.dart';
import 'i18n.dart';
import 'models.dart';
import 'rule_engine.dart';

class TickResult {
  final ModeDecision decision;
  final bool changed;
  final String title;
  final String body;
  final List<String> lines;
  final Suggestion? suggestion;
  const TickResult(this.decision, this.changed, this.title, this.body, this.lines, this.suggestion);

  Map<String, dynamic> toJson() => {
        'mode': decision.mode.name,
        'reason': decision.reason,
        'manual': decision.manual,
        'changed': changed,
        'title': title,
        'body': body,
        'lines': lines,
        'suggestion': suggestion?.toJson(),
      };
}

class Brain {
  static TickResult tick(ContextSnapshot c, LifeConfig cfg,
      {RuleHistory history = const RuleHistory(), int? usualHomeArrivalMin}) {
    final d = ContextEngine.decide(c, cfg);
    final changed = d.mode != c.currentMode;
    final t = T(cfg.lang);
    final lines = <String>[];
    String title, body;
    switch (d.mode) {
      case LifeMode.driving:
        title = t.s('Driving Mode on', 'Driving Mode on');
        body = t.s('Apps blocked. Maps ek tap pe.', 'Apps blocked. Maps is one tap away.');
        lines.add(t.s('Calls: speaker ya Bluetooth khud on karein (Android allow nahi karta).',
            'Calls: turn on speaker or Bluetooth yourself (Android does not allow apps to).'));
      case LifeMode.study:
        title = t.s('Padhai Mode on', 'Study Mode on');
        body = t.s('Social apps blocked. ${cfg.pomodoroMin} min ka focus timer start karein?',
            'Social apps blocked. Start a ${cfg.pomodoroMin} min focus timer?');
      case LifeMode.sleep:
        title = t.s('Sleep Mode on', 'Sleep Mode on');
        body = t.s('DND: sirf starred contacts + repeat callers.', 'DND: starred contacts + repeat callers only.');
        lines.addAll(sleepLines(c, t));
      case LifeMode.home:
        title = t.s('Ghar pahunch gayi!', 'You are home!');
        body = t.s('${cfg.familyName} ko "Main ghar pahunch gayi" bhejein?',
            'Send "${homeMessage(cfg)}" to ${cfg.familyName}?');
        lines.addAll(homeLines(c, cfg, t));
      case LifeMode.normal:
        title = t.s('LifeMode: Normal', 'LifeMode: Normal');
        body = t.modeTagline(LifeMode.normal);
    }
    final s = RuleEngine.evaluate(
        c: c, d: d, cfg: cfg, history: history, usualHomeArrivalMin: usualHomeArrivalMin);
    return TickResult(d, changed, title, body, lines, s);
  }

  static String homeMessage(LifeConfig cfg) =>
      cfg.lang == 'en' ? 'I reached home' : 'Main ghar pahunch gayi';

  static List<String> homeLines(ContextSnapshot c, LifeConfig cfg, T t) => [
        if (c.batteryPct < 40 && !c.charging)
          t.s('Battery ${c.batteryPct}%: charger laga do.', 'Battery ${c.batteryPct}%: plug in the charger.'),
        ...cfg.homeReminders.where((r) => r.trim().isNotEmpty),
      ];

  static List<String> sleepLines(ContextSnapshot c, T t) {
    final out = <String>[];
    if (c.nextAlarmMs != null) {
      final a = DateTime.fromMillisecondsSinceEpoch(c.nextAlarmMs!);
      out.add(t.s('Alarm ready: ${_hm(a)}', 'Alarm ready: ${_hm(a)}'));
    } else {
      out.add(t.s('Koi alarm set nahi hai.', 'No alarm is set.'));
    }
    if (c.calendarTomorrow.isNotEmpty) {
      final evs = [...c.calendarTomorrow]..sort((a, b) => a.beginMs.compareTo(b.beginMs));
      final items = evs.take(3).map((e) => '${_hm(DateTime.fromMillisecondsSinceEpoch(e.beginMs))} ${e.title}');
      out.add(t.s('Kal ke important kaam: ${items.join(', ')}', "Tomorrow's important things: ${items.join(', ')}"));
    }
    return out;
  }

  static String _hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}
