import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/logic/auth_controller.dart';

/// Re-wraps the existing DEK under a new master password. The old password
/// stays usable until the change succeeds.
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;

  static const int minPasswordLength = 8;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    final ok = await ref
        .read(authControllerProvider.notifier)
        .changePassword(
          currentPassword: _currentController.text,
          newPassword: _newController.text,
        );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (ok) {
      context.pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('主密码已修改')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前密码错误，未做任何修改')));
      _currentController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改主密码')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _currentController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '当前主密码'),
              validator: (v) => (v == null || v.isEmpty) ? '请输入当前主密码' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '新主密码'),
              validator: (v) => (v == null || v.length < minPasswordLength)
                  ? '至少 $minPasswordLength 个字符'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '确认新主密码'),
              validator: (v) => v == _newController.text ? null : '两次输入不一致',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确认修改'),
            ),
          ],
        ),
      ),
    );
  }
}
