// Hinglish / English strings. Hinglish is the default (Latin script, so the
// Poppins font renders everything and notifications stay readable).
import 'models.dart';

class T {
  final String lang;
  const T(this.lang);
  bool get hi => lang != 'en';
  String s(String hinglish, String english) => hi ? hinglish : english;

  /// LifeMode Lite (v1.0.1) has no NotificationListener, so no driving auto-reply.
  static const liteNoAutoReply = 'Auto-reply Lite version mein nahi hai';

  String modeName(LifeMode m) => switch (m) {
        LifeMode.driving => s('Driving', 'Driving'),
        LifeMode.study => s('Padhai', 'Study'),
        LifeMode.sleep => s('Sleep', 'Sleep'),
        LifeMode.home => s('Ghar', 'Home'),
        LifeMode.normal => s('Normal', 'Normal'),
      };

  String modeTagline(LifeMode m) => switch (m) {
        LifeMode.driving => s('Road pe dhyan. Apps blocked, Maps ready.',
            'Eyes on the road. Apps blocked, Maps ready.'),
        LifeMode.study => s('Focus time. Social apps blocked, timer ready.',
            'Focus time. Social apps blocked, timer ready.'),
        LifeMode.sleep => s('Phone shaant hai. Sirf starred contacts aur repeat calls.',
            'Phone is quiet. Only starred contacts and repeat callers.'),
        LifeMode.home => s('Ghar pahunch gayi. Family ko batana hai?',
            'You are home. Want to tell family?'),
        LifeMode.normal => s('Sab normal. Main background me dekh rahi hoon.',
            'All normal. Watching context quietly in the background.'),
      };

  // Generic UI
  String get appName => 'LifeMode';
  String get why => s('Kyun', 'Why');
  String get auto => s('Auto', 'Auto');
  String get today => s('Aaj', 'Today');
  String get focusScore => s('Focus score', 'Focus score');
  String get timeline => s('Aaj ki timeline', "Today's timeline");
  String get quickToggles => s('Quick toggles', 'Quick toggles');
  String get settings => s('Settings', 'Settings');
  String get incognito => s('Incognito Context', 'Incognito Context');
  String get privacy => s('Privacy', 'Privacy');
}
