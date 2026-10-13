import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthService {
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
