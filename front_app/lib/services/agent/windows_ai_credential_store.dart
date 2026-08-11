import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'ai_credential_store.dart';

abstract interface class CredentialPlatformApi {
  String? read(String target);

  void write(String target, String secret);

  void delete(String target);
}

final class CredentialPlatformException implements Exception {
  const CredentialPlatformException(this.errorCode);

  final int errorCode;
}

final class WindowsAiCredentialStore implements AiCredentialStore {
  WindowsAiCredentialStore({CredentialPlatformApi? platform})
    : _platform = platform ?? Win32CredentialPlatformApi();

  static final _validProfileId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  final CredentialPlatformApi _platform;

  @override
  Future<String?> read(String profileId) async {
    final target = _targetFor(profileId);
    try {
      return _platform.read(target);
    } on CredentialPlatformException catch (error) {
      if (error.errorCode == ERROR_NOT_FOUND) {
        return null;
      }
      throw const AiCredentialException();
    } catch (_) {
      throw const AiCredentialException();
    }
  }

  @override
  Future<void> write(String profileId, String secret) async {
    final target = _targetFor(profileId);
    if (secret.trim().isEmpty) {
      throw ArgumentError.value(secret, 'secret', 'must not be blank');
    }
    try {
      _platform.write(target, secret);
    } on CredentialPlatformException {
      throw const AiCredentialException();
    } catch (_) {
      throw const AiCredentialException();
    }
  }

  @override
  Future<void> delete(String profileId) async {
    final target = _targetFor(profileId);
    try {
      _platform.delete(target);
    } on CredentialPlatformException catch (error) {
      if (error.errorCode != ERROR_NOT_FOUND) {
        throw const AiCredentialException();
      }
    } catch (_) {
      throw const AiCredentialException();
    }
  }

  @override
  Future<bool> has(String profileId) async => await read(profileId) != null;

  String _targetFor(String profileId) {
    if (!_validProfileId.hasMatch(profileId)) {
      throw ArgumentError.value(profileId, 'profileId', 'must be a safe id');
    }
    return 'research-life-app/ai/$profileId';
  }
}

final class Win32CredentialPlatformApi implements CredentialPlatformApi {
  @override
  String? read(String target) {
    return using((arena) {
      final credentialPointer = arena<Pointer<CREDENTIAL>>();
      try {
        final result = CredRead(
          arena.pcwstr(target),
          CRED_TYPE_GENERIC,
          credentialPointer,
        );
        if (!result.value) {
          throw CredentialPlatformException(result.error);
        }
        final credential = credentialPointer.value.ref;
        final blob = credential.CredentialBlob.asTypedList(
          credential.CredentialBlobSize,
        );
        return utf8.decode(blob);
      } finally {
        if (!credentialPointer.value.isNull) {
          CredFree(credentialPointer.value);
        }
      }
    });
  }

  @override
  void write(String target, String secret) {
    using((arena) {
      final bytes = utf8.encode(secret);
      final credential = arena<CREDENTIAL>();
      credential.ref
        ..Type = CRED_TYPE_GENERIC
        ..TargetName = arena.pwstr(target)
        ..Persist = CRED_PERSIST_LOCAL_MACHINE
        ..CredentialBlob = bytes.toNative(allocator: arena)
        ..CredentialBlobSize = bytes.length;
      final result = CredWrite(credential, 0);
      if (!result.value) {
        throw CredentialPlatformException(result.error);
      }
    });
  }

  @override
  void delete(String target) {
    using((arena) {
      final result = CredDelete(arena.pcwstr(target), CRED_TYPE_GENERIC);
      if (!result.value) {
        throw CredentialPlatformException(result.error);
      }
    });
  }
}
