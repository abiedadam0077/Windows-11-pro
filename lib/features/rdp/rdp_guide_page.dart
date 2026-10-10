import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../state/providers.dart';
import '../../state/session_state.dart';
import '../../state/settings_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Connection guide: Tailscale IP, a real TCP probe to port 3389, and an
/// RDP client launcher. Success of the workflow alone does not mean RDP works.
class RdpGuidePage extends ConsumerStatefulWidget {
  const RdpGuidePage({super.key});

  @override
  ConsumerState<RdpGuidePage> createState() => _RdpGuidePageState();
}

class _RdpGuidePageState extends ConsumerState<RdpGuidePage> {
  final _ipCtrl = TextEditingController();
  RdpProbeState _probe = RdpProbeState.idle;
  String? _checkedIp;

  @override
  void initState() {
    super.initState();
    final fromSession = ref.read(sessionProvider).snapshot?.diagnostics.tailscaleIp;
    if (fromSession != null) _ipCtrl.text = fromSession;
    _ipCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final ip = _ipCtrl.text.trim();
    final s = context.s;
    if (!Validators.isTailscaleIpv4(ip)) {
      showAppSnack(context, s.t('rdp_ip_invalid'));
      return;
    }
    setState(() {
      _probe = RdpProbeState.checking;
      _checkedIp = ip;
    });
    final ok = await ref.read(rdpServiceProvider).probe(ip);
    if (!mounted) return;
    setState(() => _probe = ok ? RdpProbeState.reachable : RdpProbeState.unreachable);
  }

  Future<void> _open() async {
    final s = context.s;
    final ip = _ipCtrl.text.trim();
    final user = ref.read(settingsProvider).windowsUser;
    final uri = ref.read(rdpServiceProvider).rdpUri(ip, username: user);
    if (uri == null) {
      showAppSnack(context, s.t('rdp_no_client'));
      return;
    }
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      showAppSnack(context, s.t('rdp_no_client'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final ip = _ipCtrl.text.trim();
    final ipValid = Validators.isTailscaleIpv4(ip);
    final user = ref.watch(settingsProvider.select((st) => st.windowsUser));

    return Scaffold(
      appBar: AppBar(title: Text(s.t('rdp_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          GlassCard(
            glow: AppColors.warning,
            child: Text(s.t('rdp_disclaimer'), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          ),
          SectionTitle(s.t('rdp_steps_title')),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 1; i <= 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text('$i. ${s.t('rdp_step_$i')}', style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                  ),
              ],
            ),
          ),
          SectionTitle(s.t('rdp_connection_title')),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _ipCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: s.t('rdp_ip_label'),
                    helperText: s.t('rdp_ip_helper'),
                    errorText: ip.isNotEmpty && !ipValid ? s.t('rdp_ip_invalid') : null,
                    prefixIcon: const Icon(Icons.lan_rounded),
                    suffixIcon: IconButton(
                      tooltip: s.t('copy'),
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: ip.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: ip));
                              if (context.mounted) showAppSnack(context, s.t('copied'));
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                InfoRow(label: s.t('rdp_user_label'), value: user.isEmpty ? '—' : user),
                InfoRow(label: s.t('rdp_port_label'), value: '${AppConfig.rdpPort}'),
                const SizedBox(height: 12),
                _probeResult(s, theme),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  OutlinedButton.icon(
                    onPressed: !ipValid || _probe == RdpProbeState.checking ? null : _check,
                    icon: const Icon(Icons.network_check_rounded),
                    label: Text(s.t('rdp_check_action')),
                  ),
                  GradientButton(
                    label: s.t('rdp_open_action'),
                    icon: Icons.desktop_windows_rounded,
                    onPressed: ipValid && _probe == RdpProbeState.reachable ? _open : null,
                  ),
                ]),
                const SizedBox(height: 8),
                Text(s.t('rdp_open_hint'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          SectionTitle(s.t('rdp_client_title')),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('rdp_client_body'), style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => openExternal(context, Uri.parse(AppConfig.rdpClientStoreUrl)),
                  icon: const Icon(Icons.shop_rounded),
                  label: Text(s.t('rdp_client_store')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(s.t('limits_title')),
          GlassCard(
            child: Text(s.t('limits_body'), style: theme.textTheme.bodySmall?.copyWith(height: 1.6)),
          ),
        ],
      ),
    );
  }

  Widget _probeResult(AppStrings s, ThemeData theme) {
    final (text, color) = switch (_probe) {
      RdpProbeState.idle => (s.t('rdp_probe_idle'), AppColors.textMuted),
      RdpProbeState.checking => (s.t('rdp_probe_checking', {'ip': _checkedIp ?? ''}), AppColors.cyan),
      RdpProbeState.reachable => (s.t('rdp_probe_ok', {'ip': _checkedIp ?? ''}), AppColors.success),
      RdpProbeState.unreachable => (s.t('rdp_probe_fail', {'ip': _checkedIp ?? ''}), AppColors.danger),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}
