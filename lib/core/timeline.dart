// Turns the raw mode-change log into today's timeline segments. Pure Dart.
import 'models.dart';

class ModeEvent {
  final int startMs;
  final LifeMode mode;
  final String reason;
  final bool manual;
  const ModeEvent(this.startMs, this.mode, this.reason, {this.manual = false});

  Map<String, Object?> toRow() =>
      {'start_ms': startMs, 'mode': mode.name, 'reason': reason, 'manual': manual ? 1 : 0};
  factory ModeEvent.fromRow(Map r) => ModeEvent((r['start_ms'] as num).toInt(),
      LifeModeX.parse(r['mode']?.toString()), (r['reason'] ?? '').toString(),
      manual: r['manual'] == 1);
}

class Segment {
  final LifeMode mode;
  final DateTime start;
  final DateTime end;
  final String reason;
  const Segment(this.mode, this.start, this.end, this.reason);
  Duration get duration => end.difference(start);
}

class Timeline {
  /// Segments clipped to [dayStart, min(now, dayEnd)). [events] can include
  /// the last event before the day started so the morning isn't blank.
  static List<Segment> forDay(List<ModeEvent> events, DateTime day, DateTime now) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final limit = now.isBefore(dayEnd) ? now : dayEnd;
    final sorted = [...events]..sort((a, b) => a.startMs.compareTo(b.startMs));
    final out = <Segment>[];
    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      var s = DateTime.fromMillisecondsSinceEpoch(e.startMs);
      var en = i + 1 < sorted.length ? DateTime.fromMillisecondsSinceEpoch(sorted[i + 1].startMs) : limit;
      if (s.isBefore(dayStart)) s = dayStart;
      if (en.isAfter(limit)) en = limit;
      if (!en.isAfter(s)) continue;
      if (out.isNotEmpty && out.last.mode == e.mode) {
        final prev = out.removeLast();
        out.add(Segment(e.mode, prev.start, en, prev.reason));
      } else {
        out.add(Segment(e.mode, s, en, e.reason));
      }
    }
    return out;
  }

  static Map<LifeMode, Duration> totals(List<Segment> segs) {
    final m = <LifeMode, Duration>{};
    for (final s in segs) {
      m[s.mode] = (m[s.mode] ?? Duration.zero) + s.duration;
    }
    return m;
  }
}
