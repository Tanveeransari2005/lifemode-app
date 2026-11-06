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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LifeStore store;
  try {
    store = await SqlLifeStore.open();
  } catch (_) {
    store = MemoryLifeStore();
  }
  final state = AppState(NativeBridge(), store);
  try {
    await state.init();
  } catch (_) {}
  runApp(LifeModeApp(state: state));
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
            builder: (ctx) => AppScope.of(ctx).config.onboarded
                ? HomeScreen(animate: animate)
                : OnboardingScreen(animate: animate),
          ),
        ),
      );
}
