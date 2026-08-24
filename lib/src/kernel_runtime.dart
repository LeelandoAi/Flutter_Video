import 'kernel.dart';

class KernelRuntimeConflictException implements Exception {
  const KernelRuntimeConflictException({
    required this.group,
    required this.activeIdentity,
    required this.requestedIdentity,
  });

  final String group;
  final String activeIdentity;
  final String requestedIdentity;

  @override
  String toString() {
    return 'KernelRuntimeConflictException(运行时组 $group 已被身份 '
        '$activeIdentity 占用，无法请求身份 $requestedIdentity)';
  }
}

class VideoKernelRuntimeCoordinator {
  VideoKernelRuntimeCoordinator();

  static final VideoKernelRuntimeCoordinator instance =
      VideoKernelRuntimeCoordinator();

  final Map<String, _RuntimeSlot> _slots = <String, _RuntimeSlot>{};
  Future<void> _operation = Future<void>.value();

  Future<VideoKernelRuntimeLease> acquire(VideoKernelAdapter adapter) {
    return _serialize<VideoKernelRuntimeLease>(() async {
      final String? group = adapter.runtimeGroup;
      if (group == null) {
        await adapter.activateRuntime();
        return _VideoKernelRuntimeLease(
          () => _serialize<void>(adapter.deactivateRuntime),
        );
      }

      final _RuntimeSlot? activeSlot = _slots[group];
      if (activeSlot != null) {
        if (activeSlot.identity != adapter.runtimeIdentity) {
          throw KernelRuntimeConflictException(
            group: group,
            activeIdentity: activeSlot.identity,
            requestedIdentity: adapter.runtimeIdentity,
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

      _slots.remove(group);
      await slot.adapter.deactivateRuntime();
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
}

class _VideoKernelRuntimeLease implements VideoKernelRuntimeLease {
  _VideoKernelRuntimeLease(this._onRelease);

  final Future<void> Function() _onRelease;
  Future<void>? _releaseFuture;

  @override
  Future<void> release() => _releaseFuture ??= _onRelease();
}
