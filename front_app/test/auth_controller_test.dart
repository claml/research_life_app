import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/auth/auth_token_store.dart';
import 'package:research_life/state/auth_controller.dart';

class _EmptyTokenStore extends AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthController.refreshSessionAfterUnauthorized', () {
    test('guest mode with no tokens does not log out', () async {
      final controller = AuthController(tokenStore: _EmptyTokenStore());
      await Future<void>.delayed(Duration.zero);
      controller.enterGuestMode();
      expect(controller.isGuest, isTrue);

      final refreshed = await controller.refreshSessionAfterUnauthorized();

      expect(refreshed, isFalse);
      expect(controller.isGuest, isTrue);
      expect(controller.isAwaitingChoice, isFalse);
      controller.dispose();
    });

    test('stays on login page when refresh token is missing', () async {
      final controller = AuthController(tokenStore: _EmptyTokenStore());
      await Future<void>.delayed(Duration.zero);
      expect(controller.isAwaitingChoice, isTrue);

      final refreshed = await controller.refreshSessionAfterUnauthorized();

      expect(refreshed, isFalse);
      expect(controller.isAwaitingChoice, isTrue);
      controller.dispose();
    });
  });
}
