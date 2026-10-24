import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

enum SessionEvent { changed, recovery }

abstract interface class AuthService {
  bool get hasSession;
  bool get isAdmin;
  Stream<SessionEvent> get sessionEvents;
  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<void> updatePassword(String password);
  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  });
}

class SupabaseAuthService implements AuthService {
  const SupabaseAuthService();

  @override
  bool get hasSession => Supabase.instance.client.auth.currentSession != null;
  @override
  bool get isAdmin =>
      Supabase.instance.client.auth.currentUser?.appMetadata['role'] == 'admin';
  @override
  Stream<SessionEvent> get sessionEvents =>
      Supabase.instance.client.auth.onAuthStateChange.map((state) =>
          state.event == AuthChangeEvent.passwordRecovery
              ? SessionEvent.recovery
              : SessionEvent.changed);
  @override
  Future<void> signOut() => Supabase.instance.client.auth.signOut();
  @override
  Future<void> resetPassword(String email) =>
      Supabase.instance.client.auth.resetPasswordForEmail(email,
          redirectTo: kIsWeb
              ? Uri.base.replace(fragment: '', query: '').toString()
              : 'com.obelens.app://auth-callback/');
  @override
  Future<void> updatePassword(String password) async {
    await Supabase.instance.client.auth
        .updateUser(UserAttributes(password: password));
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
    return response.session != null;
  }
}
