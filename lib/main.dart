// From jejezz/application-release-templates common/ @ conventions-v1.
//
// 새 앱의 시작점. 규약이 요구하는 연결을 한곳에 모았다:
//   창 크기(window_manager) · 추가 라이선스 · 설정 로드 · 라이트/다크 ·
//   언어 해석 · macOS 앱 메뉴 About · 앱 바 [테마 | 언어 | 정보] · 빈 상태.
// 기존 앱에는 통째로 덮어쓰지 말고 필요한 부분만 옮긴다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'about/about_dialog.dart';
import 'about/app_menu_bar.dart';
import 'about/extra_licenses.dart';
import 'app_identity.dart';
import 'l10n/app_localizations.dart';
import 'auth/token_store.dart';
import 'images/asset_store.dart';
import 'notes/app_paths.dart';
import 'notes/note_store.dart';
import 'notes/notes_controller.dart';
import 'screens/notes_screen.dart';
import 'sync/ca_bundle.dart';
import 'sync/libgit2_engine.dart';
import 'sync/sync_service.dart';
import 'window/window_layout.dart';
import 'settings/app_settings.dart';
import 'theme/app_theme.dart';

final bool _isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerExtraLicenses();

  final prefs = await SharedPreferences.getInstance();
  WindowLayout? windowLayout;
  if (_isDesktop) {
    await windowManager.ensureInitialized();
    final layout = WindowLayout(prefs: prefs, port: DesktopWindowPort());
    windowLayout = layout;
    // ui-ux.md §5: 최소 크기는 960×600 이하. 이 앱은 화면 가장자리에 세로로 붙여 쓰는 메모 앱이라
    // 훨씬 좁게(320) 줄일 수 있다. 크기·위치는 직접 정하지 않고 저장된 값(또는 도킹)을 복원한다.
    const options = WindowOptions(minimumSize: Size(320, 420), title: AppIdentity.displayName);
    await windowManager.waitUntilReadyToShow(options, () async {
      await layout.restore(); // 창을 보이기 전에 위치·크기를 맞춘다 (깜빡임 방지)
      windowManager.addListener(layout);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final settings = await AppSettings.load();
  // 지금은 로컬 폴더. Phase 2에서 notes/ 가 GitHub 저장소 클론 안으로 옮겨간다 (docs/PLAN.md §4).
  final base = await appDataDir();
  final notes = NotesController(NoteStore(
    notesDir: Directory('${base.path}/data/notes'),
    draftsDir: Directory('${base.path}/drafts'),
  ));
  final assets = AssetStore(Directory('${base.path}/data/assets'));
  final engine = LibGit2Engine(dir: Directory('${base.path}/data'), caCertPath: await ensureCaBundle(base));
  final sync = SyncService(
    prefs: prefs,
    tokens: SecureTokenStore(),
    engine: engine,
    notes: notes,
  );
  runApp(App(settings: settings, notes: notes, sync: sync, assets: assets, windowLayout: windowLayout));
}

class App extends StatefulWidget {
  const App({
    super.key,
    required this.settings,
    required this.notes,
    required this.sync,
    required this.assets,
    this.windowLayout,
  });

  final AppSettings settings;
  final NotesController notes;
  final SyncService sync;
  final AssetStore assets;
  final WindowLayout? windowLayout;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_syncWindowBrightness);
    _syncWindowBrightness();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      await widget.notes.load();
      // 어떤 메모도 참조하지 않는 오래된 첨부를 정리한다 (7일 지난 것만).
      unawaited(widget.assets.collectOrphans(widget.notes.referencedAssets));
      // 메모를 읽은 뒤에 연결 상태를 복원한다 — 시작 pull이 끝나면 목록을 다시 읽는다.
      await widget.sync.init();
    } catch (e) {
      // 목록을 못 읽어도 앱은 열린다 — 빈 상태로 시작하고 원인을 알린다.
      widget.notes.markLoaded();
      final context = _navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).noteLoadFailed('$e'))));
      }
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncWindowBrightness);
    widget.sync.dispose();
    widget.notes.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 앱에서 다크를 골라도 OS가 라이트면 제목 표시줄은 밝게 남는다 (theming.md §4).
  @override
  void didChangePlatformBrightness() => _syncWindowBrightness();

  void _syncWindowBrightness() {
    if (!_isDesktop || Platform.isLinux) return;
    final brightness = switch (widget.settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    windowManager.setBrightness(brightness);
  }

  void _showAbout() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final l10n = AppLocalizations.of(context);
    showAppAboutDialog(context, tagline: l10n.aboutTagline, description: l10n.aboutDescription);
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: widget.settings,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          title: AppIdentity.displayName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(dense: _isDesktop),
          darkTheme: AppTheme.dark(dense: _isDesktop),
          themeMode: widget.settings.themeMode,
          locale: widget.settings.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: AppSettings.resolveLocale,
          builder: (context, child) => AppMenuBar(onAbout: _showAbout, child: child!),
          home: NotesScreen(controller: widget.notes, sync: widget.sync, assets: widget.assets, windowLayout: widget.windowLayout, onAbout: _showAbout),
        ),
      ),
    );
  }
}
