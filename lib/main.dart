import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'background.dart' as bg;
import 'data/db.dart';
import 'platform/native_bridge.dart';
import 'state/app_state.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/theme.dart';

/// Entry point for the headless engine started by ContextService (Kotlin).
@pragma('vm:entry-point')
void backgroundMain() => bg.backgroundMain();

/// v1.0.2: the UI must open no matter what. runApp() happens first (no awaits before
/// it), every init step is guarded with a timeout inside [AppState.init], and every
/// uncaught Dart error is written to the on-device crash log shown in Settings.
void main() {
  final bridge = NativeBridge();
  void report(Object e, StackTrace? st) {
    try {
      bridge.logError('$e\n${st ?? ''}').catchError((_) {});
    } catch (_) {}
  }

  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      report(d.exception, d.stack);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      report(e, st);
      return true;
    };
    ErrorWidget.builder = (d) => const _Oops();
    final state = AppState(bridge, DeferredLifeStore(SqlLifeStore.open));
    runApp(LifeModeApp(state: state));
    state.init().catchError((Object e, StackTrace st) => report(e, st));
  }, report);
}

class LifeModeApp extends StatelessWidget {
  const LifeModeApp({super.key, required this.state, this.animate = true});
  final AppState state;
  final bool animate;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'LifeMode',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: Builder(
            builder: (ctx) {
              final s = AppScope.of(ctx);
              if (!s.ready) return const _Splash();
              return s.config.onboarded ? HomeScreen(animate: animate) : OnboardingScreen(animate: animate);
            },
          ),
        ),
      );
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
}

/// Replaces Flutter's grey/red error box in release builds.
class _Oops extends StatelessWidget {
  const _Oops();
  @override
  Widget build(BuildContext context) => const Material(
        color: Colors.transparent,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Kuch gadbad hui. Settings → Crash log dekho.\nSomething went wrong. See Settings → Crash log.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF8A8A9A))),
          ),
        ),
      );
}
