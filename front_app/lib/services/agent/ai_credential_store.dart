import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ai_profile.dart';

abstract interface class AiCredentialStore {
  Future<String?> read(String profileId);

  Future<void> write(String profileId, String secret);

  Future<void> delete(String profileId);

  Future<bool> has(String profileId);
}

/// Returns a non-secret, Windows-target-safe identity for one provider slot.
///
/// Preset providers keep one credential per profile/provider. Custom services
/// also bind the credential to the normalized endpoint so a key cannot cross
/// custom service boundaries.
String aiCredentialId(AiProviderProfile profile) {
  final provider = profile.provider.trim().toLowerCase();
  if (provider != 'custom') {
    final safeProvider = RegExp(r'^[a-z0-9._-]+$').hasMatch(provider)
        ? provider
        : sha256.convert(utf8.encode(provider)).toString().substring(0, 24);
    return '${profile.id}--$safeProvider';
  }
  final endpoint = _normalizedCredentialEndpoint(profile.baseUrl);
  final fingerprint = sha256.convert(utf8.encode(endpoint)).toString();
  return '${profile.id}--custom-${fingerprint.substring(0, 24)}';
}

String _normalizedCredentialEndpoint(String rawBaseUrl) {
  final uri = Uri.parse(rawBaseUrl.trim());
  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return uri
      .replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        path: path,
        fragment: '',
      )
      .toString();
}

final class AiCredentialException implements Exception {
  const AiCredentialException();

  static const message = 'Windows 凭据操作失败';

  @override
  String toString() => message;
}
