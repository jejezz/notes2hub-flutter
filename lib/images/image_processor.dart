import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 이미지 한 장의 크기 상한 (1 MiB 미만). 저장소가 이미지로 비대해지지 않게 한다 (docs/PLAN.md §6).
const kImageLimit = 1024 * 1024;

enum ImageOutcome {
  /// 상한 미만이라 원본 그대로.
  kept,

  /// 상한을 넘어 JPEG로 줄였다.
  converted,

  /// 줄일 수 있는 데까지 줄였지만 상한을 못 맞췄다 (그래도 가장 작은 결과를 쓴다).
  convertedStillLarge,

  /// 움직이는 이미지(GIF 등)는 변환하지 않는다 — 상한을 넘으면 거부한다.
  rejectedAnimated,

  /// 알 수 없거나 읽을 수 없는 형식.
  unsupported,
}

class PreparedImage {
  const PreparedImage({required this.outcome, required this.originalSize, this.bytes, this.ext});

  final ImageOutcome outcome;
  final int originalSize;

  /// 저장할 내용과 확장자(점 없음). 거부된 경우 null.
  final Uint8List? bytes;
  final String? ext;

  bool get usable => bytes != null;
}

/// UI를 막지 않도록 Isolate에서 처리한다.
Future<PreparedImage> prepareImage(Uint8List data, {int limit = kImageLimit}) =>
    Isolate.run(() => prepareImageSync(data, limit: limit));

/// 파일 머리의 매직 바이트로 형식을 알아낸다. 모르면 null.
String? sniffImageExtension(Uint8List b) {
  bool at(int i, List<int> sig) {
    if (b.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  if (at(0, [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (at(0, [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (at(0, [0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) return 'webp';
  if (at(0, [0x42, 0x4D])) return 'bmp';
  if (at(4, [0x66, 0x74, 0x79, 0x70])) return 'heic'; // ISO base media (HEIC/AVIF)
  return null;
}

// 품질을 먼저 낮추고(85 → 50), 그래도 크면 긴 변을 줄인다 (최저 960px).
const _qualities = [85, 75, 65, 50];
const _longEdges = [2048, 1600, 1280, 960];

PreparedImage prepareImageSync(Uint8List data, {int limit = kImageLimit}) {
  final ext = sniffImageExtension(data);
  if (ext == null) return PreparedImage(outcome: ImageOutcome.unsupported, originalSize: data.length);
  if (data.length < limit) {
    return PreparedImage(outcome: ImageOutcome.kept, originalSize: data.length, bytes: data, ext: ext);
  }
  // 이하는 상한을 넘은 이미지.
  if (ext == 'gif') return PreparedImage(outcome: ImageOutcome.rejectedAnimated, originalSize: data.length);
  if (ext == 'heic') return PreparedImage(outcome: ImageOutcome.unsupported, originalSize: data.length);

  final decoder = img.findDecoderForData(data);
  final info = decoder?.startDecode(data);
  if (decoder == null || info == null) {
    return PreparedImage(outcome: ImageOutcome.unsupported, originalSize: data.length);
  }
  if (info.numFrames > 1) return PreparedImage(outcome: ImageOutcome.rejectedAnimated, originalSize: data.length);
  var image = decoder.decode(data);
  if (image == null) return PreparedImage(outcome: ImageOutcome.unsupported, originalSize: data.length);

  image = img.bakeOrientation(image);
  if (image.hasAlpha) image = _flattenOnWhite(image);

  final long = image.width > image.height ? image.width : image.height;
  // 원래 크기부터 시작해서, 그보다 작은 단계로 내려간다.
  final steps = <int>[long, ..._longEdges.where((e) => e < long)];
  Uint8List? last;
  for (final edge in steps) {
    final scaled = edge == long
        ? image
        : (image.width >= image.height
            ? img.copyResize(image, width: edge, interpolation: img.Interpolation.average)
            : img.copyResize(image, height: edge, interpolation: img.Interpolation.average));
    for (final q in _qualities) {
      last = img.encodeJpg(scaled, quality: q);
      if (last.length < limit) {
        return PreparedImage(outcome: ImageOutcome.converted, originalSize: data.length, bytes: last, ext: 'jpg');
      }
    }
  }
  return PreparedImage(outcome: ImageOutcome.convertedStillLarge, originalSize: data.length, bytes: last, ext: 'jpg');
}

/// JPEG에는 투명도가 없다 — 흰 배경에 합성한다.
img.Image _flattenOnWhite(img.Image src) {
  final out = img.Image(width: src.width, height: src.height, numChannels: 3);
  img.fill(out, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(out, src);
  return out;
}
