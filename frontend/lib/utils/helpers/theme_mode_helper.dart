import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeHelper {
  ThemeModeHelper._();

  static const _key = "theme_mode";

  static Future<void> saveHomeThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.toString());
  }

  static Future<ThemeMode> loadHomeThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);

    switch (value) {
      case "ThemeMode.dark":
        return ThemeMode.dark;
      case "ThemeMode.light":
        return ThemeMode.light;
      default:
        return ThemeMode.dark;
    }
  }
}
