import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/home_theme/home_theme_bloc.dart';
import 'package:frontend/bloc/home_theme/home_theme_event.dart';
import 'package:frontend/bloc/home_theme/home_theme_state.dart';
import 'package:frontend/widgets/theme_toggle.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

/// Waits for the bloc to finish loading/saving and settle on [mode].
Future<HomeThemeState> _settled(HomeThemeBloc bloc, ThemeMode mode) =>
    bloc.stream.firstWhere((s) => !s.isLoading && s.mode == mode);

void main() {
  group('HomeThemeBloc', () {
    test('defaults to dark when nothing is saved yet', () async {
      await _prefs();
      final bloc = HomeThemeBloc();
      expect(bloc.state.isLoading, isTrue); // still loading on the first frame
      expect((await _settled(bloc, ThemeMode.dark)).mode, ThemeMode.dark);
      await bloc.close();
    });

    test('loads the saved mode on startup', () async {
      await _prefs({'theme_mode': 'ThemeMode.light'});
      final bloc = HomeThemeBloc();
      expect((await _settled(bloc, ThemeMode.light)).mode, ThemeMode.light);
      await bloc.close();
    });

    test('toggle flips dark <-> light', () async {
      await _prefs({'theme_mode': 'ThemeMode.dark'});
      final bloc = HomeThemeBloc();
      await _settled(bloc, ThemeMode.dark);

      bloc.add(const ToggleHomeThemeEvent());
      await _settled(bloc, ThemeMode.light);

      bloc.add(const ToggleHomeThemeEvent());
      await _settled(bloc, ThemeMode.dark);
      await bloc.close();
    });

    test('the choice is persisted, and a fresh bloc (app restart) picks it up', () async {
      final prefs = await _prefs({'theme_mode': 'ThemeMode.dark'});
      final bloc = HomeThemeBloc();
      await _settled(bloc, ThemeMode.dark);

      bloc.add(const ToggleHomeThemeEvent());
      await _settled(bloc, ThemeMode.light);
      expect(prefs.getString('theme_mode'), 'ThemeMode.light');
      await bloc.close();

      final restarted = HomeThemeBloc();
      expect((await _settled(restarted, ThemeMode.light)).mode, ThemeMode.light);
      await restarted.close();
    });
  });

  testWidgets('the toggle button flips the global theme; MaterialApp rebuilds only when the mode changes',
      (tester) async {
    // Real async work (plugin storage) must run outside the widget test's fake clock.
    await tester.runAsync(() => _prefs({'theme_mode': 'ThemeMode.light'}));
    final bloc = HomeThemeBloc();
    var appBuilds = 0;

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: BlocBuilder<HomeThemeBloc, HomeThemeState>(
          buildWhen: (previous, current) => previous.mode != current.mode,
          builder: (context, state) {
            appBuilds++;
            return MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: state.mode,
              home: const Scaffold(body: Center(child: ThemeToggleButton())),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle(); // the saved mode finishes loading (dark -> light)

    Brightness brightness() => Theme.of(tester.element(find.byType(ThemeToggleButton))).brightness;
    expect(brightness(), Brightness.light);
    final baseline = appBuilds;

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    // The bloc emits an "isLoading" state too, but buildWhen filters it out:
    // exactly one rebuild for the one real mode change.
    expect(appBuilds, baseline + 1);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    expect(appBuilds, baseline + 2);

    await tester.runAsync(bloc.close);
  });
}
