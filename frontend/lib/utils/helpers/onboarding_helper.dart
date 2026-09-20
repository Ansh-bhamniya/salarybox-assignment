import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the first-run intro has been shown, so it appears once.
class OnboardingHelper {
  OnboardingHelper._();

  static const _key = 'onboarding_seen';

  /// Loaded in `main()` so the router can check it synchronously.
  static bool seen = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    seen = prefs.getBool(_key) ?? false;
  }

  static Future<void> markSeen() async {
    seen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
