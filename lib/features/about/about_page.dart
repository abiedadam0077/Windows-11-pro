import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/update_service.dart';
import '../../state/providers.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Shows the installed version and checks GitHub Releases for a newer APK.
/// The app never installs anything itself: "Download" opens the APK link and
/// Android then shows its normal install confirmation.
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  PackageInfo? _info;
  bool _checking = false;
  UpdateCheckResult? _result;
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _info = i);
    });
  }

  Future<void> _check() async {
    final info = _info ?? await PackageInfo.fromPlatform();
    setState(() {
      _checking = true;
      _failure = null;
      _result = null;
    });
    try {
      final installed = int.tryParse(info.buildNumber) ?? 0;
      final result = await ref.read(updateServiceProvider).check(installedVersionCode: installed);
      if (mounted) setState(() => _result = result);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _failure = e);
    } catch (_) {
      if (mounted) setState(() => _failure = const AppFailure(FailureKind.unknown));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppSnack(context, context.s.t('about_open_failed'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final info = _info;
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('about_title')),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home/settings')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: BrandLogo(size: 76, animate: false)),
          const SizedBox(height: 14),
          Center(
            child: Text(AppConfig.appName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              info == null ? '…' : '${s.t('about_version')} ${info.version} (${s.t('about_build')} ${info.buildNumber})',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 22),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('about_update_title'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(s.t('about_update_desc'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 14),
                GradientButton(
                  label: _checking ? s.t('about_checking') : s.t('about_check_button'),
                  icon: Icons.refresh_rounded,
                  loading: _checking,
                  onPressed: _checking ? null : _check,
                ),
                const SizedBox(height: 14),
                if (_failure != null) ErrorPanel(failure: _failure!),
                if (result != null) _resultView(context, result, info),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('about_install_title'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(s.t('about_install_desc'), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            children: [
              TextButton(onPressed: () => context.push('/legal/terms'), child: Text(s.t('terms'))),
              TextButton(onPressed: () => context.push('/legal/privacy'), child: Text(s.t('privacy'))),
              TextButton(onPressed: () => context.push('/legal/limits'), child: Text(s.t('limits_title'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultView(BuildContext context, UpdateCheckResult result, PackageInfo? info) {
    final s = context.s;
    final theme = Theme.of(context);
    final latest = result.latest;
    if (result.status == UpdateStatus.upToDate) {
      return Text(s.t('about_up_to_date'), style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.success));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${s.t('about_new_version')}: ${latest.versionName} (${latest.versionCode})',
          style: theme.textTheme.titleSmall?.copyWith(color: AppColors.cyan, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SelectableText('SHA-256: ${latest.sha256}', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(s.t('about_verify_hint'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        GradientButton(
          label: s.t('about_download_button'),
          icon: Icons.download_rounded,
          onPressed: () => _openUrl(latest.apkUrl),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(s.t('about_copy_link')),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: latest.apkUrl));
            if (context.mounted) showAppSnack(context, s.t('device_copied'));
          },
        ),
      ],
    );
  }
}
