class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: '${json['accessToken'] ?? ''}',
      refreshToken: '${json['refreshToken'] ?? ''}',
      expiresIn: _intValue(json['expiresIn']) ?? 0,
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.email,
    this.avatar,
  });

  final int id;
  final String username;
  final String? email;
  final String? avatar;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: _intValue(json['id']) ?? 0,
      username: '${json['username'] ?? ''}',
      email: json['email'] as String?,
      avatar: json['avatar'] as String?,
    );
  }
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
