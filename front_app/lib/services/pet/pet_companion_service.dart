import 'dart:convert';
import 'dart:io';

import '../storage/local_workspace_service.dart';

class PetCompanionService {
  const PetCompanionService({
    required LocalWorkspaceService localWorkspaceService,
  }) : _localWorkspaceService = localWorkspaceService;

  static const bundledSiam = PetDefinition(
    id: 'siam',
    displayName: 'Siam',
    description:
        'A tiny Siamese cat desk pet with cream fur, dark face mask, ears, paws, tail, and bright blue eyes.',
    spritesheetPath: 'assets/pets/siam/spritesheet.webp',
    source: PetSource.asset,
  );

  final LocalWorkspaceService _localWorkspaceService;

  Future<List<PetDefinition>> loadAvailablePets() async {
    final pets = <PetDefinition>[];
    final customDirectory = await _localWorkspaceService
        .resolveCustomPetsDirectory();

    await for (final entity in customDirectory.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final pet = await _tryLoadCustomPet(entity);
      if (pet != null && !pets.any((item) => item.id == pet.id)) {
        pets.add(pet);
      }
    }
    if (pets.isEmpty) {
      pets.add(bundledSiam);
    }
    pets.sort((left, right) => left.displayName.compareTo(right.displayName));
    return pets;
  }

  Future<PetDefinition> importPetDirectory(String sourceDirectoryPath) async {
    final sourceDirectory = Directory(sourceDirectoryPath);
    if (!await sourceDirectory.exists()) {
      throw const PetImportException('Pet folder does not exist.');
    }

    final manifest = File(
      '${sourceDirectory.path}${Platform.pathSeparator}pet.json',
    );
    if (!await manifest.exists()) {
      throw const PetImportException('The selected folder needs a pet.json.');
    }

    final rawManifest = await manifest.readAsString();
    final decoded = jsonDecode(rawManifest);
    if (decoded is! Map) {
      throw const PetImportException('pet.json is not a valid pet manifest.');
    }

    final pet = PetDefinition.fromJson(
      decoded.cast<String, Object?>(),
      sourceDirectory: sourceDirectory.path,
      source: PetSource.file,
    );
    final spritesheet = File(pet.spritesheetPath);
    if (!await spritesheet.exists()) {
      throw const PetImportException(
        'The pet manifest points to a missing spritesheet.',
      );
    }

    final targetRoot = await _localWorkspaceService
        .resolveCustomPetsDirectory();
    final targetDirectory = Directory(
      '${targetRoot.path}${Platform.pathSeparator}${_safePathSegment(pet.id)}',
    );
    await targetDirectory.create(recursive: true);

    final spritesheetName = _fileNameFromPath(spritesheet.path);
    final targetSpritesheetPath =
        '${targetDirectory.path}${Platform.pathSeparator}$spritesheetName';
    if (_normalizePath(spritesheet.path) !=
        _normalizePath(targetSpritesheetPath)) {
      await spritesheet.copy(targetSpritesheetPath);
    }
    final importedManifest = <String, Object?>{
      'id': pet.id,
      'displayName': pet.displayName,
      'description': pet.description,
      'spritesheetPath': spritesheetName,
    };
    await File(
      '${targetDirectory.path}${Platform.pathSeparator}pet.json',
    ).writeAsString(
      const JsonEncoder.withIndent('  ').convert(importedManifest),
    );

    final imported = await _tryLoadCustomPet(targetDirectory);
    if (imported == null) {
      throw const PetImportException('The copied pet package could not load.');
    }
    return imported;
  }

  Future<PetDefinition?> _tryLoadCustomPet(Directory directory) async {
    try {
      final manifest = File(
        '${directory.path}${Platform.pathSeparator}pet.json',
      );
      if (!await manifest.exists()) {
        return null;
      }
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final pet = PetDefinition.fromJson(
        decoded.cast<String, Object?>(),
        sourceDirectory: directory.path,
        source: PetSource.file,
      );
      if (!await File(pet.spritesheetPath).exists()) {
        return null;
      }
      return pet;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on PetImportException {
      return null;
    }
  }

  static String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('/', Platform.pathSeparator);
    final separatorIndex = normalized.lastIndexOf(Platform.pathSeparator);
    if (separatorIndex == -1 || separatorIndex == normalized.length - 1) {
      return normalized;
    }
    return normalized.substring(separatorIndex + 1);
  }

  static String _safePathSegment(String value) {
    final sanitized = value.trim().replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
      return 'pet';
    }
    return sanitized;
  }

  static String _normalizePath(String path) {
    return path
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll(RegExp(r'[\\/]+$'), '')
        .toLowerCase();
  }
}

enum PetSource { asset, file }

class PetDefinition {
  const PetDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.spritesheetPath,
    required this.source,
  });

  factory PetDefinition.fromJson(
    Map<String, Object?> json, {
    required String sourceDirectory,
    required PetSource source,
  }) {
    final id = _requiredString(json['id'], 'id');
    final displayName = _stringOrDefault(json['displayName'], id);
    final description = _stringOrDefault(json['description'], '');
    final rawSpritesheetPath = _requiredString(
      json['spritesheetPath'],
      'spritesheetPath',
    );
    final spritesheetPath = source == PetSource.asset
        ? rawSpritesheetPath
        : _resolveFilePath(sourceDirectory, rawSpritesheetPath);

    return PetDefinition(
      id: id,
      displayName: displayName,
      description: description,
      spritesheetPath: spritesheetPath,
      source: source,
    );
  }

  final String id;
  final String displayName;
  final String description;
  final String spritesheetPath;
  final PetSource source;

  bool get isAsset => source == PetSource.asset;

  static String _requiredString(Object? value, String fieldName) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw PetImportException('pet.json is missing $fieldName.');
  }

  static String _stringOrDefault(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static String _resolveFilePath(String sourceDirectory, String path) {
    final normalizedPath = path.replaceAll('/', Platform.pathSeparator);
    if (normalizedPath.contains(':') ||
        normalizedPath.startsWith(Platform.pathSeparator)) {
      return normalizedPath;
    }
    return '$sourceDirectory${Platform.pathSeparator}$normalizedPath';
  }
}

class PetImportException implements Exception {
  const PetImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
