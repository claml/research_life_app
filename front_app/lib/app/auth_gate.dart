import 'package:flutter/material.dart';

import '../features/auth/login_page.dart';
import '../state/auth_controller.dart';
import 'auth_scope.dart';
import 'app_shell.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.read(context);

    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        switch (auth.status) {
          case AuthStatus.initializing:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthStatus.awaitingChoice:
            return const LoginPage();
          case AuthStatus.guest:
          case AuthStatus.authenticated:
            return const AppShell();
        }
      },
    );
  }
}
