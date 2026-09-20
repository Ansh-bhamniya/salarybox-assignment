import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/home_theme/home_theme_bloc.dart';
import '../bloc/home_theme/home_theme_event.dart';
import '../config/theme/app_icons.dart';

/// Icon button that flips light/dark. It only *dispatches* the event; the
/// icon follows the global theme, so there is no theme state kept here.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(isDark ? AppIcons.lightMode : AppIcons.darkMode),
      onPressed: () => context.read<HomeThemeBloc>().add(
            const ToggleHomeThemeEvent(),
          ),
    );
  }
}

/// A "Dark mode" row with a switch, for menus and sheets.
class ThemeSwitchTile extends StatelessWidget {
  const ThemeSwitchTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.outlineVariant)),
        child: Icon(isDark ? AppIcons.darkMode : AppIcons.lightMode, size: 20, color: scheme.onSurface),
      ),
      title: Text('Dark mode', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      trailing: Switch(
        value: isDark,
        onChanged: (_) => context.read<HomeThemeBloc>().add(
              const ToggleHomeThemeEvent(),
            ),
      ),
      onTap: () => context.read<HomeThemeBloc>().add(
            const ToggleHomeThemeEvent(),
          ),
    );
  }
}
