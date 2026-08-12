import 'dart:async';
import 'dart:io';

typedef LocalDataLockFileResolver = Future<File> Function();

/// Serializes local-library mutations with backup snapshots.
///
/// The zone marker makes nested repository calls re-entrant while unrelated
/// asynchronous work remains queued.
class LocalDataOperationCoordinator {
  LocalDataOperationCoordinator({LocalDataLockFileResolver? lockFileResolver})
    : _lockFileResolver = lockFileResolver;

  final Object _zoneKey = Object();
  final LocalDataLockFileResolver? _lockFileResolver;
  Future<void> _tail = Future<void>.value();

  Future<T> runExclusive<T>(Future<T> Function() operation) {
    final inheritedLease = Zone.current[_zoneKey];
    if (inheritedLease is _LocalDataOperationLease && inheritedLease.active) {
      return operation();
    }

    final result = Completer<T>();
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    unawaited(() async {
      await previous;
      RandomAccessFile? lockHandle;
      var osLockAcquired = false;
      final lease = _LocalDataOperationLease();
      T? value;
      Object? failure;
      StackTrace? failureStackTrace;
      try {
        final lockFileResolver = _lockFileResolver;
        if (lockFileResolver != null) {
          final lockFile = await lockFileResolver();
          await lockFile.parent.create(recursive: true);
          lockHandle = await lockFile.open(mode: FileMode.append);
          await _acquireOsLock(lockHandle);
          osLockAcquired = true;
        }
        value = await runZoned(operation, zoneValues: {_zoneKey: lease});
      } catch (error, stackTrace) {
        failure = error;
        failureStackTrace = stackTrace;
      } finally {
        lease.active = false;
        if (lockHandle != null) {
          try {
            if (osLockAcquired) {
              await lockHandle.unlock();
            }
          } catch (error, stackTrace) {
            failure ??= error;
            failureStackTrace ??= stackTrace;
          } finally {
            try {
              await lockHandle.close();
            } catch (error, stackTrace) {
              failure ??= error;
              failureStackTrace ??= stackTrace;
            }
          }
        }
        released.complete();
      }
      if (failure != null) {
        result.completeError(failure, failureStackTrace!);
      } else {
        result.complete(value as T);
      }
    }());
    return result.future;
  }

  Future<void> _acquireOsLock(RandomAccessFile handle) async {
    while (true) {
      try {
        await handle.lock(FileLock.exclusive);
        return;
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        if (code != 11 && code != 32 && code != 33) {
          rethrow;
        }
        // Windows reports a sharing violation instead of waiting when another
        // process owns the byte-range lock. Retrying turns it into the same
        // blocking mutual exclusion contract used on other platforms.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }
}

class _LocalDataOperationLease {
  bool active = true;
}
