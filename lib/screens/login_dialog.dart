import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../github/device_flow.dart';
import '../github/github_config.dart';
import '../l10n/app_localizations.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';

/// GitHub 로그인. 기본은 브라우저 로그인(Device Flow) — 열자마자 시작해서 코드를 보여준다.
/// 토큰 직접 입력은 "고급"으로 내려 두었다. 성공하면 true.
Future<bool?> showLoginDialog(BuildContext context, SyncService sync) => showDialog<bool>(
  context: context,
  builder: (_) => _LoginDialog(sync: sync),
);

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.sync});

  final SyncService sync;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  // Client ID가 없는 빌드는 브라우저 로그인을 쓸 수 없으니 처음부터 토큰 입력을 보여준다.
  late bool _showToken = kGitHubClientId.isEmpty;
  final _token = TextEditingController();
  DeviceCode? _code;
  bool _busy = false;
  bool _closed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (kGitHubClientId.isNotEmpty) _startDevice();
  }

  @override
  void dispose() {
    _closed = true; // 진행 중인 승인 대기를 멈춘다.
    _token.dispose();
    super.dispose();
  }

  Future<void> _startDevice() async {
    setState(() {
      _busy = true;
      _error = null;
      _code = null;
    });
    String? failure;
    try {
      final flow = DeviceFlow(kGitHubClientId);
      final code = await flow.start();
      if (_closed) return;
      setState(() => _code = code);
      await launchUrl(Uri.parse(code.verificationUri));
      final token = await flow.awaitToken(code, cancelled: () => _closed);
      if (token == null || _closed) return;
      await widget.sync.loginWithToken(token);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      failure = '$e';
    } finally {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _busy = false;
          if (failure != null) {
            _error = l10n.loginFailed(failure);
            _code = null;
          }
        });
      }
    }
  }

  Future<void> _submitToken() async {
    final l10n = AppLocalizations.of(context);
    if (_token.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.sync.loginWithToken(_token.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = l10n.loginFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasBrowser = kGitHubClientId.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.loginTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasBrowser) ...[
              Text(l10n.loginBrowserFirst, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.lg),
              if (_code != null) ...[
                Text(l10n.loginDeviceStep, style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.md),
                Center(child: SelectableText(_code!.userCode, style: theme.textTheme.headlineMedium)),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => launchUrl(Uri.parse(_code!.verificationUri)),
                      child: Text(l10n.loginOpenBrowser),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () => Clipboard.setData(ClipboardData(text: _code!.userCode)),
                      child: Text(l10n.loginCopyCode),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(l10n.loginWaiting, style: theme.textTheme.bodySmall),
                  ],
                ),
              ] else if (_busy)
                const Center(child: CircularProgressIndicator())
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(onPressed: _startDevice, child: Text(l10n.loginRetry)),
                ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showToken = !_showToken),
                  child: Text(l10n.loginAdvancedToken),
                ),
              ),
            ] else
              Text(l10n.loginDeviceUnavailable, style: theme.textTheme.bodySmall),
            if (_showToken) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _token,
                obscureText: true,
                autofocus: !hasBrowser,
                enabled: !_busy || hasBrowser,
                decoration: InputDecoration(labelText: l10n.loginTokenLabel),
                onSubmitted: (_) => _submitToken(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.loginTokenHelp, style: theme.textTheme.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              SelectableText(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
        if (_showToken) FilledButton(onPressed: _submitToken, child: Text(l10n.loginSubmit)),
      ],
    );
  }
}
