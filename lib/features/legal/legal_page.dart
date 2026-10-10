import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../ui/widgets/brand_widgets.dart';

/// Privacy, terms and operational limits. Text lives in app_strings.dart.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.type});

  /// One of: privacy, terms, limits.
  final String type;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final known = const {'privacy', 'terms', 'limits'}.contains(type);
    final titleKey = known ? (type == 'limits' ? 'limits_title' : 'legal_${type}_title') : 'legal_privacy_title';
    final bodyKey = known ? (type == 'limits' ? 'limits_body' : 'legal_${type}_body') : 'legal_privacy_body';
    return Scaffold(
      appBar: AppBar(title: Text(s.t(titleKey))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          GlassCard(
            child: SelectableText(
              s.t(bodyKey),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            s.t('legal_updated', {'date': '2026-10-10'}),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
