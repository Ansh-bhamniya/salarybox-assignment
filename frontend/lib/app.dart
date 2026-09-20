import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import './config/di/service_locator.dart';
import './config/router/app_router.dart';
import './config/theme/app_theme.dart';
import './bloc/auth/auth_cubit.dart';
import './bloc/home_theme/home_theme_bloc.dart';
import './bloc/home_theme/home_theme_state.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Created once. MaterialApp rebuilds when the theme flips; if the router
  // were built inside build(), every theme change would reset navigation.
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<AuthCubit>()),
        // The one and only theme bloc; screens use the global theme.
        BlocProvider(create: (_) => HomeThemeBloc()),
      ],
      child: BlocBuilder<HomeThemeBloc, HomeThemeState>(
        buildWhen: (previous, current) => previous.mode != current.mode,
        builder: (context, state) {
          return MaterialApp.router(
            title: 'Attendance',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.mode,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
