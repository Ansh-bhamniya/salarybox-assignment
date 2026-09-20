import 'package:flutter/material.dart';

class HomeThemeState {
  final ThemeMode mode;
  final bool isLoading;

  const HomeThemeState({required this.mode, required this.isLoading});

  HomeThemeState copyWith({ThemeMode? mode, bool? isLoading}) {
    return HomeThemeState(mode: mode ?? this.mode, isLoading: isLoading ?? this.isLoading);
  }
}
