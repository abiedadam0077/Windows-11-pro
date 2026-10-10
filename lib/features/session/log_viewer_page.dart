import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../state/providers.dart';
import '../../ui/widgets/feedback_widgets.dart';

/// Shows the redacted, most recent log lines of the run's main job.
class LogViewerPage extends ConsumerStatefulWidget {
  const LogViewerPage({super.key, required this.runId, required this.repoFullName});

  final int runId;
  final String repoFullName;

  @override
  ConsumerState<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends ConsumerState<LogViewerPage> {
  List<String>? _lines;
  AppFailure? _failure;
  bool _loading = true;
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final parts = widget.repoFullName.split('/');
    if (parts.length != 2 || widget.runId < 0) {
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
      final lines = await ref.read(githubRepositoryProvider).logLines(
            owner: parts[0],
            repo: parts[1],
            runId: widget.runId,
          );
      if (!mounted) return;
      setState(() => _lines = lines);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _failure = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final query = _filter.text.trim().toLowerCase();
    final all = _lines ?? const <String>[];
    final shown = query.isEmpty ? all : all.where((l) => l.toLowerCase().contains(query)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('logs_title')),
        actions: [
          IconButton(
            tooltip: s.t('copy'),
            onPressed: all.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: shown.join('\n')));
                    if (context.mounted) showAppSnack(context, s.t('copied'));
                  },
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: s.t('refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _filter,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.t('logs_filter_hint'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                s.t('logs_info', {'n': '${all.length}', 'max': '5000'}),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.electricBlue.withValues(alpha: 0.2)),
                ),
                child: _body(s, shown),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(s.t('logs_redacted_note'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _body(AppStrings s, List<String> shown) {
    if (_loading && _lines == null) {
      return const LoadingPlaceholder();
    }
    if (_failure != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: ErrorPanel(failure: _failure!, onRetry: _load),
      );
    }
    if (shown.isEmpty) {
      return Center(child: Text(s.t('logs_empty')));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: shown.length,
      itemBuilder: (context, i) => SelectableText(
        shown[i],
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
      ),
    );
  }
}
