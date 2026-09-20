import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/routes.dart';
import '../../config/theme/app_radius.dart';
import '../../config/theme/app_spacing.dart';
import '../../config/theme/app_theme.dart';
import '../../utils/helpers/onboarding_helper.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/content_width.dart';

class _Slide {
  const _Slide(this.image, this.title, this.body);

  final String image;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    'assets/images/onboarding_1.png',
    'Just look at your phone',
    "Hold it up and it finds your face. No card to carry, no PIN to remember.",
  ),
  _Slide(
    'assets/images/onboarding_2.png',
    "We make sure it's really you",
    'Your face is matched to the photo your admin enrolled, so nobody can check in for you.',
  ),
  _Slide(
    'assets/images/onboarding_3.png',
    'Marked. Go start your day.',
    'Your check-in is saved with the exact time and place. Nothing to fill in later.',
  ),
];

/// First-run intro: three swipeable pages, a page indicator and one clear
/// button. Shown once, before the login screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingHelper.markSeen();
    // Pushed (not replaced) so the login screen can slide back to the intro.
    if (mounted) context.push(Routes.login);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  // The intro's illustrations are drawn for a white page, so it always uses the
  // light theme whatever the app's theme mode is.
  static final _theme = AppTheme.light();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme,
      child: Builder(builder: _scaffold),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: ContentWidth(
          child: Column(
            children: [
              // Skip stays in the layout on the last page (just hidden) so
              // nothing below it jumps.
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.s, AppSpacing.gutter, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const AppLogo(height: 32),
                    AnimatedOpacity(
                      opacity: _isLast ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: _isLast,
                        child: TextButton(onPressed: _finish, child: const Text('Skip')),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _Page(slide: _slides[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Center(
                  child: _Dots(count: _slides.length, index: _index),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: _next, child: Text(_isLast ? 'Get started' : 'Next')),
                ),
              ),
              const SizedBox(height: AppSpacing.l),
            ],
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        children: [
          Expanded(
            child: Center(child: Image.asset(slide.image, fit: BoxFit.contain)),
          ),
          const SizedBox(height: AppSpacing.section),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: AppTheme.display(context, size: 26).copyWith(fontWeight: FontWeight.w700, height: 1.25),
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// Page indicator: the current page is a longer pill, the others small dots.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Page ${index + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: i == index ? 20 : 8,
                height: 8,
                margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                decoration: BoxDecoration(
                  color: i == index ? scheme.primary : scheme.primary.withValues(alpha: 0.18),
                  borderRadius: AppRadius.pillBorder,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
