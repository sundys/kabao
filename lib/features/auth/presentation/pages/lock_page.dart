import 'dart:async';

import 'dart:async';

import 'package:flutter/material.dart';
// local_auth conditionally re-exports this library depending on the host
// platform; the explicit import keeps AndroidAuthMessages resolvable.
// ignore_for_file: duplicate_import
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart'
    show AndroidAuthMessages;

import '../../../../app/app_routes.dart';
import '../../logic/auth_controller.dart';
import '../../models/auth_state.dart';

class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorText;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) {
        return;
      }
      final remaining = ref
          .read(authControllerProvider.notifier)
          .remainingBackoff;
      if (remaining != _remaining) {
        setState(() => _remaining = remaining);
      }
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_remaining > Duration.zero || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final ok = await ref
        .read(authControllerProvider.notifier)
        .unlockWithPassword(_passwordController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      if (!ok) {
        _errorText = '主密码错误';
        _passwordController.clear();
      }
    });
    if (ok) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _unlockWithBiometrics() async {
    // Pre-check so unsupported/unenrolled devices get a clear message
    // instead of a silent failure from the platform channel.
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = supported && await _localAuth.canCheckBiometrics;
      if (!mounted) {
        return;
      }
      if (!canCheck) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('此设备不可用生物识别，请使用主密码解锁')));
        return;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生物识别初始化失败')));
      }
      return;
    }

    var authenticated = false;
    var errorMessage = '生物识别未通过，请使用主密码解锁';
    final busy = ref.read(biometricAuthInProgressProvider.notifier);
    try {
      busy.start();
      authenticated = await ref
          .read(authControllerProvider.notifier)
          .unlockWithBiometrics(
            authenticate: () => _localAuth.authenticate(
              localizedReason: '验证指纹以解锁卡包',
              biometricOnly: true,
              persistAcrossBackgrounding: true,
              authMessages: const [
                // Replace the plugin defaults ("Authentication required" and
                // "Verify identity") with Chinese equivalents.
                AndroidAuthMessages(
                  signInTitle: '需要验证指纹',
                  signInHint: '',
                  cancelButton: '取消',
                ),
              ],
            ),
          );
    } catch (_) {
      // Platform errors (missing FragmentActivity host, plugin not ready…)
      // must never crash silently; fall back to the password path.
      errorMessage = '生物识别调用失败，请使用主密码解锁';
    } finally {
      // Reset after the resumed event has been delivered.
      Future.delayed(const Duration(milliseconds: 300), busy.stop);
    }
    if (!mounted) {
      return;
    }
    if (authenticated) {
      context.go(AppRoutes.home);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).value;
    final biometricEnabled =
        authState is AuthLocked && authState.biometricEnabled;
    final theme = Theme.of(context);
    final locked = _remaining > Duration.zero;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '卡包已锁定',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('lock-password'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    enableSuggestions: false,
                    autocorrect: false,
                    onSubmitted: (_) => _unlock(),
                    decoration: InputDecoration(
                      labelText: '主密码',
                      errorText: _errorText,
                      enabled: !locked,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: locked || _submitting ? null : _unlock,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(locked ? '请等待 ${_remaining.inSeconds} 秒' : '解锁'),
                  ),
                  if (biometricEnabled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: locked ? null : _unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('使用生物识别解锁'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
