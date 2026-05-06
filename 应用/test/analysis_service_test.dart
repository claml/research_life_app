import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';

void main() {
  group('AnalysisService', () {
    const service = AnalysisService();

    test('extracts tasks, people, and plans from weekly text', () {
      const input = AnalysisInput(
        rawText:
            '这周我完成了论文第二章资料整理，周三和王老师同步实验计划，周四和陈同学讨论数据方案。下周准备和导师开会确认框架，周末打算和朋友见面聊天。',
        sourceType: AnalysisSourceType.text,
      );

      final draft = service.analyze(input);

      expect(draft.tasks.length, greaterThanOrEqualTo(4));
      expect(draft.tasks.any((task) => task.type == EventType.plan), isTrue);
      expect(
        draft.persons.map((person) => person.name),
        containsAll(<String>['王老师', '陈同学', '导师', '朋友']),
      );
    });

    test('handles markdown list input', () {
      const input = AnalysisInput(
        rawText: '# 本周记录\n- 完成课程论文修改\n- 周五和李老师开会\n- 周末准备看展',
        sourceType: AnalysisSourceType.md,
      );

      final draft = service.analyze(input);

      expect(draft.tasks.length, 3);
      expect(draft.tasks.last.type, EventType.plan);
    });

    test('does not swallow context into generic role names', () {
      const input = AnalysisInput(
        rawText: '今天和老师讨论了实验的知识。',
        sourceType: AnalysisSourceType.text,
      );

      final draft = service.analyze(input);
      final personNames = draft.persons.map((person) => person.name).toList();

      expect(personNames, ['老师']);
      expect(draft.tasks.single.relatedPersonNames, ['老师']);
    });

    test(
      'keeps role detection stable when multiple people share one sentence',
      () {
        const input = AnalysisInput(
          rawText: '今天和王老师、陈同学一起讨论实验安排。',
          sourceType: AnalysisSourceType.text,
        );

        final draft = service.analyze(input);
        final rolesByName = {
          for (final person in draft.persons) person.name: person.role,
        };

        expect(rolesByName['王老师'], PersonRole.teacher);
        expect(rolesByName['陈同学'], PersonRole.classmate);
      },
    );

    test('keeps next week weekday hint instead of collapsing to next week', () {
      const input = AnalysisInput(
        rawText: '下周一和导师开会确认论文安排。',
        sourceType: AnalysisSourceType.text,
      );

      final draft = service.analyze(input);

      expect(draft.tasks, isNotEmpty);
      expect(draft.tasks.first.timeHint, '下周一');
    });

    test('keeps current-week weekday records out of plan bucket', () {
      const input = AnalysisInput(
        rawText: '周三和王老师同步实验计划，周四和陈同学讨论数据方案。',
        sourceType: AnalysisSourceType.text,
      );

      final draft = service.analyze(input);

      expect(draft.tasks, hasLength(2));
      expect(
        draft.tasks.map((task) => task.type),
        everyElement(EventType.record),
      );
      expect(
        draft.persons.map((person) => person.name),
        containsAll(<String>['王老师', '陈同学']),
      );
    });

    test('does not promote incidental 要 or 将 into plans', () {
      const input = AnalysisInput(
        rawText: '这周主要完成论文整理，将实验数据整理成图表。',
        sourceType: AnalysisSourceType.text,
      );

      final draft = service.analyze(input);

      expect(draft.tasks, hasLength(2));
      expect(
        draft.tasks.map((task) => task.type),
        everyElement(EventType.record),
      );
    });

    test('treats weekday with explicit 要 action as plan', () {
      const input = AnalysisInput(
        rawText: '周六要跑一个五公里。',
        sourceType: AnalysisSourceType.text,
      );

      final draft = service.analyze(input);

      expect(draft.tasks, hasLength(1));
      expect(draft.tasks.single.type, EventType.plan);
      expect(draft.tasks.single.timeHint, '周六');
      expect(draft.tasks.single.category, ItemCategory.health);
    });

    test('recognizes plan intent without treating all weekdays as future', () {
      const input = AnalysisInput(
        rawText: '我计划和导师开会确认框架，周末打算和朋友看展。',
        sourceType: AnalysisSourceType.text,
      );

      final draft = service.analyze(input);

      expect(draft.tasks, hasLength(2));
      expect(
        draft.tasks.map((task) => task.type),
        everyElement(EventType.plan),
      );
    });

    test('extracts people from 与 and 向 relationship phrases', () {
      const input = AnalysisInput(
        rawText: '下周与导师开会，明天向李老师请教文献。',
        sourceType: AnalysisSourceType.text,
      );

      final draft = service.analyze(input);
      final rolesByName = {
        for (final person in draft.persons) person.name: person.role,
      };

      expect(rolesByName.keys, containsAll(<String>['导师', '李老师']));
      expect(rolesByName['导师'], PersonRole.teacher);
      expect(rolesByName['李老师'], PersonRole.teacher);
      expect(
        draft.tasks.map((task) => task.type),
        everyElement(EventType.plan),
      );
    });
  });

  group('ImportService', () {
    const service = ImportService();

    test('rejects excel files with clear message', () async {
      final result = await service.importFile('D:/fake/sample.xlsx');

      expect(result.success, isFalse);
      expect(result.message, contains('Excel'));
    });

    test('rejects legacy doc files with clear message', () async {
      final result = await service.importFile('D:/fake/sample.doc');

      expect(result.success, isFalse);
      expect(result.message, contains('.docx'));
    });

    test('reads utf8 txt files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_test',
      );
      final file = File('${tempDir.path}/sample.txt');
      await file.writeAsString('这周完成了阅读笔记整理。');

      final result = await service.importFile(file.path);

      expect(result.success, isTrue);
      expect(result.input?.rawText, contains('阅读笔记'));

      await tempDir.delete(recursive: true);
    });

    test('reads text files with uppercase extensions', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_uppercase_extension_test',
      );
      final file = File('${tempDir.path}/sample.TXT');
      await file.writeAsString('这周完成了课程复习。');

      final result = await service.importFile(file.path);

      expect(result.success, isTrue);
      expect(result.input?.sourceType, AnalysisSourceType.txt);
      expect(result.input?.rawText, contains('课程复习'));

      await tempDir.delete(recursive: true);
    });

    test('reads docx files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_docx_test',
      );
      final file = File('${tempDir.path}/sample.docx');
      await file.writeAsBytes(_buildDocxBytes('第一段\n第二段'));

      final result = await service.importFile(file.path);

      expect(result.success, isTrue);
      expect(result.input?.sourceType, AnalysisSourceType.docx);
      expect(result.input?.rawText, contains('第一段'));
      expect(result.input?.rawText, contains('第二段'));

      await tempDir.delete(recursive: true);
    });

    test('rejects empty supported files', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_empty_import_test',
      );
      final file = File('${tempDir.path}/empty.md');
      await file.writeAsString('   \n\t');

      final result = await service.importFile(file.path);

      expect(result.success, isFalse);
      expect(result.message, contains('文件内容为空'));

      await tempDir.delete(recursive: true);
    });

    test('rejects damaged docx files with clear message', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_damaged_docx_test',
      );
      final file = File('${tempDir.path}/damaged.docx');
      await file.writeAsBytes(const [1, 2, 3, 4]);

      final result = await service.importFile(file.path);

      expect(result.success, isFalse);
      expect(result.message, contains('Word 文件读取失败'));

      await tempDir.delete(recursive: true);
    });
  });

  group('ReviewService', () {
    const reviewService = ReviewService();

    test('splits completed and planned tasks for preview', () {
      final draft = AnalysisDraft(
        id: 'draft_1',
        tasks: const [
          ExtractedTaskDraft(
            id: 't1',
            content: '完成实验整理',
            category: ItemCategory.work,
            type: EventType.record,
            confidence: 0.9,
          ),
          ExtractedTaskDraft(
            id: 't2',
            content: '下周和导师开会',
            category: ItemCategory.work,
            type: EventType.plan,
            confidence: 0.9,
          ),
        ],
        persons: const [
          ExtractedPersonDraft(
            id: 'p1',
            name: '导师',
            role: PersonRole.teacher,
            relatedTaskIndexes: [1],
          ),
        ],
        summary: '测试总结',
        warnings: const [],
        createdAt: DateTime(2026, 4, 20),
      );

      final preview = reviewService.buildPreview(draft);

      expect(preview.completedTasks, hasLength(1));
      expect(preview.plannedTasks, hasLength(1));
      expect(preview.relationLabels, contains('老师'));
    });
  });
}

Uint8List _buildDocxBytes(String text) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
'''),
    )
    ..addFile(
      ArchiveFile.string('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
'''),
    )
    ..addFile(
      ArchiveFile.string('word/document.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    ${text.split('\n').map((line) => '<w:p><w:r><w:t>$line</w:t></w:r></w:p>').join()}
  </w:body>
</w:document>
'''),
    );

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
