import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../state/settings_state.dart';
import '../../ui/widgets/brand_widgets.dart';

/// Four-step introduction explaining OAuth, repository choice, Windows/Tailscale
/// preparation and live tracking, including the ephemeral-runner limits.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _controller = PageController();
  int _index = 0;

  static const _pages = [
    (Icons.verified_user_rounded, 'ob_1_title', 'ob_1_body'),
    (Icons.folder_special_rounded, 'ob_2_title', 'ob_2_body'),
    (Icons.settings_ethernet_rounded, 'ob_3_title', 'ob_3_body'),
    (Icons.monitor_heart_rounded, 'ob_4_title', 'ob_4_body'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(settingsProvider.notifier).completeOnboarding();
    context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final last = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: _finish, child: Text(s.t('ob_skip'))),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(44),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.violet.withValues(alpha: 0.4),
                                blurRadius: 40,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Icon(page.$1, size: 74, color: Colors.white),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          s.t(page.$2),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          s.t(page.$3),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.textMuted, height: 1.5),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.electricBlue : AppColors.outline,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: last ? s.t('ob_start') : s.t('next'),
                icon: last ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                onPressed: () {
                  if (last) {
                    _finish();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
