// Renders real app screens to PNG for the README.
//
//   flutter test --update-goldens test/screenshots_test.dart
//
// Output: test/goldens/*.png (copied to docs/screenshots/).
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemode/core/models.dart';
import 'package:lifemode/core/timeline.dart';
import 'package:lifemode/data/db.dart';
import 'package:lifemode/main.dart';
import 'package:lifemode/platform/native_bridge.dart';
import 'package:lifemode/state/app_state.dart';
import 'package:lifemode/ui/screens/settings_screen.dart';
import 'package:lifemode/ui/theme.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Poppins', ['assets/fonts/Poppins-Regular.ttf', 'assets/fonts/Poppins-Medium.ttf', 'assets/fonts/Poppins-SemiBold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final mf = '$root/bin/cache/artifacts/material_fonts';
  await load('Roboto', ['$mf/Roboto-Regular.ttf', '$mf/Roboto-Medium.ttf', '$mf/Roboto-Bold.ttf']);
  final icons = File('$mf/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
}

DateTime day(int h, [int m = 0]) => DateTime(2026, 11, 9, h, m);

Future<AppState> _state({
  required DateTime now,
  required LiveStatus live,
  LifeConfig? config,
  Map<String, bool> perms = const {},
}) async {
  final store = MemoryLifeStore();
  final evs = <ModeEvent>[
    ModeEvent(DateTime(2026, 11, 8, 23, 20).millisecondsSinceEpoch, LifeMode.sleep, 'night'),
    ModeEvent(day(6, 40).millisecondsSinceEpoch, LifeMode.home, 'wifi'),
    ModeEvent(day(8, 5).millisecondsSinceEpoch, LifeMode.driving, 'IN_VEHICLE'),
    ModeEvent(day(8, 35).millisecondsSinceEpoch, LifeMode.study, 'class'),
    ModeEvent(day(13, 10).millisecondsSinceEpoch, LifeMode.normal, ''),
    ModeEvent(day(16, 20).millisecondsSinceEpoch, LifeMode.driving, 'IN_VEHICLE'),
    ModeEvent(day(16, 50).millisecondsSinceEpoch, LifeMode.home, 'wifi'),
    ModeEvent(day(18, 0).millisecondsSinceEpoch, LifeMode.study, 'schedule'),
    ModeEvent(day(20, 30).millisecondsSinceEpoch, LifeMode.home, 'wifi'),
    ModeEvent(day(23, 25).millisecondsSinceEpoch, LifeMode.sleep, 'night'),
  ];
  store.events.addAll(evs.where((e) => e.startMs <= now.millisecondsSinceEpoch));
  final cfg = config ??
      const LifeConfig(onboarded: true, homeLat: 25.18, homeLng: 75.83, homeSsid: 'Ansari_Home', familyPhone: '919800000000');
  final s = AppState(FakeBridge(config: cfg, live: live, perms: perms), store, clock: () => now);
  await s.init();
  return s;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  Future<void> shoot(WidgetTester tester, String name, AppState s, {Widget? page, double scroll = 0}) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(page == null
          ? LifeModeApp(state: s, animate: false)
          : AppScope(state: s, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: page)));
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 700));
    if (scroll != 0) {
      await tester.drag(find.byType(Scrollable).first, Offset(0, -scroll));
      await tester.pump(const Duration(milliseconds: 500));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('01 onboarding', (t) async {
    final s = await _state(
        now: day(7, 10),
        live: const LiveStatus(),
        config: const LifeConfig(),
        perms: const {'notifications': true, 'location': true, 'activity': true});
    await shoot(t, '01_onboarding', s);
  });

  testWidgets('02 driving', (t) async {
    final s = await _state(
        now: day(16, 32),
        live: const LiveStatus(
            mode: LifeMode.driving, reason: 'IN_VEHICLE + 32 km/h', serviceRunning: true, focusStudySec: 13200, focusDistractedSec: 1080));
    await shoot(t, '02_driving', s);
  });

  testWidgets('03 study', (t) async {
    final s = await _state(
        now: day(18, 40),
        live: LiveStatus(
            mode: LifeMode.study,
            reason: 'Calendar: DBMS revision',
            serviceRunning: true,
            focusStudySec: 15600,
            focusDistractedSec: 1100,
            pomodoroEndMs: day(18, 58).millisecondsSinceEpoch));
    await shoot(t, '03_study', s);
  });

  testWidgets('04 sleep', (t) async {
    final s = await _state(
        now: day(23, 48),
        live: const LiveStatus(
            mode: LifeMode.sleep, reason: 'Raat 23:25 + screen off 14m + 2 lux', serviceRunning: true, focusStudySec: 17400, focusDistractedSec: 1300));
    await shoot(t, '04_sleep', s);
  });

  testWidgets('05 home english', (t) async {
    final s = await _state(
        now: day(20, 36),
        live: const LiveStatus(
            mode: LifeMode.home, reason: 'Home WiFi "Ansari_Home"', serviceRunning: true, focusStudySec: 17400, focusDistractedSec: 1300),
        config: const LifeConfig(
            lang: 'en', onboarded: true, homeLat: 25.18, homeLng: 75.83, homeSsid: 'Ansari_Home', familyName: 'Mummy', familyPhone: '919800000000'));
    await shoot(t, '05_home_en', s);
  });

  testWidgets('06 quick toggles', (t) async {
    final s = await _state(
        now: day(13, 5),
        live: const LiveStatus(mode: LifeMode.normal, reason: 'Koi khaas signal nahi', serviceRunning: true, focusStudySec: 9000, focusDistractedSec: 700));
    await shoot(t, '06_toggles', s, scroll: 700);
  });

  testWidgets('07 settings', (t) async {
    final s = await _state(now: day(13, 5), live: const LiveStatus(serviceRunning: true));
    await shoot(t, '07_settings', s, page: const SettingsScreen());
  });
}
