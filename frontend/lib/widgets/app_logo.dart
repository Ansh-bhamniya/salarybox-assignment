import 'package:flutter/material.dart';

/// The "Hey!" wordmark, shown as supplied. Give it a [height]; the width follows.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 36});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/images/logo.png', height: height, semanticLabel: 'Hey!');
  }
}
