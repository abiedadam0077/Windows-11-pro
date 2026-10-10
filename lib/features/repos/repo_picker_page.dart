import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../models/github_models.dart';
import '../../state/providers.dart';
import '../../state/settings_state.dart';
import '../../ui/widgets/brand_widgets.dart';
import '../../ui/widgets/feedback_widgets.dart';

enum RepoFilter { all, writable, public, private }

/// Lists repositories the user can access, with search, filters and creation.
class RepoPickerPage extends ConsumerStatefulWidget {
  const RepoPickerPage({super.key});

  @override
  ConsumerState<RepoPickerPage> createState() => _RepoPickerPageState();
}

class _RepoPickerPageState extends ConsumerState<RepoPickerPage> {
  final _search = TextEditingController();
  RepoFilter _filter = RepoFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(RepoSummary r) {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty &&
        !r.fullName.toLowerCase().contains(q) &&
        !(r.description ?? '').toLowerCase().contains(q)) {
      return false;
    }
    return switch (_filter) {
      RepoFilter.all => true,
      RepoFilter.writable => r.canPush,
      RepoFilter.public => !r.isPrivate,
      RepoFilter.private => r.isPrivate,
    };
  }

  void _select(RepoSummary repo) {
    final s = context.s;
    if (!repo.canPush) {
      showAppSnack(context, s.t('repo_no_write'));
      return;
    }
    ref.read(settingsProvider.notifier).setDefaultRepo(repo.fullName);
    showAppSnack(context, s.t('repos_selected', {'repo': repo.fullName}));
    if (context.canPop()) {
      context.pop(repo.fullName);
    } else {
      context.go('/setup');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final repos = ref.watch(repositoriesProvider);
    final selected = ref.watch(settingsProvider.select((st) => st.defaultRepo));

    String filterLabel(RepoFilter f) => switch (f) {
          RepoFilter.all => s.t('repos_filter_all'),
          RepoFilter.writable => s.t('repos_filter_writable'),
          RepoFilter.public => s.t('repos_filter_public'),
          RepoFilter.private => s.t('repos_filter_private'),
        };

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('repos_title')),
        actions: [
          IconButton(
            tooltip: s.t('refresh'),
            onPressed: () => ref.invalidate(repositoriesProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: s.t('repos_create_action'),
            onPressed: () => _createDialog(context),
            icon: const Icon(Icons.add_box_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s.t('repos_search_hint'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in RepoFilter.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(filterLabel(f)),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: repos.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(
                  5,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: SkeletonBox(height: 72, radius: 18),
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorPanel(
                  failure: e is AppFailure ? e : const AppFailure(FailureKind.unknown),
                  onRetry: () => ref.invalidate(repositoriesProvider),
                ),
              ),
              data: (list) {
                final filtered = list.where(_matches).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.folder_off_rounded,
                    title: s.t('repos_empty'),
                    action: OutlinedButton.icon(
                      onPressed: () => _createDialog(context),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(s.t('repos_create_action')),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Text(s.t('repos_count', {'count': '${filtered.length}'}),
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted));
                    }
                    final repo = filtered[i - 1];
                    final isSelected = repo.fullName == selected;
                    return _RepoTile(
                      repo: repo,
                      selected: isSelected,
                      onTap: () => _select(repo),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createDialog(BuildContext context) async {
    final s = context.s;
    final name = TextEditingController();
    final desc = TextEditingController();
    var isPrivate = true;
    String? error;
    final created = await showDialog<RepoSummary>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.t('create_repo_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: s.t('create_repo_name'),
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: desc,
                  decoration: InputDecoration(labelText: s.t('create_repo_desc')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.t('create_repo_private')),
                  value: isPrivate,
                  onChanged: (v) => setD(() => isPrivate = v),
                ),
                Text(s.t('create_repo_hint'), style: Theme.of(ctx).textTheme.bodySmall),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
            FilledButton(
              onPressed: () async {
                final value = name.text.trim();
                if (!Validators.repoName.hasMatch(value)) {
                  setD(() => error = s.t('create_repo_invalid'));
                  return;
                }
                try {
                  final repo = await ref.read(githubRepositoryProvider).createRepository(
                        name: value,
                        isPrivate: isPrivate,
                        description: desc.text.trim(),
                      );
                  if (ctx.mounted) Navigator.pop(ctx, repo);
                } on AppFailure catch (e) {
                  setD(() => error = s.t(e.titleKey));
                }
              },
              child: Text(s.t('create_repo_confirm')),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    desc.dispose();
    if (created != null) {
      ref.invalidate(repositoriesProvider);
      ref.read(settingsProvider.notifier).setDefaultRepo(created.fullName);
      if (context.mounted) {
        showAppSnack(context, s.t('repos_selected', {'repo': created.fullName}));
      }
    }
  }
}

class _RepoTile extends StatelessWidget {
  const _RepoTile({required this.repo, required this.selected, required this.onTap});

  final RepoSummary repo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Opacity(
      opacity: repo.canPush ? 1 : 0.6,
      child: GlassCard(
        glow: selected ? AppColors.success : null,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(repo.isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                color: repo.isPrivate ? AppColors.violet : AppColors.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(repo.fullName,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    repo.canPush
                        ? s.t('repo_default_branch', {'branch': repo.defaultBranch})
                        : s.t('repo_no_write'),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: AppColors.success)
            else
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
