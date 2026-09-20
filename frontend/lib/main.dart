import 'package:flutter/material.dart';
import 'package:frontend/app.dart';
import 'package:frontend/config/di/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Warm up SharedPreferences so the saved light/dark choice (read by
  // HomeThemeBloc on startup) resolves immediately.
  await SharedPreferences.getInstance();
  setupServiceLocator();
  runApp(const MyApp());
}
