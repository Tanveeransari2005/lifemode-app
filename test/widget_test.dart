import 'package:flutter_test/flutter_test.dart';
import 'package:lifemode/background.dart';
import 'package:lifemode/core/models.dart';
import 'package:lifemode/data/db.dart';
import 'package:lifemode/main.dart';
import 'package:lifemode/platform/native_bridge.dart';
import 'package:lifemode/state/app_state.dart';

void main() {
  testWidgets('dashboard shows live mode, why-line and manual override chips', (tester) async {
    final bridge = FakeBridge(
        live: const LiveStatus(mode: LifeMode.driving, reason: 'IN_VEHICLE + 32 km/h', serviceRunning: true));
    final s = AppState(bridge, MemoryLifeStore(), clock: () => DateTime(2026, 11, 9, 16, 30));
    await s.init();
    await tester.pumpWidget(LifeModeApp(state: s, animate: false));
    await tester.pump();
    expect(find.text('Driving'), findsWidgets);
    expect(find.textContaining('IN_VEHICLE + 32 km/h'), findsOneWidget);
    await tester.tap(find.text('Padhai').first);
    await tester.pump();
    expect(bridge.config.overrideMode, 'study');
    await tester.tap(find.text('Auto'));
    await tester.pump();
    expect(bridge.config.overrideMode, '');
  });

  testWidgets('language toggle switches to English', (tester) async {
    final bridge = FakeBridge(live: const LiveStatus(mode: LifeMode.home, reason: 'wifi', serviceRunning: true));
    final s = AppState(bridge, MemoryLifeStore(), clock: () => DateTime(2026, 11, 9, 19));
    await s.init();
    await tester.pumpWidget(LifeModeApp(state: s, animate: false));
    await tester.pump();
    expect(find.text('Ghar'), findsWidgets);
    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(bridge.config.lang, 'en');
    expect(find.text('Home'), findsWidgets);
  });

  test('background tick logs mode changes and suggestions, not in incognito', () async {
    final store = MemoryLifeStore();
    final now = DateTime(2026, 11, 9, 14).millisecondsSinceEpoch;
    final r = await handleTick({
      'config': const LifeConfig(homeSsid: 'Ansari_Home').toJson(),
      'snapshot': {'nowMs': now, 'activity': 'IN_VEHICLE', 'speedKmh': 40, 'batteryPct': 12, 'currentMode': 'normal'},
    }, store: store);
    expect(r['mode'], 'driving');
    expect(r['changed'], isTrue);
    expect((r['suggestion'] as Map)['id'], 'battery_low_out');
    expect(store.events.single.mode, LifeMode.driving);
    expect(store.sugg, hasLength(1));

    final inc = await handleTick({
      'config': LifeConfig(incognitoUntilMs: now + 3600000).toJson(),
      'snapshot': {'nowMs': now, 'activity': 'IN_VEHICLE', 'currentMode': 'driving'},
    }, store: store);
    expect(inc['mode'], 'normal');
    expect(store.events, hasLength(1), reason: 'incognito never logs');
  });
}
