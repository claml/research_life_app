import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/agent/ai_credential_store.dart';
import 'package:research_life/services/agent/ai_profile.dart';
import 'package:research_life/services/agent/windows_ai_credential_store.dart';
import 'package:win32/win32.dart';

void main() {
  late RecordingCredentialPlatformApi platform;
  late WindowsAiCredentialStore store;

  setUp(() {
    platform = RecordingCredentialPlatformApi();
    store = WindowsAiCredentialStore(platform: platform);
  });

  test('stores credentials at the stable app target', () async {
    await store.write('primary', 'secret-value');

    expect(platform.lastTarget, 'research-life-app/ai/primary');
    expect(await store.read('primary'), 'secret-value');

    await store.delete('primary');

    expect(await store.read('primary'), isNull);
  });

  test('has reflects whether the stable target has a credential', () async {
    expect(await store.has('primary'), isFalse);

    await store.write('primary', 'secret-value');

    expect(await store.has('primary'), isTrue);
  });

  test('credential identities isolate providers and custom endpoints', () {
    const openAi = AiProviderProfile(
      id: 'primary',
      provider: 'openai',
      displayName: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'model-a',
      requiresCredential: true,
    );
    const deepSeek = AiProviderProfile(
      id: 'primary',
      provider: 'deepseek',
      displayName: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'model-b',
      requiresCredential: true,
    );
    const customA = AiProviderProfile(
      id: 'primary',
      provider: 'custom',
      displayName: 'Custom',
      baseUrl: 'https://one.example/v1/',
      model: 'model-c',
      requiresCredential: true,
    );
    const customB = AiProviderProfile(
      id: 'primary',
      provider: 'custom',
      displayName: 'Custom',
      baseUrl: 'https://two.example/v1',
      model: 'model-c',
      requiresCredential: true,
    );

    expect(aiCredentialId(openAi), isNot(aiCredentialId(deepSeek)));
    expect(aiCredentialId(customA), isNot(aiCredentialId(customB)));
    expect(aiCredentialId(customA), matches(r'^[A-Za-z0-9._-]+$'));
  });

  test('rejects blank secrets before calling Windows', () async {
    await expectLater(store.write('primary', '   '), throwsArgumentError);

    expect(platform.writeCount, 0);
  });

  test('rejects a profile id that could inject another target', () async {
    await expectLater(
      store.write('primary/other', 'secret-value'),
      throwsArgumentError,
    );

    expect(platform.callCount, 0);
  });

  test(
    'maps an absent Windows credential to null and a delete no-op',
    () async {
      platform.readFailure = CredentialPlatformException(ERROR_NOT_FOUND);
      platform.deleteFailure = CredentialPlatformException(ERROR_NOT_FOUND);

      expect(await store.read('primary'), isNull);
      expect(await store.has('primary'), isFalse);
      await store.delete('primary');
    },
  );

  test('sanitizes unexpected Windows failures', () async {
    platform.writeFailure = CredentialPlatformException(ERROR_ACCESS_DENIED);

    await expectLater(
      store.write('primary', 'secret-value'),
      throwsA(
        isA<AiCredentialException>()
            .having(
              (exception) => exception.toString(),
              'message',
              'Windows 凭据操作失败',
            )
            .having(
              (exception) => exception.toString(),
              'does not expose target',
              isNot(contains('primary')),
            )
            .having(
              (exception) => exception.toString(),
              'does not expose secret',
              isNot(contains('secret-value')),
            ),
      ),
    );
  });

  test('sanitizes malformed credential data from Windows', () async {
    platform.readFailure = const FormatException(
      'CredentialBlob for research-life-app/ai/primary: secret-value',
    );

    await expectLater(
      store.read('primary'),
      throwsA(
        isA<AiCredentialException>().having(
          (exception) => exception.toString(),
          'message',
          'Windows 凭据操作失败',
        ),
      ),
    );
  });
}

final class RecordingCredentialPlatformApi implements CredentialPlatformApi {
  final Map<String, String> _credentials = {};

  Object? readFailure;
  Object? writeFailure;
  Object? deleteFailure;
  String? lastTarget;
  int writeCount = 0;
  int callCount = 0;

  @override
  String? read(String target) {
    callCount++;
    lastTarget = target;
    final failure = readFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, StackTrace.empty);
    }
    return _credentials[target];
  }

  @override
  void write(String target, String secret) {
    callCount++;
    writeCount++;
    lastTarget = target;
    final failure = writeFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, StackTrace.empty);
    }
    _credentials[target] = secret;
  }

  @override
  void delete(String target) {
    callCount++;
    lastTarget = target;
    final failure = deleteFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, StackTrace.empty);
    }
    _credentials.remove(target);
  }
}
