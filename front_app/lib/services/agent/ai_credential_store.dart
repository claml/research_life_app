abstract interface class AiCredentialStore {
  Future<String?> read(String profileId);

  Future<void> write(String profileId, String secret);

  Future<void> delete(String profileId);

  Future<bool> has(String profileId);
}

final class AiCredentialException implements Exception {
  const AiCredentialException();

  static const message = 'Windows 凭据操作失败';

  @override
  String toString() => message;
}
