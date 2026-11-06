import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../core/rule_engine.dart';
import '../../core/timeline.dart';
import '../theme.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ?trailing,
        ]),
      );
}

/// Big card for the active mode with its "why" line and override chips.
class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.t,
    required this.mode,
    required this.reason,
    required this.manual,
    required this.running,
    required this.onOverride,
    this.actions = const [],
  });
  final T t;
  final LifeMode mode;
  final String reason;
  final bool manual;
  final bool running;
  final void Function(LifeMode?) onOverride;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = LM.mode(mode);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
            colors: [c, Color.lerp(c, Colors.black, 0.25)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
            child: Icon(LM.icon(mode), color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(manual ? t.s('Manual mode', 'Manual mode') : t.s('Abhi ka mode', 'Current mode'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5)),
              Text(t.modeName(mode),
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.15)),
            ]),
          ),
          if (!running)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Text(t.s('Ruka hua', 'Paused'), style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 12),
        Text(t.modeTagline(mode), style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.insights_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${t.why}: ${reason.isEmpty ? '-' : reason}',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
        const SizedBox(height: 14),
        Wrap(runSpacing: 8, children: [
          _chip(t.auto, Icons.auto_awesome_rounded, !manual, () => onOverride(null)),
          for (final m in [LifeMode.driving, LifeMode.study, LifeMode.sleep, LifeMode.home])
            _chip(t.modeName(m), LM.icon(m), manual && mode == m, () => onOverride(m)),
        ]),
      ]),
    );
  }

  Widget _chip(String label, IconData icon, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: selected ? LM.ink : Colors.white),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500, color: selected ? LM.ink : Colors.white)),
              ]),
            ),
          ),
        ),
      );
}

class ActionPill extends StatelessWidget {
  const ActionPill(this.label, this.icon, this.onTap, {super.key});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: LM.ink),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LM.ink)),
            ]),
          ),
        ),
      );
}

class FocusCard extends StatelessWidget {
  const FocusCard({super.key, required this.t, required this.studySec, required this.distractedSec, this.pomodoroEndMs = 0, this.nowMs = 0});
  final T t;
  final int studySec;
  final int distractedSec;
  final int pomodoroEndMs;
  final int nowMs;
  @override
  Widget build(BuildContext context) {
    final pct = FocusMath.percent(studySec, distractedSec);
    final mins = studySec ~/ 60;
    final running = pomodoroEndMs > nowMs;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          SizedBox(
            width: 74,
            height: 74,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: studySec == 0 ? 0 : pct / 100,
                  strokeWidth: 8,
                  backgroundColor: const Color(0xFFE6F7F0),
                  color: LM.mode(LifeMode.study),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Text(studySec == 0 ? '-' : '$pct%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.focusScore, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                studySec == 0
                    ? t.s('Aaj abhi tak koi study session nahi.', 'No study session yet today.')
                    : t.s('$mins min padhai, ${distractedSec ~/ 60} min distraction apps me.',
                        '$mins min of study, ${distractedSec ~/ 60} min in distracting apps.'),
                style: const TextStyle(fontSize: 13, color: LM.muted, height: 1.35),
              ),
              if (running) ...[
                const SizedBox(height: 6),
                Text(t.s('Focus timer: ${((pomodoroEndMs - nowMs) / 60000).ceil()} min baaki', 'Focus timer: ${((pomodoroEndMs - nowMs) / 60000).ceil()} min left'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: LM.mode(LifeMode.study))),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class TimelineCard extends StatelessWidget {
  const TimelineCard({super.key, required this.t, required this.segments, required this.now});
  final T t;
  final List<Segment> segments;
  final DateTime now;

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _dur(Duration d) => d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';

  @override
  Widget build(BuildContext context) {
    final dayStart = DateTime(now.year, now.month, now.day);
    const dayLen = 24 * 60.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (_, box) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 22,
                width: box.maxWidth,
                child: Stack(children: [
                  Container(color: const Color(0xFFEFEDF8)),
                  for (final s in segments)
                    Positioned(
                      left: box.maxWidth * s.start.difference(dayStart).inMinutes / dayLen,
                      width: (box.maxWidth * s.duration.inMinutes / dayLen).clamp(2, box.maxWidth),
                      top: 0,
                      bottom: 0,
                      child: Container(color: LM.mode(s.mode)),
                    ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 4),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('00', style: TextStyle(fontSize: 11, color: LM.muted)),
            Text('06', style: TextStyle(fontSize: 11, color: LM.muted)),
            Text('12', style: TextStyle(fontSize: 11, color: LM.muted)),
            Text('18', style: TextStyle(fontSize: 11, color: LM.muted)),
            Text('24', style: TextStyle(fontSize: 11, color: LM.muted)),
          ]),
          const SizedBox(height: 10),
          if (segments.isEmpty)
            Text(t.s('Timeline yahan banegi jaise-jaise modes badlenge.', 'Your timeline fills in as modes change.'),
                style: const TextStyle(color: LM.muted, fontSize: 13))
          else
            for (final s in segments.reversed.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Container(
                      width: 10, height: 10, decoration: BoxDecoration(color: LM.mode(s.mode), shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  SizedBox(width: 92, child: Text('${_hm(s.start)}-${_hm(s.end)}', style: const TextStyle(fontSize: 12.5, color: LM.muted))),
                  Expanded(
                    child: Text(t.modeName(s.mode), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(_dur(s.duration), style: const TextStyle(fontSize: 12.5, color: LM.muted)),
                ]),
              ),
        ]),
      ),
    );
  }
}
