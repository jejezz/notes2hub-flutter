import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../images/asset_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/user_content.dart';
import 'ctrl_edit_shortcuts.dart';

/// 미리보기의 이미지: `../assets/<이름>`은 첨부 폴더에서, http(s)는 네트워크에서.
class NoteImage extends StatelessWidget {
  const NoteImage({super.key, required this.uri, required this.alt, required this.assets});

  final Uri uri;
  final String? alt;
  final AssetStore assets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget broken(Object _, StackTrace? _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined, size: 16),
        const SizedBox(width: AppSpacing.xs),
        Text(alt == null || alt!.isEmpty ? l10n.imageBroken : alt!, style: theme.textTheme.bodySmall),
      ],
    );
    final Widget image;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      image = Image.network(uri.toString(), fit: BoxFit.contain, errorBuilder: (c, e, s) => broken(e, s));
    } else if (uri.pathSegments.isNotEmpty) {
      image = Image.file(
        assets.file(uri.pathSegments.last),
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => broken(e, s),
      );
    } else {
      image = broken('', null);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720, maxHeight: 480), child: image),
    );
  }
}

/// 보드에서 카드를 눌렀을 때 아래에서 올라오는 미리보기 시트: Markdown을 렌더링해서 보여주고, 길면 본문이
/// 스크롤된다 ([닫기] [편집] 버튼은 고정). 저장하지 않은(새로 쓰거나 고친) 메모는 [onSave]를 주어 [저장] [닫기] [편집]으로 보인다. 제목 줄은 따로 두지 않는다 — 본문 첫 줄이 곧 제목이라 중복으로 보인다. 시트의 틀은 branch-dock-flutter의 시트와 같다
/// (드래그 핸들, 위쪽 모서리 AppRadius.sheet, 화면 높이의 85% 이내).
Future<void> showNotePreview(
  BuildContext context, {
  required String body,
  required AssetStore assets,
  required VoidCallback onEdit,
  VoidCallback? onSave,
}) {
  final height = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // 넓은 창에서는 글줄이 너무 길어지지 않게 폭을 제한하고 가운데에 둔다.
    constraints: BoxConstraints(maxWidth: 720, maxHeight: height * 0.85),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (sheetContext) => NotePreviewSheet(
      body: body,
      assets: assets,
      onEdit: () {
        Navigator.pop(sheetContext);
        onEdit();
      },
      onSave: onSave == null
          ? null
          : () {
              Navigator.pop(sheetContext);
              onSave();
            },
    ),
  );
}

class NotePreviewSheet extends StatelessWidget {
  const NotePreviewSheet({
    super.key,
    required this.body,
    required this.assets,
    required this.onEdit,
    this.onSave,
  });

  /// 있으면 [저장] 버튼을 맨 앞에 보인다 (저장하지 않은 메모).
  final VoidCallback? onSave;
  final String body;
  final AssetStore assets;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 좁은 창(세로로 붙인 모양)에서는 여백을 줄인다.
    final pad = MediaQuery.sizeOf(context).width < 600 ? AppSpacing.lg : AppSpacing.xl;
    final sheetBody = theme.textTheme.bodyMedium!.copyWith(fontSize: (theme.textTheme.bodyMedium!.fontSize ?? 13) - 1);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 본문만 스크롤된다.
            Flexible(
              child: Scrollbar(
                child: SingleChildScrollView(
                  primary: true,
                  child: CtrlEditShortcuts(
                    child: MarkdownBody(
                      data: body.trim().isEmpty ? ' ' : body,
                      selectable: true,
                      // 시트의 본문은 제목(titleLarge)보다 확실히 작게: 본문은 bodyMedium보다 1pt 작은 크기, 본문 안의 제목들도 그 근처로.
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: userContentStyle(sheetBody),
                        listBullet: userContentStyle(sheetBody),
                        h1: userContentStyle(theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        h2: userContentStyle(theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        h3: userContentStyle(theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                        h4: userContentStyle(theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                        h5: userContentStyle(theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                        h6: userContentStyle(theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                        code: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'Menlo',
                          fontFamilyFallback: const [
                            'SF Mono',
                            'Consolas',
                            'Cascadia Mono',
                            'DejaVu Sans Mono',
                            'Noto Sans Mono',
                            'Courier New',
                          ],
                        ),
                        blockquote: userContentStyle(sheetBody),
                      ),
                      imageBuilder: (uri, title, alt) => NoteImage(uri: uri, alt: alt, assets: assets),
                      onTapLink: (text, href, title) {
                        final uri = href == null ? null : Uri.tryParse(href);
                        if (uri != null) launchUrl(uri);
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 가장 좁은 창에서도 세 버튼이 넘치지 않게 줄을 바꾼다.
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (onSave != null)
                  OutlinedButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: Text(l10n.noteSave),
                  ),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose)),
                FilledButton(onPressed: onEdit, child: Text(l10n.noteEditTab)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
