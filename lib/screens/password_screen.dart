import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../workflow/ui.dart';

class PasswordScreen extends StatefulWidget {
  final AuthService auth;
  final bool recovery;
  final Future<void> Function()? onComplete;
  const PasswordScreen(
      {super.key, required this.auth, this.recovery = false, this.onComplete});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _value = TextEditingController(), _confirm = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _value.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.recovery) {
      if (_value.text.length < 6 || _value.text != _confirm.text) {
        showError(
            context, 'Use at least six characters and matching passwords.');
        return;
      }
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
        .hasMatch(_value.text.trim())) {
      showError(context, 'Enter a valid email address.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.recovery) {
        await widget.auth.updatePassword(_value.text);
        await widget.onComplete?.call();
      } else {
        await widget.auth.resetPassword(_value.text.trim());
        if (mounted) {
          setState(
              () => _message = 'Check your email for the password reset link.');
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkflowPage(
          title: widget.recovery ? 'Choose a new password' : 'Reset password',
          children: [
            TextField(
                controller: _value,
                obscureText: widget.recovery,
                decoration: InputDecoration(
                    labelText:
                        widget.recovery ? 'New password' : 'Email address')),
            if (widget.recovery)
              TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm password')),
            if (_message != null) Text(_message!),
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(widget.recovery
                    ? 'Save password and return to login'
                    : 'Send reset link')),
            if (!widget.recovery)
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to login')),
          ]);
}
