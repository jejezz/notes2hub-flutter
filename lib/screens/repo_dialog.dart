import 'package:flutter/material.dart';

import '../github/github_api.dart';
import '../l10n/app_localizations.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';

/// 메모 저장소를 새로 만들거나 기존 것을 골라 연결한다. 연결되면 true.
Future<bool?> showRepoDialog(BuildContext context, SyncService sync) => showDialog<bool>(
  context: context,
  builder: (_) => _RepoDialog(sync: sync),
);

class _RepoDialog extends StatefulWidget {
  const _RepoDialog({required this.sync});

  final SyncService sync;

  @override
  State<_RepoDialog> createState() => _RepoDialogState();
}

class _RepoDialogState extends State<_RepoDialog> {
  final _name = TextEditingController(text: 'notes2hub-data');
  final _filter = TextEditingController();
  List<GitHubRepo>? _repos;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repos = await widget.sync.listRepos();
      if (mounted) setState(() => _repos = repos);
    } catch (e) {
      if (mounted) setState(() => _error = AppLocalizations.of(context).repoLoadFailed('$e'));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = l10n.repoConnectFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
    final repo = await widget.sync.createRepo(_name.text.trim(), description: 'Notes2Hub notes');
    await widget.sync.connectRepo(repo);
  });

  Future<void> _pick(GitHubRepo repo) async {
    if (!repo.isPrivate) {
      final l10n = AppLocalizations.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.repoPublicConfirmTitle),
          content: Text(l10n.repoPublicConfirmBody(repo.fullName)),
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.repoConnect)),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(() => widget.sync.connectRepo(repo));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final q = _filter.text.trim().toLowerCase();
    final all = _repos ?? [];
    // Notes2Hub 표식이 붙은 저장소를 맨 위로.
    final repos = all.where((r) => q.isEmpty || r.fullName.toLowerCase().contains(q)).toList()
      ..sort((a, b) => (b.isNotesRepo ? 1 : 0) - (a.isNotesRepo ? 1 : 0));
    final suggested = all.where((r) => r.isNotesRepo).toList();
    return AlertDialog(
      title: Text(l10n.repoTitle),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (suggested.isNotEmpty) ...[
              Text(l10n.repoSuggested, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.repoSuggestedHint, style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.sm),
              for (final r in suggested)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ListTile(
                    dense: true,
                    leading: Icon(r.isPrivate ? Icons.lock_outline_rounded : Icons.public_rounded, size: 18),
                    title: Text(r.fullName),
                    trailing: FilledButton(onPressed: _busy ? null : () => _pick(r), child: Text(l10n.repoUseThis)),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(l10n.repoCreateTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    enabled: !_busy,
                    decoration: InputDecoration(labelText: l10n.repoNameLabel, isDense: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(onPressed: _busy ? null : _create, child: Text(l10n.repoCreate)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.repoExisting, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _filter,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.repoSearch,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _repos == null
                  ? Center(child: _error == null ? const CircularProgressIndicator() : const SizedBox.shrink())
                  : repos.isEmpty
                  ? Center(child: Text(l10n.repoNoMatch, style: theme.textTheme.bodySmall))
                  : ListView.builder(
                      itemCount: repos.length,
                      itemBuilder: (context, i) {
                        final r = repos[i];
                        return ListTile(
                          dense: true,
                          enabled: !_busy,
                          leading: Icon(r.isPrivate ? Icons.lock_outline_rounded : Icons.public_rounded, size: 18),
                          title: Text(r.fullName),
                          subtitle: r.description == null
                              ? null
                              : Text(r.description!, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(
                            r.isPrivate ? l10n.repoPrivate : l10n.repoPublic,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: r.isPrivate ? theme.colorScheme.onSurfaceVariant : AppColors.warningTextLight,
                            ),
                          ),
                          onTap: () => _pick(r),
                        );
                      },
                    ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(l10n.repoConnecting, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: SelectableText(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(l10n.commonClose)),
      ],
    );
  }
}
