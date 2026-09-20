import 'package:flutter/material.dart';

/// Round floating action button with a soft shadow. It squishes on press
/// (springs back with a small bounce) and the icon turns a quarter while its
/// action runs, then turns back — e.g. while the screen it opened is showing.
///
/// A tap runs [onPressed] and nothing else: no menu, no pop-ups.
class AppFab extends StatefulWidget {
  const AppFab({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;

  @override
  State<AppFab> createState() => _AppFabState();
}

class _AppFabState extends State<AppFab> {
  static const _size = 60.0;

  bool _pressed = false;
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final shadow = dark ? Colors.black.withValues(alpha: 0.6) : scheme.primary.withValues(alpha: 0.35);

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _tap,
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: Duration(milliseconds: _pressed ? 100 : 350),
            curve: _pressed ? Curves.easeOut : Curves.elasticOut,
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: shadow, blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: AnimatedRotation(
                turns: _busy ? 0.25 : 0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                child: Icon(widget.icon, size: 28, color: scheme.onPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
