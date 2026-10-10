import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/github_models.dart';
import '../../state/providers.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Lists the run's artifacts. Download goes through GitHub's API (with the
/// token), then the user picks where to save via the Android save dialog.
class ArtifactsPage extends ConsumerStatefulWidget {
  const ArtifactsPage({super.key, required this.runId, required this.repoFullName});

  final int runId;
  final String repoFullName;

  @override
  ConsumerState<ArtifactsPage> createState() => _ArtifactsPageState();
}

class _ArtifactsPageState extends ConsumerState<ArtifactsPage> {
  List<ArtifactInfo>? _items;
  AppFailure? _failure;
  bool _loading = true;
  int? _downloadingId;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (String, String)? get _parts {
    final p = widget.repoFullName.split('/');
    return p.length == 2 ? (p[0], p[1]) : null;
  }

  Future<void> _load() async {
    final parts = _parts;
    if (parts == null || widget.runId < 0) {
      setState(() {
        _loading = false;
        _failure = const AppFailure(FailureKind.validation);
      });
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final list = await ref.read(githubRepositoryProvider).artifacts(
            owner: parts.$1,
            repo: parts.$2,
            runId: widget.runId,
          );
      if (mounted) setState(() => _items = list);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _failure = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(ArtifactInfo a) async {
    final s = context.s;
    final parts = _parts;
    if (parts == null) return;
    if (a.expired) {
      showAppSnack(context, s.t('artifacts_expired'));
      return;
    }
    if (a.sizeInBytes > AppConfig.maxArtifactBytes) {
      showAppSnack(context, s.t('artifacts_too_large', {'max': formatBytes(AppConfig.maxArtifactBytes)}));
      return;
    }
    setState(() {
      _downloadingId = a.id;
      _progress = 0;
    });
    File? temp;
    try {
      final dir = await getTemporaryDirectory();
      temp = File('${dir.path}/winpilot_${a.id}_${DateTime.now().millisecondsSinceEpoch}.zip');
      await ref.read(githubRepositoryProvider).downloadArtifact(
            owner: parts.$1,
            repo: parts.$2,
            artifact: a,
            savePath: temp.path,
            onProgress: (received, total) {
              if (!mounted || total <= 0) return;
              setState(() => _progress = received / total);
            },
          );
      final bytes = await temp.readAsBytes();
      final target = await FilePicker.platform.saveFile(
        dialogTitle: s.t('artifacts_save_title'),
        fileName: '${a.name}.zip',
        type: FileType.any,
        bytes: bytes,
      );
      if (mounted) {
        showAppSnack(context, target == null ? s.t('artifacts_cancelled') : s.t('artifacts_saved'));
      }
    } on AppFailure catch (e) {
      if (mounted) showAppSnack(context, s.t(e.titleKey));
    } catch (_) {
      if (mounted) showAppSnack(context, s.t('err_storage_title'));
    } finally {
      if (temp != null && await temp.exists()) {
        await temp.delete();
      }
      if (mounted) {
        setState(() {
          _downloadingId = null;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('artifacts_title')),
        actions: [
          IconButton(
            tooltip: s.t('refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _items == null
          ? const LoadingPlaceholder()
          : _failure != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorPanel(failure: _failure!, onRetry: _load),
                )
              : (_items ?? const []).isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: s.t('artifacts_empty'),
                          body: s.t('artifacts_empty_body'),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        GlassCard(
                          glow: AppColors.violet,
                          child: Text(s.t('artifacts_note'),
                              style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
                        ),
                        const SizedBox(height: 12),
                        for (final a in _items!)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Icon(Icons.archive_rounded, color: AppColors.cyan),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(a.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                    ),
                                    if (a.expired) StatusChip(label: s.t('artifacts_expired_chip'), color: AppColors.warning),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${formatBytes(a.sizeInBytes)} · ${s.t('artifacts_expires')}: ${formatDateTime(a.expiresAt)}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                                  ),
                                  const SizedBox(height: 10),
                                  if (_downloadingId == a.id) ...[
                                    LinearProgressIndicator(value: _progress),
                                    const SizedBox(height: 4),
                                    Text(s.t('artifacts_downloading'), style: theme.textTheme.labelSmall),
                                  ] else
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: GradientButton(
                                        label: s.t('artifacts_download'),
                                        icon: Icons.download_rounded,
                                        onPressed: _downloadingId != null || a.expired ? null : () => _download(a),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}
