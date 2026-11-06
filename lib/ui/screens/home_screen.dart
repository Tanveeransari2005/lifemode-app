import 'package:flutter/material.dart';

import '../../core/brain.dart';
import '../../core/i18n.dart';
import '../../core/icon_schedule.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/cards.dart';
import '../widgets/mascot.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.animate = true});
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.t;
    final now = s.clock();
    final variant = IconSchedule.variantAt(now);
    final live = s.live;
    final cfg = s.config;

    final actions = <Widget>[
      if (live.mode == LifeMode.driving)
        ActionPill(t.s('Google Maps', 'Google Maps'), Icons.map_rounded, s.bridge.openMaps),
      if (live.mode == LifeMode.study)
        live.pomodoroEndMs > now.millisecondsSinceEpoch
            ? ActionPill(t.s('Timer roko', 'Stop timer'), Icons.stop_circle_rounded, s.bridge.stopPomodoro)
            : ActionPill(t.s('${cfg.pomodoroMin} min focus', '${cfg.pomodoroMin} min focus'), Icons.timer_rounded,
                () => s.bridge.startPomodoro(cfg.pomodoroMin)),
      if (live.mode == LifeMode.home)
        ActionPill(t.s('${cfg.familyName} ko batao', 'Tell ${cfg.familyName}'), Icons.send_rounded,
            () => s.bridge.openWhatsAppOrSms(cfg.familyPhone, Brain.homeMessage(cfg), cfg.homeChannel)),
      if (live.mode == LifeMode.sleep)
        ActionPill(t.s('Main jaag rahi hoon', "I'm awake"), Icons.wb_sunny_rounded, () => s.setOverride(LifeMode.normal, minutes: 60)),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await s.bridge.tickNow();
          await s.refreshTimeline();
        },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _Header(variant: variant, animate: animate)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
            sliver: SliverList.list(children: [
              const SizedBox(height: 16),
              ModeCard(
                  t: t,
                  mode: live.mode,
                  reason: s.incognito ? t.s('Incognito on: context ruka hua', 'Incognito on: context paused') : live.reason,
                  manual: live.manual,
                  running: live.serviceRunning,
                  onOverride: (m) => s.setOverride(m),
                  actions: actions,
              ),
              const SizedBox(height: 14),
              FocusCard(
                t: t,
                studySec: live.focusStudySec,
                distractedSec: live.focusDistractedSec,
                pomodoroEndMs: live.pomodoroEndMs,
                nowMs: now.millisecondsSinceEpoch,
              ),
              SectionTitle(t.timeline),
              TimelineCard(t: t, segments: s.today, now: now),
              SectionTitle(t.quickToggles),
              _QuickToggles(),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.variant, required this.animate});
  final IconVariant variant;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.t;
    final dark = variant == IconVariant.night || variant == IconVariant.evening;
    final fg = dark ? Colors.white : LM.ink;
    final greet = switch (variant) {
      IconVariant.morning => t.s('Good morning, Tanveer', 'Good morning, Tanveer'),
      IconVariant.afternoon => t.s('Namaste, Tanveer', 'Hi, Tanveer'),
      IconVariant.evening => t.s('Good evening, Tanveer', 'Good evening, Tanveer'),
      IconVariant.night => t.s('Shubh ratri, Tanveer', 'Good night, Tanveer'),
    };
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: skyFor(variant), begin: Alignment.topCenter, end: Alignment.bottomCenter),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 12, 8, 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        AnimatedMascot(variant: variant, size: 70, animate: animate),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('LifeMode', style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.w700, height: 1.1)),
              ),
              _LangToggle(dark: dark),
              IconButton(
                tooltip: t.settings,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.tune_rounded, color: fg),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ]),
            Text(greet, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13.5)),
          ]),
        ),
      ]),
    );
  }
}

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.dark});
  final bool dark;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final hi = s.config.lang != 'en';
    Widget seg(String label, bool on, String lang) => GestureDetector(
          onTap: () => s.update({'lang': lang}).then((_) => s.bridge.tickNow()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
                color: on ? (dark ? Colors.white : LM.ink) : Colors.transparent, borderRadius: BorderRadius.circular(14)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? (dark ? LM.ink : Colors.white) : (dark ? Colors.white : LM.ink))),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
          border: Border.all(color: (dark ? Colors.white : LM.ink).withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('HI', hi, 'hi'), seg('EN', !hi, 'en')]),
    );
  }
}

class _QuickToggles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.t;
    final cfg = s.config;
    final inc = s.incognito;
    String incLabel() {
      final until = DateTime.fromMillisecondsSinceEpoch(cfg.incognitoUntilMs);
      return t.s('${until.hour}:${until.minute.toString().padLeft(2, '0')} tak', 'until ${until.hour}:${until.minute.toString().padLeft(2, '0')}');
    }

    return Card(
      child: Column(children: [
        SwitchListTile(
          secondary: const Icon(Icons.sensors_rounded),
          title: Text(t.s('LifeMode engine', 'LifeMode engine')),
          subtitle: Text(cfg.engineOn
              ? t.s('Background me context dekh raha hai', 'Reading context in the background')
              : t.s('Band hai', 'Off')),
          value: cfg.engineOn,
          onChanged: s.setEngine,
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        ListTile(
          leading: Icon(inc ? Icons.visibility_off_rounded : Icons.visibility_outlined),
          title: Text(t.incognito),
          subtitle: Text(inc
              ? t.s('On (${incLabel()}). Kuch record nahi ho raha.', 'On (${incLabel()}). Nothing is recorded.')
              : t.s('Kuch der ke liye context sensing pause karein', 'Pause context sensing for a while')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            if (inc) ActionChip(label: Text(t.s('Band karo', 'Turn off')), onPressed: () => s.setIncognito(null)),
            ActionChip(label: const Text('1h'), onPressed: () => s.setIncognito(const Duration(hours: 1))),
            ActionChip(label: const Text('4h'), onPressed: () => s.setIncognito(const Duration(hours: 4))),
            ActionChip(label: Text(t.s('Kal subah tak', 'Until tomorrow')), onPressed: () => s.setIncognito(Duration.zero)),
          ]),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline_rounded),
          title: Text(t.s('Driving auto-reply', 'Driving auto-reply')),
          subtitle: Text(T.liteNoAutoReply),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        SwitchListTile(
          secondary: const Icon(Icons.wb_twilight_rounded),
          title: Text(t.s('Time ke saath icon badle', 'Icon changes with time of day')),
          subtitle: Text(t.s('06:00 / 12:00 / 17:00 / 20:00', '06:00 / 12:00 / 17:00 / 20:00')),
          value: cfg.iconSwitching,
          onChanged: (v) => s.update({'iconSwitching': v}).then((_) => s.bridge.setIconSwitching(v)),
        ),
      ]),
    );
  }
}
