import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';

import '../images/asset_store.dart';
import '../l10n/app_localizations.dart';
import '../notes/note.dart';
import '../notes/notes_controller.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';

/// 메모 보드: 맨 위에 빠른 메모 입력창과 검색, 아래에 날짜별로 묶인 카드. 카드를 누르면 편집 화면이 열린다.
/// 카드는 첨부 이미지를 표지로 쓰고, 동기화 상태를 칩으로 보여준다.
class NotesBoard extends StatelessWidget {
  const NotesBoard({
    super.key,
    required this.controller,
    required this.sync,
    required this.assets,
    required this.capture,
    required this.captureFocus,
    required this.search,
    required this.searchFocus,
    required this.onCapture,
    required this.onPreview,
    required this.onEdit,
    required this.onDelete,
    required this.onCreate,
  });

  final NotesController controller;
  final SyncService sync;
  final AssetStore assets;
  final TextEditingController capture;
  final FocusNode captureFocus;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ValueChanged<String> onCapture;

  /// 카드를 눌렀을 때: 스낵바로 내용 미리보기.
  final ValueChanged<String> onPreview;

  /// 편집 화면을 연다 (카드의 편집 버튼, 더블클릭).
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDelete;
  final VoidCallback onCreate;

  /// 보드의 날짜 묶음 이름. [now]를 받는 것은 테스트를 위해서다.
  static String groupOf(AppLocalizations l10n, DateTime t, DateTime now) {
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return l10n.boardToday;
    if (diff == 1) return l10n.boardYesterday;
    if (diff < 7) return l10n.boardThisWeek;
    return l10n.boardEarlier;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notes = controller.notes;
    final now = DateTime.now();

    // 날짜 묶음 (이미 최근 수정순이라 순서대로 모으면 된다).
    final groups = <String, List<Note>>{};
    for (final n in notes) {
      groups.putIfAbsent(groupOf(l10n, n.updated.toLocal(), now), () => []).add(n);
    }

    // 창을 화면 가장자리에 세로로 붙이면(좁은 창) 입력창과 검색창을 위아래로 쌓고 여백을 줄인다.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final pad = narrow ? AppSpacing.md : AppSpacing.xl;
    // 첫 화면(보드)은 입력창·안내문·카드 모두 앱 글꼴(서울남산체)로 통일한다 (사용자 요청).
    // 편집기와 미리보기 시트는 사용자 글이라 시스템 글꼴을 그대로 쓴다 (fonts.md §3).
    // hint를 따로 정하지 않으면 입력창의 style을 물려받으므로 두 입력창에 같은 스타일을 명시한다.
    final fieldStyle = theme.textTheme.bodyLarge;
    final hintStyle = theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor);
    final captureField = TextField(
      controller: capture,
      focusNode: captureFocus,
      textInputAction: TextInputAction.done,
      style: fieldStyle,
      decoration: InputDecoration(
        hintText: l10n.boardCaptureHint,
        hintStyle: hintStyle,
        prefixIcon: const Icon(Icons.add_rounded, size: 18),
      ),
      onSubmitted: (v) {
        if (v.trim().isEmpty) return;
        onCapture(v);
        // Enter 뒤에도 계속 이어서 쓸 수 있게 입력창에 포커스를 둔다.
        captureFocus.requestFocus();
      },
    );
    final searchField = TextField(
      controller: search,
      focusNode: searchFocus,
      onChanged: controller.setQuery,
      style: fieldStyle,
      decoration: InputDecoration(
        hintText: l10n.notesSearchHint,
        hintStyle: hintStyle,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: controller.query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  search.clear();
                  controller.setQuery('');
                },
              ),
      ),
    );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, narrow ? AppSpacing.md : AppSpacing.xl, pad, AppSpacing.md),
              sliver: SliverToBoxAdapter(
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          captureField,
                          const SizedBox(height: AppSpacing.sm),
                          searchField,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: captureField),
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(width: 240, child: searchField),
                        ],
                      ),
              ),
            ),
            if (notes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: controller.query.isNotEmpty
                        ? Text(l10n.notesNoResults, style: theme.textTheme.bodyMedium)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset('assets/icon/app_icon.png', width: 48, height: 48),
                              const SizedBox(height: AppSpacing.lg),
                              Text(l10n.homeEmptyTitle, style: theme.textTheme.titleMedium),
                              const SizedBox(height: AppSpacing.xs),
                              Text(l10n.boardEmptyHint, style: theme.textTheme.bodySmall),
                              const SizedBox(height: AppSpacing.lg),
                              FilledButton(onPressed: onCreate, child: Text(l10n.homeEmptyAction)),
                            ],
                          ),
                  ),
                ),
              )
            else
              for (final entry in groups.entries) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad, AppSpacing.lg, pad, AppSpacing.sm),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      entry.key,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                // 카드 높이는 내용에 맞춘다 (표지 이미지가 있으면 더 크게) — 쌓아 올리는 보드 배치.
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  // 가장 좁은 창에서는 카드를 한 줄에 하나씩, 넓으면 280 안팎 폭의 여러 열로.
                  sliver: SliverMasonryGrid.count(
                    // 카드 폭이 260 밑으로 내려가지 않게 열 수를 내림으로 구한다 (아래 칩·버튼이 들어갈 자리).
                    crossAxisCount: narrow
                        ? 1
                        : ((MediaQuery.sizeOf(context).width - 2 * pad + AppSpacing.md) / (260 + AppSpacing.md))
                              .floor()
                              .clamp(1, 8),
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childCount: entry.value.length,
                    itemBuilder: (context, i) {
                      final n = entry.value[i];
                      return NoteCard(
                        note: n,
                        assets: assets,
                        state: _stateOf(n.id),
                        onTap: () => onPreview(n.id),
                        onEdit: () => onEdit(n.id),
                        onDelete: () => onDelete(n.id),
                      );
                    },
                  ),
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  CardSync _stateOf(String id) {
    if (controller.isDirty(id)) return CardSync.unsaved;
    if (!sync.connected) return CardSync.none;
    return sync.pendingNotes.contains(id) ? CardSync.pending : CardSync.synced;
  }
}

enum CardSync { none, unsaved, pending, synced }

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.assets,
    required this.state,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Note note;
  final AssetStore assets;
  final CardSync state;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final title = note.title.isEmpty ? l10n.noteUntitled : note.title;
    final excerpt = note.excerpt(max: 140);
    final cover = note.coverAsset;
    final conflict = note.isConflictCopy;
    final dark = theme.brightness == Brightness.dark;

    // 칩: 저장 안 됨 > 충돌 사본 > 동기화 대기 > 동기화됨.
    final (String, Color)? chip = switch ((state, conflict)) {
      (CardSync.unsaved, _) => (l10n.noteUnsaved, AppColors.warning),
      (_, true) => (l10n.chipConflict, dark ? AppColors.danger : AppColors.dangerTextLight),
      (CardSync.pending, _) => (l10n.chipPending, dark ? AppColors.warning : AppColors.warningTextLight),
      (CardSync.synced, _) => (l10n.chipSynced, dark ? AppColors.success : AppColors.successTextLight),
      _ => null,
    };

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.tile),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap, // 더블클릭 처리를 두면 한 번 클릭이 300ms 늦게 반응한다 — 편집은 버튼으로
        splashFactory: NoSplash.splashFactory,
        hoverColor: scheme.primary.withValues(alpha: 0.05),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != null)
              SizedBox(
                height: 92,
                width: double.infinity,
                child: Image.file(
                  assets.file(cover),
                  fit: BoxFit.cover,
                  cacheWidth: 600,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: note.title.isEmpty ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (excerpt.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      excerpt,
                      maxLines: cover == null ? 6 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      // 칩이 길어 자리가 모자라면 줄을 바꿔서 넘치지 않게 한다.
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              DateFormat.MMMd(locale).add_Hm().format(note.updated.toLocal()),
                              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            if (chip != null) _Chip(text: chip.$1, color: chip.$2),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      _CardButton(icon: Icons.edit_outlined, tooltip: l10n.noteEditTab, onPressed: onEdit),
                      _CardButton(icon: Icons.delete_outline_rounded, tooltip: l10n.noteDelete, onPressed: onDelete),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
    ),
  );
}

/// 카드 아래의 작은 아이콘 버튼 (편집, 삭제).
class _CardButton extends StatelessWidget {
  const _CardButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
}
