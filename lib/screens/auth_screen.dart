import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'image_source_screen.dart';
import 'password_screen.dart';
import '../services/auth_service.dart';
import '../services/ocr_service.dart';

class AuthScreen extends StatefulWidget {
  final BaseOcrService? ocrService;
  final AuthService? authService;
  final VoidCallback? onAuthenticated;

  const AuthScreen(
      {super.key, this.ocrService, this.authService, this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSignUp = false;
  bool _hidePassword = true;
  bool _isSubmitting = false;

  AuthService get _authService =>
      widget.authService ?? const SupabaseAuthService();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleMode(bool signUp) {
    if (_isSignUp == signUp) return;
    setState(() {
      _isSignUp = signUp;
      _formKey.currentState?.reset();
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  void _continueToHome() {
    if (widget.onAuthenticated != null) {
      widget.onAuthenticated!();
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ImageSourceScreen(ocrService: widget.ocrService),
    ));
  }

  Future<void> _submit() async {
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) return;

    final isSignUp = _isSignUp;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final fullName = _nameController.text.trim();

    setState(() => _isSubmitting = true);
    try {
      if (isSignUp) {
        final hasSession = await _authService.signUp(
          email: email,
          password: password,
          fullName: fullName,
        );
        if (!mounted) return;
        if (!hasSession) {
          _showMessage(
            'Account created. Check your email to confirm your account before logging in.',
          );
          return;
        }
      } else {
        await _authService.signInWithPassword(
          email: email,
          password: password,
        );
      }

      if (mounted) _continueToHome();
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Unable to ${isSignUp ? 'create your account' : 'log in'}: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter your email address';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.document_scanner_outlined,
                          size: 30, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        'OBE-Lens',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mark sheet capture, review and attainment',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(value: false, label: Text('Log in')),
                                ButtonSegment(value: true, label: Text('Sign up')),
                              ],
                              selected: {_isSignUp},
                              onSelectionChanged: _isSubmitting
                                  ? null
                                  : (selection) => _toggleMode(selection.first),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              _isSignUp ? 'Create your account' : 'Welcome back',
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isSignUp
                                  ? 'New accounts stay pending until an administrator approves them.'
                                  : 'Sign in to continue to your workspace.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: muted),
                            ),
                            const SizedBox(height: 20),
                            if (_isSignUp) ...[
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration:
                                    const InputDecoration(labelText: 'Full name'),
                                validator: (value) =>
                                    (value?.trim().isEmpty ?? true)
                                        ? 'Please enter your name'
                                        : null,
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                  labelText: 'Email address'),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _hidePassword,
                              textInputAction: _isSignUp
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) {
                                if (!_isSignUp) _submit();
                              },
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  tooltip: _hidePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () => setState(
                                      () => _hidePassword = !_hidePassword),
                                  icon: Icon(_hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                if (_isSignUp && value.length < 8) {
                                  return 'Use at least 8 characters';
                                }
                                return null;
                              },
                            ),
                            if (_isSignUp) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _hidePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(
                                    labelText: 'Confirm password'),
                                validator: (value) =>
                                    value != _passwordController.text
                                        ? 'Passwords do not match'
                                        : null,
                              ),
                            ],
                            if (!_isSignUp)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) => PasswordScreen(
                                                    auth: _authService)),
                                          ),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(_isSignUp ? 'Create account' : 'Log in'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _isSignUp
                              ? 'Already have an account?'
                              : 'New to OBE-Lens?',
                          overflow: TextOverflow.ellipsis,
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => _toggleMode(!_isSignUp),
                        child: Text(_isSignUp ? 'Log in' : 'Create account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
