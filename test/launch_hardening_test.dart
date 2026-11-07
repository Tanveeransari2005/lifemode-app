// v1.0.2: "won't open" hardening. The UI must come up even when native init fails or hangs.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemode/core/models.dart';
import 'package:lifemode/core/timeline.dart';
import 'package:lifemode/data/db.dart';
import 'package:lifemode/main.dart';
import 'package:lifemode/platform/native_bridge.dart';
import 'package:lifemode/state/app_state.dart';
import 'package:lifemode/ui/screens/home_screen.dart';
import 'package:lifemode/ui/screens/settings_screen.dart';
import 'package:lifemode/ui/theme.dart';

class _BrokenBridge extends FakeBridge {
  _BrokenBridge({this.hang = false});
  final bool hang;
  int starts = 0;
  @override
  Future<LifeConfig> loadConfig() => hang ? Completer<LifeConfig>().future : Future.error(StateError('channel down'));
  @override
  Future<Map<String, bool>> permissions() => Future.error(StateError('perms down'));
  @override
  Future<LiveStatus> status() => Future.error(StateError('status down'));
  @override
  Stream<LiveStatus> statusStream() => throw StateError('no stream');
  @override
  Future<void> startService() async => starts++;
}

class _CountingBridge extends FakeBridge {
  _CountingBridge({super.config});
  int starts = 0;
  @override
  Future<void> startService() async => starts++;
}

void main() {
  testWidgets('UI opens on onboarding when every native init call fails', (tester) async {
    final b = _BrokenBridge();
    final s = AppState(b, MemoryLifeStore());
    await s.init();
    expect(s.ready, isTrue);
    await tester.pumpWidget(LifeModeApp(state: s, animate: false));
    await tester.pump();
    expect(find.byType(Scaffold), findsWidgets);
    expect(s.config.onboarded, isFalse);
    expect(b.starts, 0, reason: 'never start the service before onboarding');
    expect(b.errors, isNotEmpty, reason: 'failures are reported to the crash log');
  });

  test('a hanging config call times out instead of blocking launch', () async {
    final s = AppState(_BrokenBridge(hang: true), MemoryLifeStore());
    await s.init().timeout(const Duration(seconds: 20));
    expect(s.ready, isTrue);
  });

  testWidgets('splash shows until init finishes', (tester) async {
    final s = AppState(FakeBridge(), MemoryLifeStore());
    await tester.pumpWidget(LifeModeApp(state: s, animate: false));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await s.init();
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  test('safe mode after a crash: engine is not auto-started until the user retries', () async {
    final b = _CountingBridge(config: const LifeConfig(onboarded: true))
      ..crash = const CrashInfo(log: '[x] FATAL boom', safeMode: true, fatal: true);
    final s = AppState(b, MemoryLifeStore());
    await s.init();
    expect(b.starts, 0);
    expect(s.crash.safeMode, isTrue);
    await s.retryEngine();
    expect(b.starts, 1);
    expect(s.crash.safeMode, isFalse);
  });

  test('normal launch still starts the engine once onboarded', () async {
    final b = _CountingBridge(config: const LifeConfig(onboarded: true));
    await AppState(b, MemoryLifeStore()).init();
    expect(b.starts, 1);
  });

  testWidgets('Settings shows the crash log with share and clear', (tester) async {
    final b = FakeBridge(config: const LifeConfig(onboarded: true, lang: 'en'))
      ..crash = const CrashInfo(log: '[2026-11-07] FATAL thread=main\n  java.lang.SecurityException: test', fatal: true);
    final s = AppState(b, MemoryLifeStore());
    await s.init();
    await tester.pumpWidget(AppScope(state: s, child: MaterialApp(theme: buildTheme(), home: Scaffold(body: CrashLogCard(state: s)))));
    await tester.pump();
    expect(find.text('The app crashed last time'), findsOneWidget);
    expect(find.textContaining('SecurityException'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('No crashes recorded'), findsOneWidget);
  });

  test('DeferredLifeStore falls back to memory when the database cannot open', () async {
    final st = DeferredLifeStore(() => Future.error(StateError('db locked')));
    await st.logMode(ModeEvent(1, LifeMode.home, 'wifi'));
    expect(await st.eventsSince(0), hasLength(1));
  });

  test('icon switching is opt-in (default off, old configs without the key stay off)', () {
    expect(const LifeConfig().iconSwitching, isFalse);
    expect(LifeConfig.fromJson({'onboarded': true}).iconSwitching, isFalse);
    expect(LifeConfig.fromJson({'iconSwitching': true}).iconSwitching, isTrue);
  });

  group('manifest launch safety', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final aliases = RegExp(r'<activity-alias[^>]*>', dotAll: true).allMatches(m).map((x) => x.group(0)!).toList();

    test('exactly one launcher alias enabled by default, all target MainActivity', () {
      expect(aliases, hasLength(4));
      expect(aliases.where((a) => a.contains('android:enabled="true"')), hasLength(1));
      for (final a in aliases) {
        expect(a, contains('android:targetActivity=".MainActivity"'));
        expect(a, contains('android:exported="true"'));
      }
    });

    test('custom Application installs the crash log', () {
      expect(m, contains('android:name=".LifeModeApp"'));
      expect(File('android/app/src/main/kotlin/com/tanveer/lifemode/LifeModeApp.kt').existsSync(), isTrue);
    });

    test('specialUse FGS declares its subtype property and every FGS permission', () {
      expect(m, contains('android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE'));
      for (final p in ['FOREGROUND_SERVICE_LOCATION', 'FOREGROUND_SERVICE_SPECIAL_USE', 'FOREGROUND_SERVICE_DATA_SYNC']) {
        expect(m, contains('android.permission.$p'));
      }
    });

    test('no exact alarms (would need SCHEDULE_EXACT_ALARM)', () {
      final kt = Directory('android/app/src/main/kotlin').listSync(recursive: true).whereType<File>()
          .map((f) => f.readAsStringSync()).join('\n');
      expect(kt, isNot(contains('setExact')));
      expect(kt, isNot(contains('setAlarmClock')));
    });

    test('release build is not minified', () {
      final g = File('android/app/build.gradle.kts').readAsStringSync();
      expect(g, contains('isMinifyEnabled = false'));
    });
  });
}
