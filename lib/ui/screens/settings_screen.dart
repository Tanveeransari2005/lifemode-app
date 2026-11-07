import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../../platform/native_bridge.dart';
import '../theme.dart';
import '../widgets/cards.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.t;
    final c = s.config;
    String hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    Future<int?> pickTime(int initial) async {
      final r = await showTimePicker(context: context, initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60));
      return r == null ? null : r.hour * 60 + r.minute;
    }

    final sensorNames = <String, String>{
      'location': t.s('Location / GPS', 'Location / GPS'),
      'activity': t.s('Activity (gaadi/chalna)', 'Activity (vehicle/walking)'),
      'wifi': t.s('WiFi naam (SSID)', 'WiFi name (SSID)'),
      'motion': t.s('Motion (accelerometer)', 'Motion (accelerometer)'),
      'light': t.s('Roshni (light sensor)', 'Ambient light'),
      'usage': t.s('App usage', 'App usage'),
      'calendar': t.s('Calendar', 'Calendar'),
      'mic': t.s('Mic: sirf awaaz ka level, kabhi recording nahi', 'Mic: loudness only, never recorded'),
    };

    return Scaffold(
      appBar: AppBar(title: Text(t.settings, style: const TextStyle(fontWeight: FontWeight.w600))),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 40), children: [
        // ---------------- Driving
        SectionTitle(t.s('Driving', 'Driving')),
        Card(
          child: Column(children: [
            _AppsTile(
              title: t.s('Driving me block apps', 'Apps blocked while driving'),
              selected: c.blockDriving,
              onChanged: (l) => s.update({'blockDriving': l}),
            ),
            ListTile(
              leading: const Icon(Icons.quickreply_rounded),
              title: Text(t.s('Auto-reply', 'Auto-reply')),
              subtitle: Text(T.liteNoAutoReply),
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: Text(t.s('GPS speed se Driving', 'Driving by GPS speed')),
              subtitle: Text(t.s('${c.drivingSpeedKmh} km/h se upar (2 baar)', 'Above ${c.drivingSpeedKmh} km/h (twice)')),
              trailing: DropdownButton<int>(
                value: c.drivingSpeedKmh,
                underline: const SizedBox(),
                items: [15, 20, 25, 30].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                onChanged: (v) => s.update({'drivingSpeedKmh': v}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.phone_in_talk_rounded),
              title: Text(t.s('Calls ka speakerphone', 'Speakerphone for calls')),
              subtitle: Text(t.s('Android sirf default dialer app ko speaker on karne deta hai, isliye LifeMode yaad dilata hai.',
                  'Android only lets the default dialer turn on speaker, so LifeMode reminds you instead.')),
            ),
          ]),
        ),
        // ---------------- Study
        SectionTitle(t.s('Padhai', 'Study')),
        Card(
          child: Column(children: [
            _AppsTile(
              title: t.s('Padhai me block apps', 'Apps blocked while studying'),
              selected: c.blockStudy,
              onChanged: (l) => s.update({'blockStudy': l}),
            ),
            ListTile(
              leading: const Icon(Icons.timer_rounded),
              title: Text(t.s('Focus timer', 'Focus timer')),
              trailing: DropdownButton<int>(
                value: c.pomodoroMin,
                underline: const SizedBox(),
                items: [15, 25, 45, 50, 60].map((v) => DropdownMenuItem(value: v, child: Text('$v min'))).toList(),
                onChanged: (v) => s.update({'pomodoroMin': v}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_view_week_rounded),
              title: Text(t.s('Study schedule', 'Study schedule')),
              subtitle: Text(c.studySlots.isEmpty
                  ? t.s('Calendar me "class/exam/study" events bhi Study on karte hain.',
                      'Calendar events named class/exam/study also turn Study on.')
                  : c.studySlots.map((x) => '${_day(x.weekday)} ${hm(x.startMin)}-${hm(x.endMin)}').join(', ')),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () async {
                  final day = await showDialog<int>(
                    context: context,
                    builder: (_) => SimpleDialog(
                      title: Text(t.s('Din', 'Day')),
                      children: [
                        SimpleDialogOption(onPressed: () => Navigator.pop(context, 0), child: Text(t.s('Mon-Fri (roz)', 'Mon-Fri (weekdays)'))),
                        for (var d = 1; d <= 7; d++)
                          SimpleDialogOption(onPressed: () => Navigator.pop(context, d), child: Text(_day(d))),
                      ],
                    ),
                  );
                  if (day == null || !context.mounted) return;
                  final st = await pickTime(18 * 60);
                  if (st == null || !context.mounted) return;
                  final en = await pickTime(st + 120);
                  if (en == null || en <= st) return;
                  final days = day == 0 ? [1, 2, 3, 4, 5] : [day];
                  s.update({
                    'studySlots': [...c.studySlots.map((x) => x.toJson()), for (final d in days) StudySlot(d, st, en).toJson()]
                  });
                },
              ),
              onLongPress: () => s.update({'studySlots': []}),
            ),
          ]),
        ),
        // ---------------- Sleep
        SectionTitle(t.s('Sleep', 'Sleep')),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.bedtime_rounded),
              title: Text(t.s('Sone ka time', 'Bedtime')),
              trailing: Text(hm(c.sleepStartMin), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                final v = await pickTime(c.sleepStartMin);
                if (v != null) s.update({'sleepStartMin': v});
              },
            ),
            ListTile(
              leading: const Icon(Icons.alarm_rounded),
              title: Text(t.s('Uthne ka time', 'Wake-up time')),
              trailing: Text(hm(c.sleepEndMin), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                final v = await pickTime(c.sleepEndMin);
                if (v != null) s.update({'sleepEndMin': v});
              },
            ),
          ]),
        ),
        // ---------------- Home
        SectionTitle(t.s('Ghar', 'Home')),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.home_work_rounded),
              title: Text(t.s('Ghar ki location', 'Home location')),
              subtitle: Text(c.homeLat == null
                  ? t.s('Set nahi. Ghar par ho to "Yahi ghar hai" dabao.', 'Not set. Tap "This is home" when at home.')
                  : '${c.homeLat!.toStringAsFixed(4)}, ${c.homeLng!.toStringAsFixed(4)}  (${c.homeRadiusM} m)'),
              trailing: TextButton(
                onPressed: () async {
                  final p = await s.bridge.currentPlace();
                  if (p == null) return;
                  final ch = <String, dynamic>{};
                  if (p['lat'] != null) ch.addAll({'homeLat': p['lat'], 'homeLng': p['lng']});
                  if ((p['ssid'] ?? '').toString().isNotEmpty) ch['homeSsid'] = p['ssid'];
                  if (ch.isNotEmpty) await s.update(ch);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ch.isEmpty
                            ? t.s('Location nahi mili. Location permission/GPS check karo.', 'Could not get location. Check permission/GPS.')
                            : t.s('Ghar save ho gaya.', 'Home saved.'))));
                  }
                },
                child: Text(t.s('Yahi ghar hai', 'This is home')),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_rounded),
              title: Text(t.s('Home WiFi', 'Home WiFi')),
              subtitle: Text(c.homeSsid.isEmpty ? t.s('Set nahi', 'Not set') : c.homeSsid),
              onTap: () async {
                final v = await _editText(context, 'Home WiFi (SSID)', c.homeSsid);
                if (v != null) s.update({'homeSsid': v.trim()});
              },
            ),
            ListTile(
              leading: const Icon(Icons.family_restroom_rounded),
              title: Text(t.s('Family contact', 'Family contact')),
              subtitle: Text(c.familyPhone.isEmpty
                  ? '${c.familyName} · ${t.s('number set nahi (WhatsApp contact khud chunoge)', 'no number (you pick in WhatsApp)')}'
                  : '${c.familyName} · +${c.familyPhone}'),
              onTap: () async {
                final n = await _editText(context, t.s('Naam (jaise Mummy)', 'Name (e.g. Mum)'), c.familyName);
                if (n == null || !context.mounted) return;
                final ph = await _editText(context, t.s('WhatsApp number, country code ke saath (91...)', 'WhatsApp number with country code (91...)'),
                    c.familyPhone, number: true);
                s.update({'familyName': n.trim().isEmpty ? c.familyName : n.trim(), if (ph != null) 'familyPhone': ph.replaceAll(RegExp(r'\D'), '')});
              },
            ),
            ListTile(
              leading: const Icon(Icons.send_rounded),
              title: Text(t.s('Kaise bhejein', 'Send via')),
              subtitle: Text(t.s('Message pehle se likha khulta hai, bhejna aap dabati ho. Kabhi chupke se nahi bhejta.',
                  'The message opens prefilled; you press send. Never sent silently.')),
              trailing: DropdownButton<String>(
                value: c.homeChannel,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                  DropdownMenuItem(value: 'sms', child: Text('SMS')),
                ],
                onChanged: (v) => s.update({'homeChannel': v}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: Text(t.s('Ghar pe reminders', 'Home reminders')),
              subtitle: Text(c.homeReminders.join(' · ')),
              onTap: () async {
                final v = await _editText(context, t.s('Reminders (comma se alag)', 'Reminders (comma separated)'), c.homeReminders.join(', '));
                if (v != null) s.update({'homeReminders': v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()});
              },
            ),
          ]),
        ),
        // ---------------- Sensors / privacy
        SectionTitle(t.s('Sensors (har ek ka on/off)', 'Sensors (each on/off)')),
        Card(
          child: Column(children: [
            for (final e in sensorNames.entries)
              SwitchListTile(
                dense: true,
                title: Text(e.value, style: const TextStyle(fontSize: 14)),
                value: c.sensor(e.key),
                onChanged: (v) async {
                  await s.update({'sensors': {...c.sensors, e.key: v}});
                  if (v && e.key == 'mic' && s.perms['mic'] != true) await s.bridge.requestPermission('mic');
                },
              ),
          ]),
        ),
        SectionTitle(t.privacy),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.lock_rounded),
              title: Text(t.s('Sab data sirf is phone me', 'All data stays on this phone')),
              subtitle: Text(t.s('Koi server nahi, koi account nahi. Sirf mode timeline aur suggestions save hote hain, location history nahi.',
                  'No server, no account. Only the mode timeline and suggestions are saved, no location history.')),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_rounded),
              title: Text(t.s('Permissions', 'Permissions')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingScreen(standalone: true))),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: Text(t.s('Data export (JSON)', 'Export data (JSON)')),
              onTap: s.exportData,
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: Color(0xFFE03131)),
              title: Text(t.s('Sab data delete karo', 'Delete all data'), style: const TextStyle(color: Color(0xFFE03131))),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(t.s('Pakka delete karein?', 'Delete everything?')),
                    content: Text(t.s('Timeline aur suggestion history mit jayegi. Settings bachi rahengi.',
                        'Timeline and suggestion history will be erased. Settings stay.')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.s('Nahi', 'Cancel'))),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.s('Delete', 'Delete'))),
                    ],
                  ),
                );
                if (ok == true) await s.deleteData();
              },
            ),
          ]),
        ),
        SectionTitle(t.s('Crash log', 'Crash log')),
        CrashLogCard(state: s),
        const SizedBox(height: 18),
        Center(
          child: Text('LifeMode 1.0.2 · MIT · Tanveer Ansari', style: const TextStyle(fontSize: 12, color: LM.muted)),
        ),
      ]),
    );
  }

  static String _day(int d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1];
}

Future<String?> _editText(BuildContext context, String title, String initial, {bool number = false}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLines: number ? 1 : 3,
        minLines: 1,
        keyboardType: number ? TextInputType.phone : TextInputType.text,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('OK')),
      ],
    ),
  );
}

class _AppsTile extends StatelessWidget {
  const _AppsTile({required this.title, required this.selected, required this.onChanged});
  final String title;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListTile(
      leading: const Icon(Icons.block_rounded),
      title: Text(title),
      subtitle: Text(selected.isEmpty ? '-' : selected.map(_short).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        final apps = await s.bridge.launchableApps();
        if (!context.mounted) return;
        final r = await Navigator.push<List<String>>(
            context, MaterialPageRoute(builder: (_) => AppPickerScreen(apps: apps, selected: selected, title: title)));
        if (r != null) onChanged(r);
      },
    );
  }

  static String _short(String pkg) => switch (pkg) {
        'com.instagram.android' => 'Instagram',
        'com.google.android.youtube' => 'YouTube',
        'com.snapchat.android' => 'Snapchat',
        'com.facebook.katana' => 'Facebook',
        'com.whatsapp' => 'WhatsApp',
        _ => pkg.split('.').last,
      };
}

class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({super.key, required this.apps, required this.selected, required this.title});
  final List<AppInfo> apps;
  final List<String> selected;
  final String title;
  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  late final Set<String> sel = {...widget.selected};
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.apps.where((a) => a.label.toLowerCase().contains(q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 17)), actions: [
        TextButton(onPressed: () => Navigator.pop(context, sel.toList()), child: const Text('Save')),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', border: OutlineInputBorder()),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => CheckboxListTile(
              title: Text(list[i].label),
              subtitle: Text(list[i].package, style: const TextStyle(fontSize: 11)),
              value: sel.contains(list[i].package),
              onChanged: (v) => setState(() => v == true ? sel.add(list[i].package) : sel.remove(list[i].package)),
            ),
          ),
        ),
      ]),
    );
  }
}


/// v1.0.2: shows crashes / errors recorded on this phone (nothing is uploaded).
class CrashLogCard extends StatelessWidget {
  const CrashLogCard({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: state, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final t = state.t;
    final c = state.crash;
    if (c.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline_rounded),
          title: Text(t.s('Koi crash nahi', 'No crashes recorded')),
          subtitle: Text(t.s('Agar app band ho jaye, details yahan dikhengi.', 'If the app ever closes unexpectedly, details show here.')),
          trailing: IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: state.refreshCrash),
        ),
      );
    }
    final lines = c.log.trim().split('\n');
    final preview = lines.length > 14 ? lines.sublist(lines.length - 14).join('\n') : lines.join('\n');
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: Icon(c.fatal ? Icons.bug_report_rounded : Icons.info_outline_rounded,
              color: c.fatal ? const Color(0xFFE03131) : null),
          title: Text(c.fatal ? t.s('Pichhli baar app crash hui thi', 'The app crashed last time') : t.s('Kuch warnings', 'Some warnings')),
          subtitle: Text(t.s('Ye log sirf is phone me hai. Share karke developer ko bhejo.',
              'This log stays on this phone. Share it with the developer.')),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(color: const Color(0xFFF3F2F8), borderRadius: BorderRadius.circular(10)),
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(preview, style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, height: 1.3)),
          ),
        ),
        OverflowBar(alignment: MainAxisAlignment.end, children: [
          TextButton.icon(
              onPressed: state.shareCrashLog, icon: const Icon(Icons.ios_share_rounded), label: Text(t.s('Share', 'Share'))),
          TextButton.icon(
              onPressed: state.clearCrashLog, icon: const Icon(Icons.delete_outline_rounded), label: Text(t.s('Clear', 'Clear'))),
        ]),
      ]),
    );
  }
}
