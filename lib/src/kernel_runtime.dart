import 'kernel.dart';

class KernelRuntimeConflictException implements Exception {
  const KernelRuntimeConflictException({
    required this.group,
    required this.activeIdentity,
    required this.requestedIdentity,
    this.cleanupError,
  });

  final String group;
  final String activeIdentity;
  final String requestedIdentity;
  final Object? cleanupError;

  @override
  String toString() {
    final String cleanupDetails = cleanupError == null
        ? ''
        : '，失败 adapter 清理异常：$cleanupError';
    return 'KernelRuntimeConflictException(运行时组 $group 已被身份 '
        '$activeIdentity 占用，无法请求身份 $requestedIdentity$cleanupDetails)';
  }
}

class KernelRuntimeRecoveryException implements Exception {
  const KernelRuntimeRecoveryException({
    required this.group,
    required this.identity,
    required this.deactivationError,
    required this.recoveryError,
  });

  final String group;
  final String identity;
  final Object deactivationError;
  final Object recoveryError;

  @override
  String toString() {
    return 'KernelRuntimeRecoveryException(运行时组 $group 的身份 $identity '
        '停用失败后恢复失败；停用异常：$deactivationError；恢复异常：$recoveryError)';
  }
}

class VideoKernelRuntimeCoordinator {
  VideoKernelRuntimeCoordinator();

  static final VideoKernelRuntimeCoordinator instance =
      VideoKernelRuntimeCoordinator();

  final Map<String, _RuntimeSlot> _slots = <String, _RuntimeSlot>{};
  Future<void> _operation = Future<void>.value();

  Future<VideoKernelRuntimeLease> acquire(VideoKernelAdapter adapter) {
    final String? group = adapter.runtimeGroup;
    if (group == null) {
      return adapter.activateRuntime().then<VideoKernelRuntimeLease>(
        (_) => _VideoKernelRuntimeLease(adapter.deactivateRuntime),
      );
    }

    return _serialize<VideoKernelRuntimeLease>(() async {
      final _RuntimeSlot? activeSlot = _slots[group];
      if (activeSlot != null) {
        if (activeSlot.identity != adapter.runtimeIdentity) {
          throw KernelRuntimeConflictException(
            group: group,
            activeIdentity: activeSlot.identity,
            requestedIdentity: adapter.runtimeIdentity,
          );
        }
        if (activeSlot.poisoned) {
          try {
            await adapter.activateRuntime();
          } catch (error, stackTrace) {
            Error.throwWithStackTrace(
              KernelRuntimeRecoveryException(
                group: group,
                identity: activeSlot.identity,
                deactivationError: activeSlot.deactivationError!,
                recoveryError: error,
              ),
              stackTrace,
            );
          }
          final _RuntimeSlot recoveredSlot = _RuntimeSlot(
            adapter: adapter,
            identity: adapter.runtimeIdentity,
          );
          _slots[group] = recoveredSlot;
          return _VideoKernelRuntimeLease(
            () => _releaseGrouped(group, recoveredSlot),
          );
        }
        activeSlot.referenceCount += 1;
        return _VideoKernelRuntimeLease(
          () => _releaseGrouped(group, activeSlot),
        );
      }

      await adapter.activateRuntime();
      final _RuntimeSlot slot = _RuntimeSlot(
        adapter: adapter,
        identity: adapter.runtimeIdentity,
      );
      _slots[group] = slot;
      return _VideoKernelRuntimeLease(() => _releaseGrouped(group, slot));
    });
  }

  Future<void> _releaseGrouped(String group, _RuntimeSlot slot) {
    return _serialize<void>(() async {
      if (!identical(_slots[group], slot)) {
        return;
      }

      slot.referenceCount -= 1;
      if (slot.referenceCount > 0) {
        return;
      }

      try {
        await slot.adapter.deactivateRuntime();
      } catch (error, stackTrace) {
        slot.poisoned = true;
        slot.deactivationError = error;
        Error.throwWithStackTrace(error, stackTrace);
      }
      _slots.remove(group);
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final Future<T> next = _operation.then((_) => operation());
    _operation = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return next;
  }
}

abstract interface class VideoKernelRuntimeLease {
  Future<void> release();
}

class _RuntimeSlot {
  _RuntimeSlot({required this.adapter, required this.identity});

  final VideoKernelAdapter adapter;
  final String identity;
  int referenceCount = 1;
  bool poisoned = false;
  Object? deactivationError;
}

class _VideoKernelRuntimeLease implements VideoKernelRuntimeLease {
  _VideoKernelRuntimeLease(this._onRelease);

  final Future<void> Function() _onRelease;
  Future<void>? _releaseFuture;

  @override
  Future<void> release() => _releaseFuture ??= _onRelease();
}
