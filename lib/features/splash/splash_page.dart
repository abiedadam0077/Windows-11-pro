import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth_state.dart';
import '../../state/providers.dart';
import '../../state/settings_state.dart';
import '../../ui/widgets/brand_widgets.dart';

/// Brand splash. Always leaves within a bounded time, even if restoring the
/// session fails (the user is then sent to onboarding or sign-in).
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  static const _minDisplay = Duration(milliseconds: 2400);
  static const _restoreLimit = Duration(seconds: 12);
  bool _showRetry = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_boot()));
  }

  Future<void> _boot() async {
    if (!mounted) return;
    setState(() => _showRetry = false);
    final started = DateTime.now();
    try {
      await ref.read(authProvider.notifier).restore().timeout(_restoreLimit);
    } catch (_) {
      // Restoring is best-effort: offline or timed-out restores fall through.
      if (!mounted) return;
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minDisplay) await Future<void>.delayed(_minDisplay - elapsed);
    if (!mounted || _navigated) return;

    final settings = ref.read(settingsProvider);
    final auth = ref.read(authProvider).status;
    final signedIn = auth == AuthStatus.signedIn || auth == AuthStatus.expired;
    final target = !settings.onboardingDone
        ? '/onboarding'
        : signedIn
            ? '/home/dashboard'
            : '/welcome';
    _navigated = true;
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.background, Color(0xFF1B1450), Color(0xFF0B2A6B)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Spacer(),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          AppColors.violet.withValues(alpha: 0.35),
                          AppColors.electricBlue.withValues(alpha: 0.12),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                    const BrandLogo(size: 128, animate: true),
                  ],
                ),
                const SizedBox(height: 28),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOut,
                  builder: (context, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
                  ),
                  child: Column(
                    children: [
                      Text(
                        s.t('app_name'),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.t('splash_tagline'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_showRetry) ...[
                  Text(s.t('splash_error'), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _boot, child: Text(s.t('splash_retry'))),
                ] else ...[
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 12),
                  Text(s.t('splash_loading'), style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
