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

/// 보드에서 카드를 눌렀을 때 스낵바에 띄우는 미리보기: Markdown을 렌더링해서 보여주고,
/// 길면 스크롤된다 (편집 화면을 열지 않고 내용만 훑어볼 때).
class NotePreviewSnack extends StatelessWidget {
  const NotePreviewSnack({super.key, required this.body, required this.assets, this.maxHeight = 360});

  final String body;
  final AssetStore assets;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scrollbar(
        child: SingleChildScrollView(
          primary: true,
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: MarkdownBody(
            data: body.trim().isEmpty ? ' ' : body,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: userContentStyle(theme.textTheme.bodyMedium),
              listBullet: userContentStyle(theme.textTheme.bodyMedium),
            ),
            imageBuilder: (uri, title, alt) => NoteImage(uri: uri, alt: alt, assets: assets),
            onTapLink: (text, href, title) {
              final uri = href == null ? null : Uri.tryParse(href);
              if (uri != null) launchUrl(uri);
            },
          ),
        ),
      ),
    );
  }
}

/// 스낵바 미리보기를 보여준다. 닫기 버튼과 "편집" 동작이 있고, 닫을 때까지 남는다.
void showNotePreview(
  BuildContext context, {
  required String body,
  required AssetStore assets,
  required VoidCallback onEdit,
}) {
  final l10n = AppLocalizations.of(context);
  final height = MediaQuery.sizeOf(context).height;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        persist: true,
        showCloseIcon: true,
        duration: const Duration(days: 1),
        content: NotePreviewSnack(body: body, assets: assets, maxHeight: (height * 0.5).clamp(160, 420)),
        action: SnackBarAction(
          label: l10n.noteEditTab,
          onPressed: () {
            messenger.hideCurrentSnackBar();
            onEdit();
          },
        ),
      ),
    );
}
