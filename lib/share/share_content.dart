import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../notes/note.dart';

/// 공유 형식. 시스템 공유 화면에서는 사용자가 어떤 앱(문자·메일·카카오톡…)을 고르는지 알 수 없어서,
/// 공유하기 전에 형식을 고르게 한다.
enum ShareMode {
  /// 메일·메신저: 글 전체 + 첨부 이미지 모두.
  full,

  /// 글만: 이미지 없이 글 전체. 카카오톡처럼 글과 이미지를 함께 받으면 글을 버리고 이미지만 보내는 앱용.
  textOnly,

  /// 문자(SMS/MMS): 글을 [kSmsMaxChars]자까지만, 이미지는 첫 번째 1장만.
  sms,

  /// 클립보드에 글만 (공유 화면을 쓰지 못하는 곳, 예: 이미지를 못 보내는 Linux).
  copy,
}

/// 문자용 글자 수 상한. 한국 통신사 LMS(약 2,000바이트 ≈ 한글 1,000자) 기준 — 통신사·문자 앱마다 달라서 상수로 둔다.
const kSmsMaxChars = 1000;

/// 공유할 내용. 이미지는 실제로 있는 첨부 파일만 담는다.
class ShareContent {
  const ShareContent({required this.subject, required this.text, this.images = const []});

  /// 메일 제목으로 쓰이는 메모 제목 (본문 첫 글 줄). 전체 공유에서만 채운다 — 비어 있으면 제목 없이 보낸다.
  final String subject;
  final String text;
  final List<File> images;
}

// ![alt](주소 "제목") — 주소에 공백이 없다고 본다.
final _imageRef = RegExp(r'!\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)');
final _localAsset = RegExp(r'^\.\./assets/(.+)$');

/// 메모 본문에서 공유할 내용을 만든다.
///
/// - 사용자가 친 줄바꿈·빈 줄은 그대로 둔다 (Markdown 문법도 바꾸지 않는다).
/// - 첨부 이미지 참조(`![..](../assets/x.jpg)`)는 받는 사람에게 의미가 없어서 글에서 빼고, 파일로 붙인다.
///   웹 이미지(http/https)는 주소를 글로 남긴다.
/// - [ShareMode.sms]: 글자 수를 [smsMax]자(유니코드 글자 단위)로 줄이고(잘리면 …), 이미지는 첫 번째 1장.
/// - [ShareMode.textOnly], [ShareMode.copy]: 이미지 없이 글 전체.
ShareContent buildShareContent(
  String body,
  ShareMode mode, {
  required File Function(String name) assetFile,
  int smsMax = kSmsMaxChars,
}) {
  final names = <String>[];
  String strip(String line) => line.replaceAllMapped(_imageRef, (m) {
    final url = m.group(2)!;
    final local = _localAsset.firstMatch(url);
    if (local != null) {
      final name = Uri.decodeComponent(local.group(1)!);
      if (!names.contains(name)) names.add(name);
      return '';
    }
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '';
  });

  // 줄 단위로 처리해서 사용자가 친 줄바꿈과 빈 줄은 그대로 둔다. 이미지만 있던 줄은 줄째 빼고, 그 줄이
  // 빈 줄 사이에 있었다면 빈 줄이 겹치지 않게 하나만 줄인다.
  final lines = body.split('\n');
  final kept = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!_imageRef.hasMatch(line)) {
      kept.add(line);
      continue;
    }
    final stripped = strip(line);
    if (stripped.trim().isNotEmpty) {
      kept.add(stripped);
    } else if (kept.isNotEmpty && kept.last.trim().isEmpty && i + 1 < lines.length && lines[i + 1].trim().isEmpty) {
      i++; // 위아래가 모두 빈 줄이면 하나를 줄인다
    }
  }
  var text = kept.join('\n').trim();

  if (mode == ShareMode.sms) {
    final runes = text.runes.toList();
    if (runes.length > smsMax) text = '${String.fromCharCodes(runes.take(smsMax - 1)).trimRight()}…';
  }

  final images = switch (mode) {
    ShareMode.full => [for (final n in names) assetFile(n)],
    ShareMode.sms => [for (final n in names.take(1)) assetFile(n)],
    ShareMode.textOnly || ShareMode.copy => <File>[],
  }.where((f) => f.existsSync()).toList();
  // 첫 이미지 파일이 없으면 문자용도 다음 이미지로 넘어가지 않고 글만 보낸다 (순서가 바뀌면 오해를 부른다).

  // 제목은 메일 제목으로만 쓴다. 문자·메신저는 [제목][본문]으로 보여 주는데 본문 첫 줄이 곧 제목이라 겹친다.
  final subject = mode == ShareMode.full
      ? Note(id: '', created: DateTime.utc(2000), updated: DateTime.utc(2000), body: body).title
      : '';
  return ShareContent(subject: subject, text: text, images: images);
}

/// 시스템 공유 화면을 연다. 테스트에서 가짜로 바꿀 수 있다.
@visibleForTesting
Future<void> Function(ShareContent content, Rect? origin) shareImpl = _defaultShare;

Future<void> shareContent(ShareContent content, {Rect? origin}) => shareImpl(content, origin);

Future<void> _defaultShare(ShareContent content, Rect? origin) async {
  // Linux는 메일(mailto)로 글만 보낼 수 있고 파일은 지원하지 않는다.
  final files = Platform.isLinux ? const <File>[] : content.images;
  await SharePlus.instance.share(
    ShareParams(
      text: content.text,
      subject: content.subject.isEmpty ? null : content.subject,
      files: files.isEmpty ? null : [for (final f in files) XFile(f.path)],
      sharePositionOrigin: origin, // iPad·macOS는 말풍선이 붙을 자리가 필요하다
    ),
  );
}
