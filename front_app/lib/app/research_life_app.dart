import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_tokens.dart';
import '../features/pin_lock/pin_lock_gate.dart';
import '../services/storage/backup_service.dart';
import 'app_window_frame.dart';
import 'local_app_runtime.dart';
import 'local_services_scope.dart';
import 'research_life_scope.dart';
import 'workbench_shell.dart';

class ResearchLifeApp extends StatefulWidget {
  const ResearchLifeApp({
    super.key,
    this.runtimeFactory,
    this.runtimeContentBuilder,
  });

  final LocalAppRuntimeFactory? runtimeFactory;
  final Widget Function(BuildContext context, AppRuntime runtime)?
  runtimeContentBuilder;

  @override
  State<ResearchLifeApp> createState() => _ResearchLifeAppState();
}

class _ResearchLifeAppState extends State<ResearchLifeApp> {
  static const _nativeLifecycleChannel = MethodChannel(
    'research_life/window_lifecycle',
  );

  late final LocalAppRuntimeFactory _runtimeFactory;
  late final AppLifecycleListener _appLifecycleListener;
  AppRuntime? _runtime;
  Object? _startupError;
  Future<void>? _shutdownFuture;
  Future<void>? _runtimeTransition;
  bool _restarting = false;
  bool _exitRequested = false;

  @override
  void initState() {
    super.initState();
    _runtimeFactory =
        widget.runtimeFactory ??
        (restoreRuntime) => LocalAppRuntime.open(
          restoreRuntime: restoreRuntime,
          requestExit: _requestGracefulExit,
        );
    _appLifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequested,
    );
    _nativeLifecycleChannel.setMethodCallHandler(_handleNativeLifecycleCall);
    unawaited(_openInitialRuntime());
  }

  Future<void> _openInitialRuntime() {
    if (_exitRequested) {
      return Future<void>.value();
    }
    return _trackRuntimeTransition(_performInitialOpen());
  }

  Future<void> _performInitialOpen() async {
    try {
      final runtime = await _runtimeFactory(_restoreAndRestart);
      if (!mounted || _exitRequested) {
        await runtime.close();
        return;
      }
      setState(() {
        _runtime = runtime;
        _startupError = null;
      });
    } catch (error) {
      if (mounted && !_exitRequested) {
        setState(() => _startupError = error);
      }
    }
  }

  Future<BackupRestoreResult> _restoreAndRestart(Directory backupDirectory) {
    final current = _runtime;
    if (current == null || _restarting || _exitRequested) {
      return Future<BackupRestoreResult>.error(
        const BackupRestoreException('本地运行时正在切换，请稍后重试。'),
      );
    }

    _restarting = true;
    return _trackRuntimeTransition(
      _performRestoreAndRestart(current, backupDirectory),
    ).whenComplete(() => _restarting = false);
  }

  Future<BackupRestoreResult> _performRestoreAndRestart(
    AppRuntime current,
    Directory backupDirectory,
  ) async {
    // Preflight failure leaves the old runtime alive and installed. Opening a
    // second database over the same workspace would violate ownership.
    await current.flushLocalPersistence();
    if (_exitRequested) {
      throw const BackupRestoreException('应用正在退出，已取消恢复。');
    }

    if (mounted) {
      setState(() => _runtime = null);
    } else {
      _runtime = null;
    }
    try {
      await current.close();
      final restored = await current.restoreBackup(backupDirectory);
      final replacement = await _runtimeFactory(_restoreAndRestart);
      if (!mounted || _exitRequested) {
        await replacement.close();
        return restored;
      }
      setState(() {
        _runtime = replacement;
        _startupError = null;
      });
      return restored;
    } catch (error, stackTrace) {
      if (!mounted || _exitRequested) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      try {
        final recovery = await _runtimeFactory(_restoreAndRestart);
        if (!mounted || _exitRequested) {
          await recovery.close();
        } else {
          setState(() {
            _runtime = recovery;
            _startupError = null;
          });
        }
      } catch (reopenError) {
        if (mounted) {
          setState(() => _startupError = reopenError);
        }
        throw BackupRestoreException('恢复失败，且本地运行时未能重新打开：$reopenError');
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<T> _trackRuntimeTransition<T>(Future<T> operation) {
    final completed = Completer<void>();
    final transition = completed.future;
    _runtimeTransition = transition;
    return operation.whenComplete(() {
      if (!completed.isCompleted) {
        completed.complete();
      }
      if (identical(_runtimeTransition, transition)) {
        _runtimeTransition = null;
      }
    });
  }

  Future<void> _requestGracefulExit() async {
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
  }

  Future<AppExitResponse> _handleExitRequested() async {
    await _shutdownForExit();
    return AppExitResponse.exit;
  }

  Future<Object?> _handleNativeLifecycleCall(MethodCall call) async {
    if (call.method != 'requestClose') {
      throw MissingPluginException('Unknown method ${call.method}');
    }

    final runtime = _runtime;
    if (runtime != null) {
      try {
        if (await runtime.handleWindowCloseRequest()) {
          return false;
        }
      } catch (error, stackTrace) {
        developer.log(
          'Failed to apply the native window close policy.',
          name: 'research_life.window',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    await _shutdownForExit();
    return true;
  }

  Future<void> _shutdownForExit() {
    _exitRequested = true;
    return _shutdownFuture ??= _performShutdownForExit();
  }

  Future<void> _performShutdownForExit() async {
    final transition = _runtimeTransition;
    if (transition != null) {
      await transition;
    }
    final runtime = _runtime;
    _runtime = null;
    if (runtime != null) {
      try {
        await runtime.close();
      } catch (error, stackTrace) {
        // Terminal shutdown cannot recover a runtime after ownership cleanup.
        // Record the failure, but still let the framework complete the exit.
        developer.log(
          'Local runtime cleanup failed during terminal shutdown.',
          name: 'research_life.shutdown',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @override
  void dispose() {
    _nativeLifecycleChannel.setMethodCallHandler(null);
    _appLifecycleListener.dispose();
    if (_shutdownFuture == null) {
      unawaited(_shutdownForExit());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    if (runtime == null) {
      return _StartupSurface(
        failed: _startupError != null,
        onRetry: _startupError == null
            ? null
            : () {
                setState(() => _startupError = null);
                unawaited(_openInitialRuntime());
              },
      );
    }

    final runtimeContentBuilder = widget.runtimeContentBuilder;
    if (runtimeContentBuilder != null) {
      return runtimeContentBuilder(context, runtime);
    }

    return LocalServicesScope(
      backupController: runtime.backupController,
      aiServices: runtime.aiServices,
      restoreAndRestart: _restoreAndRestart,
      child: ResearchLifeScope(
        controller: runtime.controller,
        child: ValueListenableBuilder<AppColorTheme>(
          valueListenable: runtime.controller.colorThemeListenable,
          builder: (context, colorTheme, _) {
            return MaterialApp(
              title: '研LIFE',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(colorTheme),
              home: const AppWindowFrame(
                child: PinLockGate(child: WorkbenchShell()),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StartupSurface extends StatelessWidget {
  const _StartupSurface({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '研LIFE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(AppColorTheme.green),
      home: AppWindowFrame(
        child: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 34),
                const SizedBox(height: 14),
                Text(failed ? '本地工作台启动失败' : '正在打开本地工作台'),
                if (failed) ...[
                  const SizedBox(height: 12),
                  FilledButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
