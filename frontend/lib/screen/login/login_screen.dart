import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/content_width.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/theme_toggle.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../bloc/auth/auth_state.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/app_icons.dart';
import 'package:go_router/go_router.dart';
import '../../utils/routes.dart';
import '../../config/env.dart';
import '../../widgets/app_back_button.dart';

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
    context.read<AuthCubit>().login(username: _usernameController.text.trim(), password: _passwordController.text);
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
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.onboarding);
            }
          },
        ),
        leadingWidth: AppBackButton.leadingWidth,
        // Theme switch, so it is reachable before logging in.
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: BlocListener<AuthCubit, AuthState>(
          listenWhen: (previous, current) => current.errorMessage != null,
          listener: (context, state) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.l, AppSpacing.gutter, AppSpacing.xxl),
            child: ContentWidth(
              maxWidth: 400,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppLogo(height: 40),
                    const SizedBox(height: AppSpacing.section),
                    Text('Welcome back!', style: AppTheme.display(context, size: 32)),
                    const SizedBox(height: AppSpacing.s),
                    Text('Log in with the details your admin gave you.', style: muted),
                    const SizedBox(height: AppSpacing.section),
                    TextFormField(
                      controller: _usernameController,
                      focusNode: _usernameFocus,
                      decoration: const InputDecoration(
                        labelText: 'Username or employee ID',
                        prefixIcon: Icon(AppIcons.person),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Enter your username or employee ID' : null,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(AppIcons.lock),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                          icon: Icon(_obscurePassword ? AppIcons.visible : AppIcons.hidden),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (value) => (value == null || value.isEmpty) ? 'Enter your password' : null,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    BlocBuilder<AuthCubit, AuthState>(
                      builder: (context, state) {
                        final loading = state.status == AuthStatus.authenticating;
                        return PrimaryButton(label: 'Log in', loading: loading, onPressed: loading ? null : _submit);
                      },
                    ),
                    const SizedBox(height: AppSpacing.section),
                    Text('Just trying it out?', style: muted),
                    const SizedBox(height: AppSpacing.s),
                    Wrap(
                      spacing: AppSpacing.s,
                      children: [
                        _DemoChip(icon: AppIcons.adminAccess, label: 'Admin login', onPressed: _fillAdmin),
                        _DemoChip(icon: AppIcons.idBadge, label: 'Staff password', onPressed: _fillStaffPassword),
                      ],
                    ),
                    if (Env.livenessDebug) ...[
                      const SizedBox(height: AppSpacing.s),
                      TextButton.icon(
                        onPressed: () => context.push(Routes.livenessDebug),
                        icon: const Icon(AppIcons.face),
                        label: const Text('Liveness debug'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A demo-login shortcut: a see-through green pill with dark green text.
class _DemoChip extends StatelessWidget {
  const _DemoChip({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
      label: Text(label),
      labelStyle: TextStyle(color: scheme.onPrimaryContainer),
      backgroundColor: scheme.primary.withValues(alpha: 0.12),
      side: BorderSide.none,
      onPressed: onPressed,
    );
  }
}
