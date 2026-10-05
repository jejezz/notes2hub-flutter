import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/screens/share_sheet.dart';
import 'package:notes2hub/share/share_content.dart';

void main() {
  late Directory tmp;
  late File Function(String) assetFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('notes2hub-share');
    assetFile = (name) => File('${tmp.path}/$name');
    for (final n in ['a.jpg', 'b.jpg', 'c.png']) {
      assetFile(n).writeAsBytesSync([1, 2, 3]);
    }
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  const body =
      '# Trip plan\n\nFirst day ![one](../assets/a.jpg)\n\n![two](../assets/b.jpg)\n\nSecond day ![three](../assets/c.png)\n\nEnd';

  group('buildShareContent', () {
    test('full: all text, the title as the subject, every image attached and the image syntax removed', () {
      final c = buildShareContent(body, ShareMode.full, assetFile: assetFile);
      expect(c.subject, 'Trip plan');
      expect(c.text, isNot(contains('![')));
      expect(c.text, isNot(contains('../assets')));
      expect(c.text, contains('First day'));
      expect(c.text, contains('End'));
      expect(c.images.map((f) => f.uri.pathSegments.last), ['a.jpg', 'b.jpg', 'c.png']);
    });

    test('sms: first image only', () {
      final c = buildShareContent(body, ShareMode.sms, assetFile: assetFile);
      expect(c.images.map((f) => f.uri.pathSegments.last), ['a.jpg']);
      expect(c.text, contains('End')); // short enough: untouched
    });

    test('sms: cut at 1000 characters (code points) with an ellipsis; shorter text is untouched', () {
      final long = '가' * 1500;
      final c = buildShareContent(long, ShareMode.sms, assetFile: assetFile);
      expect(c.text.runes.length, kSmsMaxChars);
      expect(c.text.endsWith('…'), isTrue);
      expect(buildShareContent('가' * 1000, ShareMode.sms, assetFile: assetFile).text, '가' * 1000);
      // an emoji (surrogate pair) at the boundary is never split in half
      final emoji = '😀' * 1200;
      final e = buildShareContent(emoji, ShareMode.sms, assetFile: assetFile).text;
      expect(e.runes.length, kSmsMaxChars);
      expect(() => e.runes.toList(), returnsNormally);
      expect(e.codeUnits.where((u) => u >= 0xD800 && u <= 0xDFFF).length % 2, 0);
    });

    test('copy: text only, no images', () {
      final c = buildShareContent(body, ShareMode.copy, assetFile: assetFile);
      expect(c.images, isEmpty);
      expect(c.text, isNot(contains('![')));
    });

    test('missing attachment files are skipped; web images stay as their address', () {
      assetFile('a.jpg').deleteSync();
      const b = 'Look ![x](https://example.com/p.png) and ![y](../assets/a.jpg) and ![z](../assets/b.jpg)';
      final full = buildShareContent(b, ShareMode.full, assetFile: assetFile);
      expect(full.text, contains('https://example.com/p.png'));
      expect(full.images.map((f) => f.uri.pathSegments.last), ['b.jpg']);
      // the first image is gone: sms does not jump to the second one (the order would mislead)
      expect(buildShareContent(b, ShareMode.sms, assetFile: assetFile).images, isEmpty);
    });

    test('an image-only note shares no text and encoded file names are decoded', () {
      assetFile('my photo.jpg').writeAsBytesSync([9]);
      final c = buildShareContent('![](../assets/my%20photo.jpg)', ShareMode.full, assetFile: assetFile);
      expect(c.text, isEmpty);
      expect(c.images.single.uri.pathSegments.last, 'my photo.jpg'); // %20 in the reference → the real file name
    });

    test('blank lines left by removed images are collapsed', () {
      final c = buildShareContent('A\n\n![](../assets/a.jpg)\n\n\n\nB', ShareMode.full, assetFile: assetFile);
      expect(c.text, 'A\n\nB');
    });
  });

  group('share sheet', () {
    ShareContent? shared;
    String? clipboard;

    setUp(() {
      shared = null;
      clipboard = null;
      shareImpl = (c, Rect? o) async => shared = c;
    });

    Future<void> open(WidgetTester tester, String text) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showShareSheet(context, body: text, assets: AssetStore(tmp)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers full / for text messages / copy text', (tester) async {
      await open(tester, body);
      expect(find.text('Share in full'), findsOneWidget);
      expect(find.text('For text messages'), findsOneWidget);
      expect(find.text('First 1000 characters and the first image only'), findsOneWidget);
      expect(find.text('Copy text'), findsOneWidget);

      await tester.tap(find.text('For text messages'));
      await tester.pumpAndSettle();
      expect(shared!.images, hasLength(1));
      expect(find.text('Share in full'), findsNothing); // sheet closed
    });

    testWidgets('full shares every image; copy puts only the text on the clipboard', (tester) async {
      await open(tester, body);
      await tester.tap(find.text('Share in full'));
      await tester.pumpAndSettle();
      expect(shared!.images, hasLength(3));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy text'));
      await tester.pumpAndSettle();
      expect(clipboard, isNotNull);
      expect(clipboard, isNot(contains('![')));
      expect(find.text('Copied to the clipboard'), findsOneWidget);
    });

    testWidgets('an empty note says there is nothing to share instead of opening the sheet', (tester) async {
      await open(tester, '  ');
      expect(find.text('Share in full'), findsNothing);
      expect(find.text('There is nothing to share yet'), findsOneWidget);
    });

    testWidgets('a failing share shows the error instead of crashing', (tester) async {
      shareImpl = (c, o) async => throw PlatformException(code: 'x', message: 'no app');
      await open(tester, body);
      await tester.tap(find.text('Share in full'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not share'), findsOneWidget);
    });
  });
}
