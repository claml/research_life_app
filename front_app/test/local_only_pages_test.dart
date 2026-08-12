import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active local pages do not import auth or cloud UI', () {
    for (final path in [
      'lib/features/files/my_files_page.dart',
      'lib/features/pdf_tools/pdf_tools_page.dart',
      'lib/features/agent/agent_page.dart',
      'lib/features/settings/settings_page.dart',
      'lib/features/reading/reading_page.dart',
      'lib/features/document_view/document_viewer_page.dart',
      'lib/features/notes/my_notes_page.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('AuthScope')), reason: path);
      expect(source, isNot(contains('AuthController')), reason: path);
      expect(source, isNot(contains('CloudFileExplorer')), reason: path);
      expect(source, isNot(contains('WorkspaceCloudPicker')), reason: path);
      expect(source, isNot(contains('SyncStatusPanel')), reason: path);
    }
  });

  test('notes refresh stays on the local library path', () {
    final notes = File(
      'lib/features/notes/my_notes_page.dart',
    ).readAsStringSync();

    expect(notes, contains('ensurePdfLibraryLoaded'));
    expect(notes, isNot(contains('refreshCloud')));
    expect(notes, isNot(contains('AuthScope')));
  });

  test('runtime startup does not wait for weather networking', () {
    final runtime = File('lib/app/local_app_runtime.dart').readAsStringSync();

    expect(runtime, isNot(contains('await controller.ensureWeatherLoaded()')));
  });

  test('research reading is a complete local-only surface', () {
    final reading = File(
      'lib/features/reading/reading_page.dart',
    ).readAsStringSync();
    final noteDialog = File(
      'lib/features/reading/reading_note_dialog.dart',
    ).readAsStringSync();

    expect(reading, contains('waitForPendingPdfPersistence'));
    expect(reading, isNot(contains('saveDocumentToCloud')));
    expect(reading, isNot(contains('CloudFileExplorer')));
    expect(reading, isNot(contains('AuthScope')));
    expect(reading, isNot(contains('云端')));
    expect(noteDialog, contains('保存到本机'));
    expect(noteDialog, isNot(contains('云端')));
  });

  test('document viewer reads only imported local documents', () {
    final viewer = File(
      'lib/features/document_view/document_viewer_page.dart',
    ).readAsStringSync();

    expect(viewer, contains('localViewableDocuments'));
    expect(viewer, contains('DocumentTextLoader.loadFromPath'));
    expect(viewer, isNot(contains('AuthScope')));
    expect(viewer, isNot(contains('WorkspaceCloudPicker')));
    expect(viewer, isNot(contains('CloudFileEntry')));
    expect(viewer, isNot(contains('云端')));
  });

  test('local file and PDF pages retain complete local actions', () {
    final files = File(
      'lib/features/files/my_files_page.dart',
    ).readAsStringSync();
    final pdf = File(
      'lib/features/pdf_tools/pdf_tools_page.dart',
    ).readAsStringSync();

    for (final label in ['导入', '重命名', '删除', '打开', 'PDF 操作']) {
      expect(files, contains(label));
    }
    expect(files, isNot(contains('云端')));
    expect(pdf, contains('选择本地 PDF'));
    expect(pdf, contains('选择保存文件夹'));
    expect(pdf, isNot(contains('请登录')));
    expect(pdf, isNot(contains('cloudServerId')));
  });

  test('Agent owns secure AI configuration and Settings stays local', () {
    final agent = File('lib/features/agent/agent_page.dart').readAsStringSync();
    final settings = File(
      'lib/features/settings/settings_page.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/state/research_life_controller.dart',
    ).readAsStringSync();
    final runtime = File('lib/app/local_app_runtime.dart').readAsStringSync();
    final researchWorkspace = File(
      'lib/features/workbench/research_workspace.dart',
    ).readAsStringSync();

    expect(agent, isNot(contains('ResearchLifeController')));
    expect(agent, isNot(contains('/api/v1/agent')));
    expect(agent, contains("Key('agent-settings')"));
    expect(agent, contains("Key('agent-api-key')"));
    expect(researchWorkspace, contains('AgentPage'));
    expect(settings, contains('LocalBackupPanel'));
    for (final forbiddenSource in [
      'AuthScope',
      '_RemoteLlmAnalysisPanel',
      '_LegacyRemoteLlmAnalysisPanel',
      'RemoteLlmAnalysisSettings',
      '_remoteLlmApiKeyController',
      'saveRemoteLlmAnalysisSettings(',
    ]) {
      expect(settings, isNot(contains(forbiddenSource)));
    }
    expect(settings, isNot(contains("id: 'agent.llm'")));
    expect(settings, isNot(contains('_AgentLlmPanel')));
    expect(settings, isNot(contains('controller.backupDatabase')));
    expect(settings, isNot(contains('_agentLlmApiKeyController')));
    expect(settings, isNot(contains('saveAgentLlmSettings(')));
    expect(controller, isNot(contains('AgentLlmSettings')));
    expect(controller, isNot(contains('requestOpenAiSettings')));
    expect(runtime, isNot(contains('clearLegacyAiSettings()')));
    for (final forbidden in ['登录', '退出登录', '云同步', '迁移到云端']) {
      expect(settings, isNot(contains(forbidden)));
    }
  });
}
