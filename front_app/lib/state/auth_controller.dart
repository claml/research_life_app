import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../services/auth/auth_api.dart';
import '../services/auth/auth_models.dart';
import '../services/auth/auth_token_store.dart';

enum AuthStatus {
  /// 启动中，读取本地 token
  initializing,

  /// 未登录且尚未选择进入方式，显示登录页
  awaitingChoice,

  /// 用户选择本地使用
  guest,

  /// 已登录云端
  authenticated,
}

class AuthController extends ChangeNotifier {
  /// 临时开关：启动时跳过登录页，直接以游客身份进入应用，
  /// 不再被登录页挡住其他功能。需要恢复登录时改为 false。
  final bool skipLoginOnStartup;

  AuthController({AuthTokenStore? tokenStore, this.skipLoginOnStartup = false})
    : _tokenStore = tokenStore ?? AuthTokenStore() {
    _apiClient = ApiClient(accessTokenReader: () => _cachedAccessToken);
    _authApi = AuthApi(_apiClient);
    unawaited(initialize());
  }

  static String? _cachedAccessToken;

  static String? get accessToken => _cachedAccessToken;

  final AuthTokenStore _tokenStore;
  late final ApiClient _apiClient;
  late final AuthApi _authApi;

  AuthStatus _status = AuthStatus.initializing;
  UserProfile? _user;
  String? _lastError;
  bool _busy = false;
  Future<bool>? _refreshInFlight;

  AuthStatus get status => _status;
  UserProfile? get user => _user;
  String? get lastError => _lastError;
  bool get busy => _busy;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isGuest => _status == AuthStatus.guest;
  bool get isAwaitingChoice => _status == AuthStatus.awaitingChoice;
  bool get hasEnteredApp =>
      _status == AuthStatus.guest || _status == AuthStatus.authenticated;
  bool get cloudSyncEnabled => isAuthenticated;

  Future<void> initialize() async {
    _status = AuthStatus.initializing;
    notifyListeners();

    final access = await _tokenStore.readAccessToken();
    final refresh = await _tokenStore.readRefreshToken();
    _cachedAccessToken = access;

    if (access == null || access.isEmpty) {
      _status = skipLoginOnStartup
          ? AuthStatus.guest
          : AuthStatus.awaitingChoice;
      notifyListeners();
      return;
    }

    try {
      _user = await _authApi.me();
      _status = AuthStatus.authenticated;
    } on ApiException catch (error) {
      if (error.code == 401 && refresh != null && refresh.isNotEmpty) {
        final refreshed = await _tryRefresh(refresh);
        if (!refreshed && _status == AuthStatus.initializing) {
          _status = skipLoginOnStartup
              ? AuthStatus.guest
              : AuthStatus.awaitingChoice;
        }
      } else {
        await _clearSession();
        _status = skipLoginOnStartup
            ? AuthStatus.guest
            : AuthStatus.awaitingChoice;
      }
    } catch (_) {
      await _clearSession();
      _status = skipLoginOnStartup
          ? AuthStatus.guest
          : AuthStatus.awaitingChoice;
    }
    notifyListeners();
  }

  Future<String?> login({
    required String username,
    required String password,
  }) async {
    return _runAuthAction(() async {
      final tokens = await _authApi.login(
        username: username.trim(),
        password: password,
      );
      await _applyTokens(tokens);
      _user = await _authApi.me();
      _status = AuthStatus.authenticated;
    });
  }

  Future<String?> register({
    required String username,
    required String password,
    String? email,
  }) async {
    return _runAuthAction(() async {
      await _authApi.registerOnly(
        username: username.trim(),
        password: password,
        email: email?.trim(),
      );
      final tokens = await _authApi.login(
        username: username.trim(),
        password: password,
      );
      await _applyTokens(tokens);
      _user = await _authApi.me();
      _status = AuthStatus.authenticated;
    });
  }

  Future<String?> logout() async {
    final refresh = await _tokenStore.readRefreshToken();
    try {
      if (_cachedAccessToken != null) {
        await _authApi.logout(refreshToken: refresh);
      }
    } on ApiException {
      // 本地仍清除会话
    } catch (_) {
      // ignore
    }
    await _clearSession();
    _status = AuthStatus.awaitingChoice;
    notifyListeners();
    return null;
  }

  void enterGuestMode() {
    _status = AuthStatus.guest;
    _lastError = null;
    notifyListeners();
  }

  Future<bool> refreshSessionAfterUnauthorized() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final refreshFuture = _refreshSessionAfterUnauthorized();
    _refreshInFlight = refreshFuture;
    return refreshFuture.whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _refreshSessionAfterUnauthorized() async {
    final refresh = await _tokenStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      // 游客或会话已清除：不退出应用到登录页，由调用方按普通失败处理。
      return false;
    }
    final refreshed = await _tryRefresh(refresh);
    notifyListeners();
    return refreshed;
  }

  Future<bool> _tryRefresh(String refreshToken) async {
    try {
      final tokens = await _authApi.refresh(refreshToken: refreshToken);
      await _applyTokens(tokens);
      _user = await _authApi.me();
      _status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (error) {
      if (error.code == 401 || error.code == 403 || error.code == 400) {
        await _clearSession();
        _status = AuthStatus.awaitingChoice;
      }
      // 网络或服务器临时错误：保留会话，不强制退出登录。
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyTokens(AuthTokens tokens) async {
    _cachedAccessToken = tokens.accessToken;
    await _tokenStore.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }

  Future<void> _clearSession() async {
    _cachedAccessToken = null;
    _user = null;
    await _tokenStore.clear();
  }

  Future<String?> _runAuthAction(Future<void> Function() action) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await action();
      return null;
    } on ApiException catch (error) {
      _lastError = error.message;
      return error.message;
    } catch (error) {
      _lastError = '$error';
      return '登录失败：$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
