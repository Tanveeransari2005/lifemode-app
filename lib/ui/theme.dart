import 'package:flutter/material.dart';

import '../core/models.dart';

class LM {
  static const ink = Color(0xFF1E1B4B);
  static const primary = Color(0xFF6C5CE7);
  static const bg = Color(0xFFF7F5FF);
  static const card = Colors.white;
  static const muted = Color(0xFF6B6890);

  static Color mode(LifeMode m) => switch (m) {
        LifeMode.driving => const Color(0xFF3B5BDB),
        LifeMode.study => const Color(0xFF0CA678),
        LifeMode.sleep => const Color(0xFF4C3F91),
        LifeMode.home => const Color(0xFFF08C00),
        LifeMode.normal => const Color(0xFF868E96),
      };

  static IconData icon(LifeMode m) => switch (m) {
        LifeMode.driving => Icons.directions_car_rounded,
        LifeMode.study => Icons.menu_book_rounded,
        LifeMode.sleep => Icons.bedtime_rounded,
        LifeMode.home => Icons.home_rounded,
        LifeMode.normal => Icons.blur_on_rounded,
      };
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Poppins',
    colorScheme: ColorScheme.fromSeed(seedColor: LM.primary, surface: LM.bg),
    scaffoldBackgroundColor: LM.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
        backgroundColor: LM.bg, foregroundColor: LM.ink, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: LM.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: Color(0xFFE3DFFA)),
    ),
    textTheme: base.textTheme.apply(bodyColor: LM.ink, displayColor: LM.ink),
  );
}
