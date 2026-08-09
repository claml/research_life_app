import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/export/consulting_package_service.dart';

void main() {
  group('ConsultingPackageService', () {
    test(
      'exports sanitized package without sqlite, preferences, pdf, or real data directories',
      () async {
        final projectRoot = await Directory.systemTemp.createTemp(
          'research_life_consulting_package_test',
        );
        addTearDown(() => projectRoot.delete(recursive: true));

        await _writeFile(projectRoot, 'pubspec.yaml', 'name: research_life\n');
        await _writeFile(projectRoot, 'README.md', '# Research Life\n');
        await _writeFile(projectRoot, 'lib/main.dart', 'void main() {}\n');
        await _writeFile(
          projectRoot,
          'lib/services/private.sqlite',
          'sqlite in lib should not export',
        );
        await _writeFile(
          projectRoot,
          'test/service_test.dart',
          'void main() {}\n',
        );
        await _writeFile(
          projectRoot,
          'test/fixture.pdf',
          '%PDF real fixture should not export',
        );
        await _writeFile(projectRoot, 'docs/architecture.md', '# Arch\n');
        await _writeFile(
          projectRoot,
          'docs/private.pdf',
          '%PDF real document should not export',
        );
        await _writeFile(
          projectRoot,
          '.research_life/research_life.sqlite',
          '真实周记：张三和李四讨论论文',
        );
        await _writeFile(
          projectRoot,
          '.research_life/preferences.json',
          '{"private":true}',
        );
        await _writeFile(projectRoot, 'preferences.json', '{"private":true}');
        await _writeFile(projectRoot, '资料/真实论文.pdf', '%PDF sensitive paper');
        await _writeFile(projectRoot, 'home_images/private.png', 'image');
        await _writeFile(
          projectRoot,
          'legacy_desktop_pet/private.txt',
          'legacy pet data',
        );
        await _writeFile(projectRoot, '桌宠形象/private.png', 'pet image');
        await _writeFile(projectRoot, 'build/app.bin', 'build output');
        await _writeFile(projectRoot, '.dart_tool/package_config.json', '{}');
        await _writeFile(projectRoot, 'docs/run.log', 'log output');

        final outputDirectory = Directory(
          '${projectRoot.path}${Platform.pathSeparator}exports',
        );
        final service = ConsultingPackageService(
          projectRoot: projectRoot,
          clock: () => DateTime(2026, 5, 13, 10, 11, 12),
        );

        final result = await service.exportPackage(
          outputDirectory: outputDirectory,
        );

        expect(
          result.packageFile.path,
          endsWith('research_life_consulting_2026-05-13_101112.zip'),
        );

        final archive = ZipDecoder().decodeBytes(
          await result.packageFile.readAsBytes(),
        );
        final names = archive.files.map((file) => file.name).toSet();
        final allText = archive.files
            .where((file) => file.isFile)
            .map((file) => utf8.decode(file.content, allowMalformed: true))
            .join('\n');

        expect(names, contains('pubspec.yaml'));
        expect(names, contains('README.md'));
        expect(names, contains('lib/main.dart'));
        expect(names, contains('test/service_test.dart'));
        expect(names, contains('docs/architecture.md'));
        expect(names, contains(ConsultingPackageService.contextFileName));

        expect(names.any((name) => name.contains('.research_life')), isFalse);
        expect(names.any((name) => name.endsWith('.sqlite')), isFalse);
        expect(names.any((name) => name.endsWith('.sqlite-wal')), isFalse);
        expect(names.any((name) => name.endsWith('.sqlite-shm')), isFalse);
        expect(names, isNot(contains('preferences.json')));
        expect(
          names.any((name) => name.toLowerCase().endsWith('.pdf')),
          isFalse,
        );
        expect(names.any((name) => name.startsWith('资料/')), isFalse);
        expect(names.any((name) => name.startsWith('home_images/')), isFalse);
        expect(
          names.any((name) => name.startsWith('legacy_desktop_pet/')),
          isFalse,
        );
        expect(names.any((name) => name.startsWith('桌宠形象/')), isFalse);
        expect(names.any((name) => name.startsWith('build/')), isFalse);
        expect(names.any((name) => name.startsWith('.dart_tool/')), isFalse);
        expect(
          names.any((name) => name.toLowerCase().endsWith('.log')),
          isFalse,
        );
        expect(allText, isNot(contains('真实周记')));
        expect(allText, isNot(contains('张三')));
        expect(allText, isNot(contains('敏感')));
      },
    );
  });
}

Future<void> _writeFile(
  Directory root,
  String relativePath,
  String content,
) async {
  final file = File(
    '${root.path}${Platform.pathSeparator}'
    '${relativePath.replaceAll('/', Platform.pathSeparator)}',
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
