import 'package:drift/drift.dart';

import '../../agent/agent_models.dart' as domain;
import '../../storage/local_data_operation_coordinator.dart';
import '../app_database.dart' as db;

class AgentChatRepository {
  const AgentChatRepository(
    this._database, {
    required LocalDataOperationCoordinator operationCoordinator,
  }) : _operationCoordinator = operationCoordinator;

  final db.AppDatabase _database;
  final LocalDataOperationCoordinator _operationCoordinator;

  Future<domain.AgentChatSession> createSession({
    required String profileId,
    required String model,
    required String title,
  }) {
    return _operationCoordinator.runExclusive(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await _database
          .into(_database.agentChatSessions)
          .insert(
            db.AgentChatSessionsCompanion.insert(
              title: title,
              profileId: profileId,
              model: model,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return _sessionById(id);
    });
  }

  Future<List<domain.AgentChatSession>> listSessions() async {
    final rows =
        await (_database.select(_database.agentChatSessions)..orderBy([
              (session) => OrderingTerm(
                expression: session.updatedAt,
                mode: OrderingMode.desc,
              ),
              (session) =>
                  OrderingTerm(expression: session.id, mode: OrderingMode.desc),
            ]))
            .get();
    return rows.map(_sessionFromRow).toList(growable: false);
  }

  Future<List<domain.AgentChatMessage>> listMessages(int sessionId) async {
    final rows =
        await (_database.select(_database.agentChatMessages)
              ..where((message) => message.sessionId.equals(sessionId))
              ..orderBy([
                (message) => OrderingTerm.asc(message.createdAt),
                (message) => OrderingTerm.asc(message.id),
              ]))
            .get();
    return rows.map(_messageFromRow).toList(growable: false);
  }

  Future<domain.AgentChatMessage> appendMessage({
    required int sessionId,
    required String role,
    required String content,
    String? reasoningContent,
    String? model,
  }) {
    return _operationCoordinator.runExclusive(() async {
      final id = await _database
          .into(_database.agentChatMessages)
          .insert(
            db.AgentChatMessagesCompanion.insert(
              sessionId: sessionId,
              role: role,
              content: content,
              reasoningContent: Value(reasoningContent),
              model: Value(model),
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      return _messageById(id);
    });
  }

  Future<domain.AgentChatSession> updateSessionAfterReply({
    required int sessionId,
    String? title,
    String? model,
  }) {
    return _operationCoordinator.runExclusive(() async {
      await (_database.update(
        _database.agentChatSessions,
      )..where((session) => session.id.equals(sessionId))).write(
        db.AgentChatSessionsCompanion(
          title: title == null ? const Value.absent() : Value(title),
          model: model == null ? const Value.absent() : Value(model),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      return _sessionById(sessionId);
    });
  }

  Future<void> deleteSession(int sessionId) {
    return _operationCoordinator.runExclusive(() async {
      await _database.transaction(() async {
        await (_database.delete(
          _database.agentChatMessages,
        )..where((message) => message.sessionId.equals(sessionId))).go();
        await (_database.delete(
          _database.agentChatSessions,
        )..where((session) => session.id.equals(sessionId))).go();
      });
    });
  }

  Future<domain.AgentChatSession> _sessionById(int id) async {
    final row = await (_database.select(
      _database.agentChatSessions,
    )..where((session) => session.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('Agent chat session $id does not exist.');
    }
    return _sessionFromRow(row);
  }

  Future<domain.AgentChatMessage> _messageById(int id) async {
    final row = await (_database.select(
      _database.agentChatMessages,
    )..where((message) => message.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('Agent chat message $id does not exist.');
    }
    return _messageFromRow(row);
  }

  domain.AgentChatSession _sessionFromRow(db.AgentChatSession row) {
    return domain.AgentChatSession(
      id: row.id,
      title: row.title,
      profileId: row.profileId,
      model: row.model,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    );
  }

  domain.AgentChatMessage _messageFromRow(db.AgentChatMessage row) {
    return domain.AgentChatMessage(
      id: row.id,
      sessionId: row.sessionId,
      role: row.role,
      content: row.content,
      reasoningContent: row.reasoningContent,
      model: row.model,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    );
  }
}
