import 'dart:io';

import 'package:path/path.dart' as p;

import 'local_data_operation_coordinator.dart';
import 'local_file_library_store.dart';
import 'local_workspace_service.dart';

class LocalFolderException implements Exception {
  const LocalFolderException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class LocalFolderService {
  const LocalFolderService({
    required LocalWorkspaceService workspaceService,
    required LocalFileLibraryStore store,
    required LocalDataOperationCoordinator operationCoordinator,
  }) : _workspaceService = workspaceService,
       _store = store,
       _operationCoordinator = operationCoordinator;

  final LocalWorkspaceService _workspaceService;
  final LocalFileLibraryStore _store;
  final LocalDataOperationCoordinator _operationCoordinator;

  Future<Directory> renameFolder({
    required Directory folder,
    required String newName,
  }) {
    return _operationCoordinator.runExclusive(
      () => _renameFolder(folder: folder, newName: newName),
    );
  }

  Future<Directory> _renameFolder({
    required Directory folder,
    required String newName,
  }) async {
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty ||
        normalizedName == '.' ||
        normalizedName == '..' ||
        normalizedName.contains('/') ||
        normalizedName.contains('\\')) {
      throw const LocalFolderException('文件夹名称无效。');
    }
    if (!await folder.exists()) {
      throw LocalFolderException(
        '文件夹不存在。',
        cause: FileSystemException('文件夹不存在', folder.path),
      );
    }

    final payloads = await _workspaceService
        .resolveManagedFilePayloadsDirectory(create: false);
    final payloadRoot = p.normalize(p.absolute(payloads.path));
    final originalPath = p.normalize(p.absolute(folder.path));
    if (p.equals(originalPath, payloadRoot) ||
        !p.isWithin(payloadRoot, originalPath)) {
      throw const LocalFolderException('只能重命名资料库中的子文件夹。');
    }

    final destinationPath = p.join(p.dirname(originalPath), normalizedName);
    if (p.equals(originalPath, destinationPath)) {
      return Directory(originalPath);
    }
    if (await FileSystemEntity.type(destinationPath) !=
        FileSystemEntityType.notFound) {
      throw const LocalFolderException('同名文件夹已存在。');
    }

    final documents = await _store.loadDocuments(includeDeleted: true);
    final replacements = <String, String>{};
    for (final document in documents) {
      final documentPath = p.normalize(p.absolute(document.path));
      if (p.equals(documentPath, originalPath) ||
          p.isWithin(originalPath, documentPath)) {
        replacements[document.id] = p.join(
          destinationPath,
          p.relative(documentPath, from: originalPath),
        );
      }
    }

    Directory? renamed;
    try {
      renamed = await Directory(originalPath).rename(destinationPath);
      await _store.replaceDocumentPaths(replacements);
      return renamed;
    } catch (error) {
      Object? rollbackError;
      if (renamed != null &&
          await renamed.exists() &&
          !await Directory(originalPath).exists()) {
        try {
          await renamed.rename(originalPath);
        } catch (failure) {
          rollbackError = failure;
        }
      }
      if (rollbackError != null) {
        throw LocalFolderException('文件夹重命名失败，且未能恢复原目录。', cause: rollbackError);
      }
      throw LocalFolderException('文件夹重命名失败，已恢复原目录。', cause: error);
    }
  }
}
