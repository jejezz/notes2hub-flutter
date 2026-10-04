import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../images/asset_store.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/user_content.dart';

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
/// 스크롤된다 (제목과 [닫기] [편집] 버튼은 고정). 시트의 틀은 branch-dock-flutter의 시트와 같다
/// (드래그 핸들, 위쪽 모서리 AppRadius.sheet, 화면 높이의 85% 이내).
Future<void> showNotePreview(
  BuildContext context, {
  required String title,
  required String body,
  required AssetStore assets,
  required VoidCallback onEdit,
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
      title: title,
      body: body,
      assets: assets,
      onEdit: () {
        Navigator.pop(sheetContext);
        onEdit();
      },
    ),
  );
}

class NotePreviewSheet extends StatelessWidget {
  const NotePreviewSheet({
    super.key,
    required this.title,
    required this.body,
    required this.assets,
    required this.onEdit,
  });

  final String title;
  final String body;
  final AssetStore assets;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 좁은 창(세로로 붙인 모양)에서는 여백을 줄인다.
    final pad = MediaQuery.sizeOf(context).width < 600 ? AppSpacing.lg : AppSpacing.xl;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.isEmpty ? l10n.noteUntitled : title,
              style: userContentStyle(theme.textTheme.titleLarge),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.md),
            // 본문만 스크롤된다.
            Flexible(
              child: Scrollbar(
                child: SingleChildScrollView(
                  primary: true,
                  child: MarkdownBody(
                    data: body.trim().isEmpty ? ' ' : body,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: userContentStyle(theme.textTheme.bodyLarge),
                      listBullet: userContentStyle(theme.textTheme.bodyLarge),
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
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose)),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(onPressed: onEdit, child: Text(l10n.noteEditTab)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
