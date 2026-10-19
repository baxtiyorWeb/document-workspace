import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/models/auth_state.dart';

void main() {
  group('UserProfile Model Tests', () {
    test('UserProfile json serialization and deserialization', () {
      final json = {
        'id': 'user-100',
        'email': 'user@example.com',
        'full_name': 'Sardor Rahimov',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'user-100');
      expect(profile.email, 'user@example.com');
      expect(profile.fullName, 'Sardor Rahimov');

      final encoded = profile.toJson();
      expect(encoded['id'], 'user-100');
      expect(encoded['email'], 'user@example.com');
      expect(encoded['full_name'], 'Sardor Rahimov');
    });
  });

  group('AuthState Model Tests', () {
    test('AuthState initial state and copyWith', () {
      const initial = AuthState();

      expect(initial.isAuthenticated, isFalse);
      expect(initial.isLoading, isTrue);
      expect(initial.user, isNull);
      expect(initial.accessToken, isNull);

      const user = UserProfile(
        id: 'u-1',
        email: 'test@example.com',
        fullName: 'Test User',
      );

      final loggedIn = initial.copyWith(
        isAuthenticated: true,
        isLoading: false,
        accessToken: 'access-token-xyz',
        user: user,
      );

      expect(loggedIn.isAuthenticated, isTrue);
      expect(loggedIn.isLoading, isFalse);
      expect(loggedIn.accessToken, 'access-token-xyz');
      expect(loggedIn.user?.fullName, 'Test User');
    });
  });
}
