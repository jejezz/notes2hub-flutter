import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../images/asset_store.dart';
import '../l10n/app_localizations.dart';
import '../share/share_content.dart';

/// 버튼이 있는 자리의 화면 좌표. iPad·macOS의 공유 말풍선이 이 자리에 붙는다 (없으면 시스템이 정한다).
Rect? shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// 공유 형식을 고르는 시트: 전체 공유 / 문자용 / 텍스트 복사. 고르면 시트가 닫히고 시스템 공유 화면이 열린다.
Future<void> showShareSheet(BuildContext context, {required String body, required AssetStore assets, Rect? origin}) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (body.trim().isEmpty) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.shareNothing)));
    return Future.value();
  }

  Future<void> run(ShareMode mode) async {
    final content = buildShareContent(body, mode, assetFile: assets.file);
    try {
      if (mode == ShareMode.copy) {
        await Clipboard.setData(ClipboardData(text: content.text));
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.shareCopied)));
      } else {
        await shareContent(content, origin: origin);
      }
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.shareFailed('$e'))));
    }
  }

  return showModalBottomSheet<void>(
    context: context,
    // 낮은 화면(폰 가로, 작은 창)에서 선택지가 잘리지 않게 높이를 늘릴 수 있게 하고, 그래도 모자라면 스크롤한다.
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (sheetContext) {
      Widget option(IconData icon, String title, String hint, ShareMode mode) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(hint),
        onTap: () {
          Navigator.pop(sheetContext);
          run(mode);
        },
      );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(l10n.shareTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              option(Icons.ios_share_rounded, l10n.shareFull, l10n.shareFullHint, ShareMode.full),
              option(Icons.notes_rounded, l10n.shareTextOnly, l10n.shareTextOnlyHint, ShareMode.textOnly),
              option(Icons.sms_outlined, l10n.shareSms, l10n.shareSmsHint(kSmsMaxChars), ShareMode.sms),
              option(Icons.copy_rounded, l10n.shareCopy, l10n.shareCopyHint, ShareMode.copy),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
