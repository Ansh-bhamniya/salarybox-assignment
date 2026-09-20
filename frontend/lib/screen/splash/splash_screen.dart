import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/app_logo.dart';

/// First screen on every launch. Holds for [duration] while the saved session
/// restores in the background, then calls [onFinished]; the router decides
/// where to go next.
///
/// Always light, like the native launch screen it continues from, so the
/// hand-off from the OS launch screen doesn't flash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  static const duration = Duration(seconds: 3);

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen.duration, widget.onFinished);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: AppLogo(height: 67)),
    );
  }
}
