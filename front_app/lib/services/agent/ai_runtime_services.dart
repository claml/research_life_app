import '../../features/agent/state/agent_controller.dart';
import '../database/repositories/agent_chat_repository.dart';
import 'ai_credential_store.dart';
import 'ai_profile_repository.dart';
import 'openai_compatible_chat_client.dart';

final class AiRuntimeServices {
  const AiRuntimeServices({
    required this.profiles,
    required this.credentials,
    required this.chats,
    required this.client,
  });

  final AiProfileStore profiles;
  final AiCredentialStore credentials;
  final AgentChatStore chats;
  final OpenAiCompatibleChatClient client;

  AgentController createController() => AgentController(
    profiles: profiles,
    credentials: credentials,
    chats: chats,
    client: client,
  );
}
