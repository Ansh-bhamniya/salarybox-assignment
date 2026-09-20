import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/content_width.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/theme_toggle.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../bloc/auth/auth_state.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/app_radius.dart';
import '../../config/theme/app_icons.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    context.read<AuthCubit>().login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  void _fillAdmin() {
    _usernameController.text = 'admin';
    _passwordController.text = 'admin123';
  }

  void _fillStaffPassword() {
    _passwordController.text = 'staff123';
    _usernameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: BlocListener<AuthCubit, AuthState>(
          listenWhen: (previous, current) => current.errorMessage != null,
          listener: (context, state) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          },
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                    vertical: AppSpacing.xxl,
                  ),
                  child: ContentWidth(
                    maxWidth: 400,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: AppRadius.controlBorder,
                              ),
                              child: Icon(
                                AppIcons.face,
                                size: 36,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Scales down rather than wrapping on narrow screens or
                          // with large system text.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Attendance',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: AppTheme.display(context, size: 40),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sign in to continue',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _usernameController,
                            focusNode: _usernameFocus,
                            decoration: const InputDecoration(
                              labelText: 'Username or Employee ID',
                              prefixIcon: Icon(AppIcons.person),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Enter your username or employee ID'
                                : null,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(AppIcons.lock),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _obscurePassword
                                      ? AppIcons.visible
                                      : AppIcons.hidden,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? 'Enter your password'
                                : null,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 24),
                          BlocBuilder<AuthCubit, AuthState>(
                            builder: (context, state) {
                              final loading =
                                  state.status == AuthStatus.authenticating;
                              return PrimaryButton(
                                label: 'Log in',
                                loading: loading,
                                onPressed: loading ? null : _submit,
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Demo access',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              ActionChip(
                                avatar: const Icon(
                                  AppIcons.adminAccess,
                                  size: 18,
                                ),
                                label: const Text('Fill admin login'),
                                onPressed: _fillAdmin,
                              ),
                              ActionChip(
                                avatar: const Icon(
                                  AppIcons.idBadge,
                                  size: 18,
                                ),
                                label: const Text('Staff: use password'),
                                onPressed: _fillStaffPassword,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Theme switch, so it is reachable before logging in.
              const Positioned(top: 4, right: 8, child: ThemeToggleButton()),
            ],
          ),
        ),
      ),
    );
  }
}
