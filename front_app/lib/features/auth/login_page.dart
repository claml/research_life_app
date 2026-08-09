import 'package:flutter/material.dart';

import '../../app/auth_scope.dart';
import '../../core/config/api_config.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/auth_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController(text: 'admin123');
  final _emailController = TextEditingController();
  bool _isRegister = false;
  bool _obscurePassword = true;
  AuthController? _auth;
  bool _listeningToAuth = false;

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthScope.of(context);
    if (!_listeningToAuth) {
      _auth = auth;
      auth.addListener(_onAuthChanged);
      _listeningToAuth = true;
    }
  }

  void _onAuthChanged() {
    if (!mounted || _auth == null) {
      return;
    }
    if (_auth!.hasEnteredApp && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final auth = AuthScope.of(context);
    final username = _usernameController.text;
    final password = _passwordController.text;
    final message = _isRegister
        ? await auth.register(
            username: username,
            password: password,
            email: _emailController.text,
          )
        : await auth.login(username: username, password: password);
    if (!mounted) {
      return;
    }
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('登录成功，正在进入应用…')));
  }

  void _enterLocalMode() {
    AuthScope.of(context).enterGuestMode();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final auth = AuthScope.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tokens.backdropTop,
              tokens.backdropMiddle,
              tokens.backdropBottom,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: tokens.panelSurface,
                  borderRadius: BorderRadius.circular(tokens.radiusLarge),
                  border: Border.all(color: tokens.borderFaint),
                  boxShadow: tokens.shadowMd,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '研LIFE',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tokens.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '选择进入方式',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: auth.busy ? null : _enterLocalMode,
                              icon: const Icon(Icons.offline_bolt_outlined),
                              label: const Text('本地使用'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: auth.busy ? null : _submit,
                              icon: auth.busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_outlined),
                              label: Text(_isRegister ? '注册并登录' : '云端登录'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '本地使用：无需账号，数据仅存本机；云端登录：启用文献与批注同步',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        _isRegister ? '注册云端账号' : '云端账号',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().length < 3) {
                            return '用户名至少 3 个字符';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_isRegister) ...[
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: '邮箱（可选）',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: '密码',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return '密码至少 6 位';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: auth.busy
                            ? null
                            : () => setState(() => _isRegister = !_isRegister),
                        child: Text(_isRegister ? '已有账号？去登录' : '没有账号？注册'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'API：${ApiConfig.baseUrl}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
