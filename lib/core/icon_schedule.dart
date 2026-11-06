// Which mascot icon the launcher shows at a given time.
// Mirrored in Kotlin (IconSwitcher.kt) — keep both in sync.
enum IconVariant { morning, afternoon, evening, night }

class IconSchedule {
  /// Boundaries in minutes from midnight: 06:00, 12:00, 17:00, 20:00.
  static const boundaries = <int, IconVariant>{
    6 * 60: IconVariant.morning,
    12 * 60: IconVariant.afternoon,
    17 * 60: IconVariant.evening,
    20 * 60: IconVariant.night,
  };

  static IconVariant variantAt(DateTime t) {
    final m = t.hour * 60 + t.minute;
    if (m >= 20 * 60 || m < 6 * 60) return IconVariant.night;
    if (m >= 17 * 60) return IconVariant.evening;
    if (m >= 12 * 60) return IconVariant.afternoon;
    return IconVariant.morning;
  }

  /// The next moment the icon should change (strictly after [t]).
  static DateTime nextSwitch(DateTime t) {
    final m = t.hour * 60 + t.minute;
    for (final b in boundaries.keys) {
      if (b > m) return DateTime(t.year, t.month, t.day, b ~/ 60, b % 60);
    }
    final tomorrow = DateTime(t.year, t.month, t.day + 1);
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 6);
  }

  static String asset(IconVariant v) => 'assets/mascot/${v.name}.png';
}
