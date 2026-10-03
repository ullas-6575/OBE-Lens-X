import 'package:flutter/material.dart';
import 'image_source_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  static const _ink = Color(0xFF102A43);
  static const _blue = Color(0xFF2563EB);
  static const _teal = Color(0xFF0D9488);
  static const _demoEmail = 'demo@obelens.com';
  static const _demoPassword = 'Lens2026!';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late final AnimationController _introController;
  late final AnimationController _floatController;
  late final Animation<double> _introAnimation;
  bool _isSignUp = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _introAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _introController.forward();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    _floatController.dispose();
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
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ImageSourceScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (!_isSignUp &&
        (_emailController.text.trim().toLowerCase() != _demoEmail ||
            _passwordController.text != _demoPassword)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Those details do not match the demo account.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _continueToHome();
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
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF071B33),
                    Color(0xFF123C5A),
                    Color(0xFF126C78)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            top: -95,
            right: -48,
            child: _floatingOrb(
              size: 300,
              color: const Color(0xFF42D6C3).withOpacity(0.12),
              phase: 0,
            ),
          ),
          Positioned(
            bottom: -125,
            left: -85,
            child: _floatingOrb(
              size: 330,
              color: const Color(0xFF5888FF).withOpacity(0.16),
              phase: 0.5,
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 28,
                ),
                child: FadeTransition(
                  opacity: _introAnimation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.07),
                      end: Offset.zero,
                    ).animate(_introAnimation),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isWide ? 1040 : 470,
                      ),
                      child: isWide
                          ? Row(
                              children: [
                                Expanded(child: _buildWelcomePanel()),
                                const SizedBox(width: 42),
                                SizedBox(width: 440, child: _buildAuthCard()),
                              ],
                            )
                          : Column(
                              children: [
                                _buildBrandHeader(compact: true),
                                const SizedBox(height: 26),
                                _buildAuthCard(),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingOrb({
    required double size,
    required Color color,
    required double phase,
  }) {
    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        final offset = ((_floatController.value + phase) % 1) * 20 - 10;
        return Transform.translate(
          offset: Offset(offset, -offset),
          child: child,
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 75, spreadRadius: 18)
          ],
        ),
      ),
    );
  }

  Widget _buildBrandHeader({required bool compact}) {
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_teal, _blue]),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.document_scanner_rounded,
                color: Colors.white,
                size: 25,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'OBE Lens',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 36),
          const Text(
            'See every mark.\nClearly.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              height: 1.08,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Turn handwritten mark sheets into clear, organized results in moments.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.76),
              fontSize: 17,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 32),
          _feature(Icons.bolt_rounded, 'Fast mark-sheet scanning'),
          const SizedBox(height: 14),
          _feature(Icons.fact_check_rounded, 'Review every detected result'),
          const SizedBox(height: 14),
          _feature(Icons.insights_rounded, 'Automatic totals, ready to use'),
        ],
      ],
    );
  }

  Widget _buildWelcomePanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: _buildBrandHeader(compact: false),
    );
  }

  Widget _feature(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6DE0CE), size: 21),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.88),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF031326).withOpacity(0.24),
            blurRadius: 44,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _modeButton('Log in',
                    isSelected: !_isSignUp, onTap: () => _toggleMode(false)),
                _modeButton('Sign up',
                    isSelected: _isSignUp, onTap: () => _toggleMode(true)),
              ],
            ),
          ),
          const SizedBox(height: 26),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.035, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(_isSignUp),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isSignUp ? 'Create your account' : 'Welcome back',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _isSignUp
                      ? 'Start making mark-sheet reviews effortless.'
                      : 'Sign in to continue to your workspace.',
                  style: const TextStyle(
                    color: Color(0xFF66788A),
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isSignUp) ...[
                  _inputLabel('Full name'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      hint: 'Your name',
                      icon: Icons.person_outline_rounded,
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Please enter your name'
                        : null,
                  ),
                  const SizedBox(height: 17),
                ],
                _inputLabel('Email address'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: _fieldDecoration(
                    hint: 'you@example.com',
                    icon: Icons.alternate_email_rounded,
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 17),
                _inputLabel('Password'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _hidePassword,
                  textInputAction:
                      _isSignUp ? TextInputAction.next : TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) {
                    if (!_isSignUp) _submit();
                  },
                  decoration: _fieldDecoration(
                    hint: _isSignUp ? 'At least 8 characters' : 'Your password',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      tooltip:
                          _hidePassword ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() {
                        _hidePassword = !_hidePassword;
                      }),
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF73869A),
                        size: 20,
                      ),
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
                  const SizedBox(height: 17),
                  _inputLabel('Confirm password'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _hideConfirmPassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: _fieldDecoration(
                      hint: 'Re-enter your password',
                      icon: Icons.verified_user_outlined,
                      suffix: IconButton(
                        tooltip: _hideConfirmPassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(() {
                          _hideConfirmPassword = !_hideConfirmPassword;
                        }),
                        icon: Icon(
                          _hideConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF73869A),
                          size: 20,
                        ),
                      ),
                    ),
                    validator: (value) => value != _passwordController.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                ],
                const SizedBox(height: 23),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isSignUp ? 'Create account' : 'Log in',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_isSignUp) ...[
            const SizedBox(height: 21),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F8FA),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFE2EFF2)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: _teal, size: 18),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          color: Color(0xFF536A7D),
                          fontSize: 12,
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(text: 'Demo access  '),
                          TextSpan(
                            text: 'demo@obelens.com',
                            style: TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: '\nPassword  '),
                          TextSpan(
                            text: 'Lens2026!',
                            style: TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _isSignUp ? 'Already have an account?' : 'New to OBE Lens?',
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    color: Color(0xFF73869A),
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _toggleMode(!_isSignUp),
                style: TextButton.styleFrom(
                  foregroundColor: _blue,
                  padding: const EdgeInsets.only(left: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _isSignUp ? 'Log in' : 'Create account',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeButton(
    String title, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF102A43).withOpacity(0.08),
                    blurRadius: 9,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: isSelected ? _ink : const Color(0xFF7B8B9B),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF8293A4), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: const TextStyle(color: Color(0xFF9AA8B6), fontSize: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFE4EAF0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFDC4454)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFDC4454), width: 1.5),
      ),
    );
  }
}
