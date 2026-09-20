import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';
import '../../utils/helpers/theme_mode_helper.dart';

import './home_theme_event.dart';
import './home_theme_state.dart';

class HomeThemeBloc extends Bloc<HomeThemeEvent, HomeThemeState> {
  HomeThemeBloc()
      : super(const HomeThemeState(
          mode: ThemeMode.dark,
          isLoading: true,
        )) {
    on<LoadHomeThemeEvent>(_onLoadTheme);
    on<ToggleHomeThemeEvent>(_onToggleTheme);
    add(const LoadHomeThemeEvent());
  }

  Future<void> _onLoadTheme(
      LoadHomeThemeEvent event, Emitter<HomeThemeState> emit) async {
    final mode = await ThemeModeHelper.loadHomeThemeMode();
    emit(HomeThemeState(mode: mode, isLoading: false));
  }

  Future<void> _onToggleTheme(
      ToggleHomeThemeEvent event, Emitter<HomeThemeState> emit) async {
    final newMode =
        state.mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    emit(state.copyWith(isLoading: true));
    await ThemeModeHelper.saveHomeThemeMode(newMode);
    emit(HomeThemeState(mode: newMode, isLoading: false));
  }
}

