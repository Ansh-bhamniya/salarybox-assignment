import 'package:flutter/material.dart';
import 'package:frontend/app.dart';
import 'package:frontend/config/di/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/utils/helpers/onboarding_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Warm up SharedPreferences so the saved light/dark choice (read by
  // HomeThemeBloc on startup) resolves immediately, and load whether the
  // first-run intro has been seen (the router checks it synchronously).
  await SharedPreferences.getInstance();
  await OnboardingHelper.load();
  setupServiceLocator();
  runApp(const MyApp());
}
