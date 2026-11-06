// LifeMode Lite (v1.0.1): guards against re-adding the permissions that make
// Google Play Protect's enhanced fraud protection block sideloaded installs.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemode/core/brain.dart';
import 'package:lifemode/core/i18n.dart';
import 'package:lifemode/core/models.dart';
import 'package:lifemode/data/db.dart';
import 'package:lifemode/platform/native_bridge.dart';
import 'package:lifemode/state/app_state.dart';
import 'package:lifemode/ui/screens/onboarding_screen.dart';
import 'package:lifemode/ui/screens/settings_screen.dart';
import 'package:lifemode/ui/theme.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('manifest has no NotificationListener or AccessibilityService', () {
    expect(manifest, isNot(contains('BIND_NOTIFICATION_LISTENER_SERVICE')));
    expect(manifest, isNot(contains('BIND_ACCESSIBILITY_SERVICE')));
    expect(manifest, isNot(contains('NotificationListenerService')));
    expect(manifest, isNot(contains('android.accessibilityservice')));
  });

  test('risky permissions are only present as tools:node="remove"', () {
    const risky = [
      'READ_SMS', 'RECEIVE_SMS', 'SEND_SMS', 'READ_CALL_LOG', 'READ_PHONE_STATE',
      'QUERY_ALL_PACKAGES', 'REQUEST_INSTALL_PACKAGES',
    ];
    final lines = manifest.split('\n');
    for (final p in risky) {
      for (final l in lines.where((l) => l.contains('android.permission.$p"'))) {
        expect(l, contains('tools:node="remove"'), reason: '$p must not be requested');
      }
    }
  });

  test('onboarding no longer asks for notification access or accessibility', () {
    final keys = permissionList.map((p) => p.key).toList();
    expect(keys, isNot(contains('listener')));
    expect(keys, isNot(contains('accessibility')));
    expect(permissionList.firstWhere((p) => p.key == 'overlay').optional, isTrue);
  });

  test('config drops auto-reply but still reads a v1.0 config', () {
    final json = const LifeConfig().toJson();
    expect(json.containsKey('autoReply'), isFalse);
    expect(json.containsKey('autoReplyText'), isFalse);
    final old = LifeConfig.fromJson({...json, 'autoReply': true, 'autoReplyText': 'Drive kar rahi hoon'});
    expect(old.familyName, const LifeConfig().familyName);
  });

  test('driving notification does not promise an auto-reply', () {
    final r = Brain.tick(
        ContextSnapshot(nowMs: DateTime(2026, 11, 9, 16).millisecondsSinceEpoch, activity: 'IN_VEHICLE', speedKmh: 40),
        const LifeConfig());
    expect(r.decision.mode, LifeMode.driving);
    expect(r.body.toLowerCase(), isNot(contains('auto-reply')));
    expect(const T('hi').modeTagline(LifeMode.driving).toLowerCase(), isNot(contains('auto-reply')));
  });

  testWidgets('settings shows the Lite auto-reply note', (tester) async {
    final s = AppState(FakeBridge(config: const LifeConfig(onboarded: true)), MemoryLifeStore(),
        clock: () => DateTime(2026, 11, 9, 13));
    await s.init();
    await tester.pumpWidget(AppScope(state: s, child: MaterialApp(theme: buildTheme(), home: const SettingsScreen())));
    await tester.pump();
    expect(find.text(T.liteNoAutoReply), findsOneWidget);
  });
}
