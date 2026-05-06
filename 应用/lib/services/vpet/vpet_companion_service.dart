import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef VPetExitCallback = void Function();

class VPetCompanionService {
  VPetCompanionService({
    List<String> executableCandidates = defaultExecutableCandidates,
    this.ipcPort = defaultIpcPort,
  }) : _executableCandidates = executableCandidates;

  static const defaultIpcPort = 18765;

  static const defaultExecutableCandidates = <String>[
    r'D:\桌面\研究生活\VPet-main\VPet-Simulator.Windows\bin\x64\Release\net8.0-windows\VPet-Simulator.Windows.exe',
    r'D:\桌面\研究生活\VPet-main\VPet-Simulator.Windows\bin\x64\Release\VPet-Simulator.Windows.exe',
    r'D:\桌面\研究生活\VPet-main\VPet-Simulator.Windows\bin\x64\Debug\net8.0-windows\VPet-Simulator.Windows.exe',
    r'D:\桌面\研究生活\VPet-main\VPet-Simulator.Windows\bin\x64\Debug\VPet-Simulator.Windows.exe',
    r'D:\桌面\研究生活\应用\external\vpet\VPet-Simulator.Windows.exe',
  ];

  static const defaultPrefix = 'research_life';
  static const _requestTimeout = Duration(seconds: 3);

  final List<String> _executableCandidates;
  final int ipcPort;
  Process? _process;

  bool get isRunning => _process != null;
  int? get processId => _process?.pid;

  Future<String?> findDefaultExecutablePath() async {
    for (final candidate in _executableCandidates) {
      final file = File(candidate);
      if (await file.exists()) {
        return file.path;
      }
    }
    return null;
  }

  Future<void> launch({
    required String executablePath,
    String prefix = defaultPrefix,
    VPetExitCallback? onExit,
  }) async {
    if (_process != null) {
      return;
    }

    final executableFile = File(executablePath);
    if (!await executableFile.exists()) {
      throw FileSystemException('找不到 VPet 可执行文件', executablePath);
    }

    final process = await Process.start(executableFile.path, [
      'prefix#$prefix:|',
      'researchlife_ipc#$ipcPort:|',
    ], workingDirectory: executableFile.parent.path);
    _process = process;

    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.whenComplete(() {
        if (_process == process) {
          _process = null;
          onExit?.call();
        }
      }),
    );
  }

  Future<Map<String, Object?>> fetchStatus() {
    return _sendJson('GET', '/status');
  }

  Future<bool> waitUntilReady({
    Duration timeout = const Duration(seconds: 30),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await fetchStatus();
        if (status['ready'] == true) {
          return true;
        }
      } catch (_) {
        // VPet may still be starting; retry until the deadline.
      }

      await Future<void>.delayed(interval);
    }

    return false;
  }

  Future<void> say(
    String text, {
    bool force = true,
    String? graph,
    String? desc,
  }) async {
    await _sendJson(
      'POST',
      '/say',
      body: <String, Object?>{
        'text': text,
        'force': force,
        'graph': graph,
        'desc': desc,
      },
    );
  }

  Future<bool> requestClose() async {
    try {
      await _sendJson('POST', '/close');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stop() async {
    final process = _process;
    if (process == null) {
      return false;
    }

    if (await requestClose()) {
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_process == null) {
          return true;
        }
      }
    }

    if (_process == process) {
      _process = null;
    }
    return process.kill();
  }

  Future<Map<String, Object?>> _sendJson(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: ipcPort,
      path: path,
    );
    final client = HttpClient()..connectionTimeout = _requestTimeout;

    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(_requestTimeout);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(_requestTimeout);
      final rawBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < HttpStatus.ok ||
          response.statusCode >= HttpStatus.multipleChoices) {
        throw HttpException(
          rawBody.isEmpty ? 'VPet IPC 请求失败：${response.statusCode}' : rawBody,
          uri: uri,
        );
      }

      if (rawBody.trim().isEmpty) {
        return <String, Object?>{};
      }

      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
      }
      return <String, Object?>{};
    } finally {
      client.close(force: true);
    }
  }
}
