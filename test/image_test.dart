import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/images/image_processor.dart';

/// 압축이 거의 안 되는 무작위 이미지 — 상한을 쉽게 넘긴다.
img.Image noise(int w, int h, {bool alpha = false, int seed = 1}) {
  final r = Random(seed);
  final im = img.Image(width: w, height: h, numChannels: alpha ? 4 : 3);
  for (final p in im) {
    p
      ..r = r.nextInt(256)
      ..g = r.nextInt(256)
      ..b = r.nextInt(256);
    if (alpha) p.a = 255;
  }
  return im;
}

void main() {
  group('prepareImageSync', () {
    test('a small image is kept byte-for-byte with its own extension', () {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 20)));
      final r = prepareImageSync(png);
      expect(r.outcome, ImageOutcome.kept);
      expect(r.bytes, same(png));
      expect(r.ext, 'png');
    });

    test('exactly at the limit is already too big (strictly under 1 MiB)', () {
      final big = Uint8List(kImageLimit)
        ..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(prepareImageSync(big).outcome, isNot(ImageOutcome.kept));
    });

    test('a big PNG becomes a JPEG under the limit', () {
      final png = Uint8List.fromList(img.encodePng(noise(1400, 1000)));
      expect(png.length, greaterThan(kImageLimit));
      final r = prepareImageSync(png);
      expect(r.outcome, ImageOutcome.converted);
      expect(r.ext, 'jpg');
      expect(r.bytes!.length, lessThan(kImageLimit));
      final back = img.decodeJpg(r.bytes!)!;
      expect(back.width, lessThanOrEqualTo(1400));
    });

    test('a transparent PNG is flattened onto white', () {
      final im = noise(1400, 1000, alpha: true);
      // top-left 100x100 fully transparent
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          im.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
      final r = prepareImageSync(Uint8List.fromList(img.encodePng(im)));
      expect(r.outcome, ImageOutcome.converted);
      final px = img.decodeJpg(r.bytes!)!.getPixel(50, 50);
      expect(px.r, greaterThan(240));
      expect(px.g, greaterThan(240));
      expect(px.b, greaterThan(240));
    });

    test('quality drops first, then the long edge shrinks', () {
      final png = Uint8List.fromList(img.encodePng(noise(3000, 2000)));
      final r = prepareImageSync(png);
      expect(r.outcome, ImageOutcome.converted);
      final back = img.decodeJpg(r.bytes!)!;
      // noise at 3000px can't fit at any quality → must have been scaled down
      expect(back.width, lessThan(3000));
      expect([2048, 1600, 1280, 960], contains(back.width));
    });

    test('when nothing fits it still returns the smallest attempt, flagged', () {
      final png = Uint8List.fromList(img.encodePng(noise(1100, 900)));
      final r = prepareImageSync(png, limit: 20 * 1024);
      expect(r.outcome, ImageOutcome.convertedStillLarge);
      expect(r.bytes, isNotNull);
      expect(r.ext, 'jpg');
    });

    test('an oversized GIF is rejected, not converted', () {
      final gif = Uint8List.fromList(img.encodeGif(noise(1100, 1100)));
      expect(gif.length, greaterThan(kImageLimit));
      final r = prepareImageSync(gif);
      expect(r.outcome, ImageOutcome.rejectedAnimated);
      expect(r.usable, isFalse);
    });

    test('unknown or corrupt data is unsupported', () {
      expect(prepareImageSync(Uint8List.fromList([1, 2, 3, 4, 5])).outcome, ImageOutcome.unsupported);
      final truncated = Uint8List(kImageLimit + 10)..setAll(0, [0x89, 0x50, 0x4E, 0x47]);
      expect(prepareImageSync(truncated).outcome, ImageOutcome.unsupported);
    });

    test('prepareImage runs the same logic off the main isolate', () async {
      final png = Uint8List.fromList(img.encodePng(noise(1400, 1000)));
      final r = await prepareImage(png);
      expect(r.outcome, ImageOutcome.converted);
    });
  });

  group('AssetStore', () {
    late Directory tmp;
    late AssetStore store;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('notes2hub-assets');
      store = AssetStore(Directory('${tmp.path}/assets'));
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('add writes <uuid>.<ext> atomically', () async {
      final name = await store.add(Uint8List.fromList([1, 2, 3]), 'png');
      expect(name, matches(RegExp(r'^[0-9a-f-]{36}\.png$')));
      expect(store.file(name).readAsBytesSync(), [1, 2, 3]);
      expect(File('${store.file(name).path}.tmp').existsSync(), isFalse);
    });

    test('markdown reference round-trips through referencedIn', () {
      final md = AssetStore.markdownFor('abc.jpg', alt: 'a [shot]\nname');
      expect(md, '![a  shot  name](../assets/abc.jpg)');
      final body = '# t\n\n$md\n\ntext ![x](../assets/def.png) and ![web](https://x/y.png)';
      expect(AssetStore.referencedIn(body), {'abc.jpg', 'def.png'});
    });

    test('collectOrphans removes only old unreferenced files', () async {
      final keep = await store.add(Uint8List(1), 'jpg');
      final old = await store.add(Uint8List(1), 'jpg');
      final fresh = await store.add(Uint8List(1), 'jpg');
      store.file(old).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
      store.file(keep).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
      final n = await store.collectOrphans({keep});
      expect(n, 1);
      expect(store.file(old).existsSync(), isFalse);
      expect(store.file(keep).existsSync(), isTrue);
      expect(store.file(fresh).existsSync(), isTrue); // too new to touch
    });
  });
}
