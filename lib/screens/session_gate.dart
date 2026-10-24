import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/ocr_service.dart';
import '../workflow/dashboard.dart';
import '../workflow/repository.dart';
import 'auth_screen.dart';
import 'password_screen.dart';

class SessionGate extends StatefulWidget {
  final AuthService auth;
  final WorkflowRepository repository;
  final BaseOcrService? ocrService;
  const SessionGate(
      {super.key,
      required this.auth,
      required this.repository,
      this.ocrService});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late bool _isAdmin = widget.auth.isAdmin;
  late bool _signedIn = widget.auth.hasSession;
  bool _recovery = false;
  late final StreamSubscription<SessionEvent> _subscription;
  @override
  void initState() {
    super.initState();
    _subscription = widget.auth.sessionEvents.listen((event) {
      if (mounted) {
        setState(() {
          if (_isAdmin != widget.auth.isAdmin) {
            _isAdmin = widget.auth.isAdmin;
            _navigatorKey = GlobalKey<NavigatorState>();
          }
          _signedIn = widget.auth.hasSession;
          if (event == SessionEvent.recovery) _recovery = true;
          if (!_signedIn) _recovery = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recovery) {
      return PasswordScreen(
          auth: widget.auth,
          recovery: true,
          onComplete: () async {
            await widget.auth.signOut();
            if (mounted) {
              setState(() {
                _recovery = false;
                _signedIn = false;
              });
            }
          });
    }
    if (!_signedIn) {
      return AuthScreen(
          authService: widget.auth,
          ocrService: widget.ocrService,
          onAuthenticated: () =>
              setState(() => _signedIn = widget.auth.hasSession));
    }
    // A dedicated authenticated navigator is disposed on sign-out/session loss.
    // Back cannot reveal protected pages after returning to login.
    return NavigatorPopHandler(
        onPop: () => _navigatorKey.currentState?.maybePop(),
        child: Navigator(
            key: _navigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => Dashboard(
                    repository: widget.repository,
                    isAdmin: widget.auth.isAdmin,
                    ocrService: widget.ocrService,
                    signOut: () async {
                      await widget.auth.signOut();
                      if (mounted) setState(() => _signedIn = false);
                    }))));
  }
}
