import '../../core/network/api_client.dart';
import 'auth_models.dart';

class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  Future<AuthTokens> login({
    required String username,
    required String password,
  }) {
    return _client.postData<AuthTokens>(
      '/api/v1/user/login',
      data: {'username': username, 'password': password},
      fromJson: (json) => AuthTokens.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<AuthTokens> register({
    required String username,
    required String password,
    String? email,
  }) {
    return _client.postData<AuthTokens>(
      '/api/v1/user/register',
      data: {
        'username': username,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
      },
      fromJson: (_) {
        throw UnsupportedError('register returns no token body');
      },
    );
  }

  Future<void> registerOnly({
    required String username,
    required String password,
    String? email,
  }) async {
    await _client.postVoid(
      '/api/v1/user/register',
      data: {
        'username': username,
        'password': password,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
  }

  Future<AuthTokens> refresh({required String refreshToken}) {
    return _client.postData<AuthTokens>(
      '/api/v1/user/refresh',
      data: {'refreshToken': refreshToken},
      fromJson: (json) => AuthTokens.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<UserProfile> me() {
    return _client.getData<UserProfile>(
      '/api/v1/user/me',
      fromJson: (json) => UserProfile.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<void> logout({String? refreshToken}) {
    return _client.postVoid(
      '/api/v1/user/logout',
      headers: refreshToken == null || refreshToken.isEmpty
          ? null
          : {'X-Refresh-Token': refreshToken},
    );
  }
}
