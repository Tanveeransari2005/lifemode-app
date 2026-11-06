import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/icon_schedule.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/mascot.dart';

/// One permission, explained in plain Hinglish/English: what it is used for.
class PermInfo {
  final String key;
  final IconData icon;
  final String Function(T) title;
  final String Function(T) why;
  final bool optional;
  const PermInfo(this.key, this.icon, this.title, this.why, {this.optional = false});
}

final permissionList = <PermInfo>[
  PermInfo('notifications', Icons.notifications_active_rounded, (t) => t.s('Notifications', 'Notifications'),
      (t) => t.s('Mode card aur chhote suggestions dikhane ke liye.', 'To show the mode card and small suggestions.')),
  PermInfo('location', Icons.location_on_rounded, (t) => t.s('Location (GPS)', 'Location (GPS)'),
      (t) => t.s('Speed se Driving pehchanne aur ghar ke paas aane par Home mode ke liye. Location phone se bahar nahi jaati.',
          'Speed for Driving and arriving home for Home mode. Location never leaves the phone.')),
  PermInfo('backgroundLocation', Icons.my_location_rounded, (t) => t.s('Location: "Allow all the time"', 'Location: "Allow all the time"'),
      (t) => t.s('Phone restart ke baad bhi home geofence chale. Settings > Permissions > Location me "All the time" chunein.',
          'Keeps the home geofence working after a restart. In Settings > Permissions > Location pick "All the time".'),
      optional: true),
  PermInfo('activity', Icons.directions_car_filled_rounded, (t) => t.s('Physical activity', 'Physical activity'),
      (t) => t.s('Google Play ka activity detection batata hai aap gaadi me ho, chal rahi ho ya ruki ho.',
          "Google Play's activity detection tells if you're in a vehicle, walking or still.")),
  PermInfo('usage', Icons.query_stats_rounded, (t) => t.s('Usage access', 'Usage access'),
      (t) => t.s('Kaunsa app samne hai (blocking ke liye), focus score aur late-night scrolling.',
          'Which app is open (for blocking), focus score and late-night scrolling.')),
  PermInfo('overlay', Icons.layers_rounded, (t) => t.s('Display over other apps', 'Display over other apps'),
      (t) => t.s('Blocked app khulne par "Driving Mode on" screen kholne ke liye. Iske bina sirf notification aayega.',
          'Lets LifeMode open the "Driving Mode on" screen when a blocked app opens. Without it you only get a notification.'),
      optional: true),
  PermInfo('dnd', Icons.do_not_disturb_on_rounded, (t) => t.s('Do Not Disturb access', 'Do Not Disturb access'),
      (t) => t.s('Sleep/Driving me DND: sirf starred contacts aur repeat callers aayenge.',
          'DND in Sleep/Driving: only starred contacts and repeat callers ring.')),
  PermInfo('calendar', Icons.event_rounded, (t) => t.s('Calendar', 'Calendar'),
      (t) => t.s('Class/exam events se Study mode aur "kal ke important kaam" reminder.',
          'Class/exam events for Study mode and the "tomorrow" reminder.'),
      optional: true),
  PermInfo('battery', Icons.battery_saver_rounded, (t) => t.s('Battery optimisation off', 'Ignore battery optimisation'),
      (t) => t.s('Kuch phones (Xiaomi, Oppo, Vivo) background apps band kar dete hain. Ye LifeMode ko chalne deta hai.',
          'Some phones (Xiaomi, Oppo, Vivo) kill background apps. This keeps LifeMode running.'),
      optional: true),
  PermInfo('mic', Icons.mic_none_rounded, (t) => t.s('Microphone (optional, OFF)', 'Microphone (optional, OFF)'),
      (t) => t.s('Sirf aawaz kitni tez hai (dB), kabhi recording nahi. Default band hai.',
          'Only how loud it is (dB), never a recording. Off by default.'),
      optional: true),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.standalone = false, this.animate = true});
  final bool standalone; // opened from Settings
  final bool animate;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed) AppScope.of(context).refreshPerms();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.t;
    final variant = IconSchedule.variantAt(s.clock());
    return Scaffold(
      appBar: widget.standalone ? AppBar(title: Text(t.s('Permissions', 'Permissions'))) : null,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
          if (!widget.standalone) ...[
            Row(children: [
              AnimatedMascot(variant: variant, size: 84, animate: widget.animate),
              const SizedBox(width: 10),
              const Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'Life', style: TextStyle(color: LM.ink)),
                  TextSpan(text: 'Mode', style: TextStyle(color: LM.primary)),
                ]), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 14),
            Text(t.s('Phone khud samjhega aap kya kar rahi ho.', 'Your phone figures out what you are doing.'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25)),
            const SizedBox(height: 8),
            Text(
                t.s('Driving, Padhai, Sleep aur Ghar: LifeMode background me context padh kar sahi mode on karta hai. Koi daily entry nahi. Sab data sirf aapke phone me.',
                    'Driving, Study, Sleep and Home: LifeMode reads context in the background and switches the right mode on. No daily entry. All data stays on your phone.'),
                style: const TextStyle(fontSize: 14.5, color: LM.muted, height: 1.45)),
            const SizedBox(height: 12),
            Row(children: [
              Text(t.s('Bhasha:', 'Language:'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              ChoiceChip(label: const Text('Hinglish'), selected: t.hi, onSelected: (_) => s.update({'lang': 'hi'})),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('English'), selected: !t.hi, onSelected: (_) => s.update({'lang': 'en'})),
            ]),
            const SizedBox(height: 18),
            Text(t.s('Permissions (har ek kyun chahiye)', 'Permissions (and why each one)'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
          ],
          for (final p in permissionList) _PermTile(p: p, granted: s.perms[p.key] == true),
          const SizedBox(height: 18),
          if (!widget.standalone)
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54), backgroundColor: LM.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: s.finishOnboarding,
              child: Text(t.s('Shuru karein', "Let's start"), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 8),
          Text(
            t.s('Koi bhi permission baad me Settings se badal sakti ho. Jo permission nahi doge, uska feature bas band rahega.',
                'You can change any permission later in Settings. Skipped permissions just turn that feature off.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: LM.muted),
          ),
        ]),
      ),
    );
  }
}

class _PermTile extends StatelessWidget {
  const _PermTile({required this.p, required this.granted});
  final PermInfo p;
  final bool granted;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFFF0EEFF), borderRadius: BorderRadius.circular(12)),
              child: Icon(p.icon, color: LM.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title(t), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(p.why(t), style: const TextStyle(fontSize: 12.5, color: LM.muted, height: 1.35)),
              ]),
            ),
            const SizedBox(width: 8),
            granted
                ? const Padding(
                    padding: EdgeInsets.only(top: 8), child: Icon(Icons.check_circle_rounded, color: Color(0xFF0CA678)))
                : TextButton(
                    onPressed: () => s.bridge.requestPermission(p.key).then((_) => s.refreshPerms()),
                    child: Text(t.s('Allow', 'Allow')),
                  ),
          ]),
        ),
      ),
    );
  }
}
