import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fullscreen_platform.dart';
import 'kernel.dart';
import 'kernel_runtime.dart';
import 'models.dart';

class KernelSwitchException implements Exception {
  const KernelSwitchException({
    required this.fromKernelId,
    required this.toKernelId,
    required this.position,
    required this.targetError,
    required this.rollbackSucceeded,
    this.cleanupError,
    this.rollbackError,
  });

  final String fromKernelId;
  final String toKernelId;
  final Duration position;
  final Object targetError;
  final bool rollbackSucceeded;
  final Object? cleanupError;
  final Object? rollbackError;

  @override
  String toString() {
    return rollbackSucceeded
        ? '切换内核 $fromKernelId 到 $toKernelId 失败，已恢复原内核。'
        : '切换内核 $fromKernelId 到 $toKernelId 失败，且恢复原内核失败。';
  }
}

class _KernelAdapterCleanupException implements Exception {
  const _KernelAdapterCleanupException({
    required this.operationError,
    required this.cleanupError,
  });

  final Object operationError;
  final Object cleanupError;
}

class _KernelSwitchSnapshot {
  const _KernelSwitchSnapshot({
    required this.source,
    required this.kernelId,
    required this.position,
    required this.wasPlaying,
    required this.speed,
    required this.fit,
    required this.volume,
    required this.fullscreen,
  });

  final VideoSource source;
  final String kernelId;
  final Duration position;
  final bool wasPlaying;
  final double speed;
  final UnifiedVideoFit fit;
  final double volume;
  final bool fullscreen;
}

class UnifiedVideoController extends ValueNotifier<UnifiedVideoState> {
  UnifiedVideoController({
    required this.registry,
    UnifiedVideoPlatform? platform,
    VideoKernelRuntimeCoordinator? runtimeCoordinator,
    this.preference = const KernelPreference.automatic(),
    this.stateRefreshInterval = const Duration(milliseconds: 300),
    UnifiedVideoState initialState = const UnifiedVideoState(),
  }) : _platform = platform ?? currentUnifiedVideoPlatform(),
       _runtimeCoordinator =
           runtimeCoordinator ?? VideoKernelRuntimeCoordinator.instance,
       super(initialState) {
    UnifiedVideoFullscreenPlatform.ensureChangeHandlerInitialized();
    UnifiedVideoFullscreenPlatform.changes.addListener(
      _handleNativeFullscreenChanged,
    );
  }

  final VideoKernelRegistry registry;
  final UnifiedVideoPlatform _platform;
  final VideoKernelRuntimeCoordinator _runtimeCoordinator;
  final Duration? stateRefreshInterval;
  KernelPreference preference;
  VideoKernelAdapter? _adapter;
  VideoKernelRuntimeLease? _runtimeLease;
  Timer? _stateRefreshTimer;
  Future<void> _operationTail = Future<void>.value();
  Future<void> _fullscreenOperationTail = Future<void>.value();
  Future<void> _cleanupFuture = Future<void>.value();
  int _stateGeneration = 0;
  int _openRequestGeneration = 0;
  bool _operationRunning = false;
  bool _refreshingState = false;
  bool _disposed = false;

  List<VideoKernelDescriptor> get availableKernels => registry.descriptors;

  List<VideoKernelDescriptor> get compatibleKernels {
    final VideoSource? source = value.source;
    if (source == null) {
      return availableKernels;
    }
    return availableKernels
        .where((VideoKernelDescriptor item) => item.supports(platform, source))
        .toList(growable: false);
  }

  VideoKernelAdapter? get activeAdapter => _adapter;

  UnifiedVideoPlatform get platform => _platform;

  void claimFullscreenOwnership() {
    UnifiedVideoFullscreenPlatform.claimFullscreenOwnership(this);
  }

  void claimFullscreenOwnershipIfUnclaimed() {
    UnifiedVideoFullscreenPlatform.claimFullscreenOwnershipIfUnclaimed(this);
  }

  void releaseFullscreenOwnership() {
    UnifiedVideoFullscreenPlatform.releaseFullscreenOwnership(this);
  }

  void _handleNativeFullscreenChanged() {
    if (_disposed ||
        (_platform != UnifiedVideoPlatform.macos &&
            _platform != UnifiedVideoPlatform.windows &&
            _platform != UnifiedVideoPlatform.linux)) {
      return;
    }
    final bool? fullscreen = UnifiedVideoFullscreenPlatform.changes.value;
    if (fullscreen == null ||
        !UnifiedVideoFullscreenPlatform.isFullscreenOwner(this)) {
      return;
    }
    if (fullscreen == value.fullscreen) {
      return;
    }
    value = value.copyWith(fullscreen: fullscreen, clearError: true);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      _stateGeneration += 1;
      _operationRunning = true;
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _operationRunning = false;
      }
    });
    return completer.future;
  }

  Future<void> open(VideoSource source, {KernelPreference? preference}) {
    final int requestGeneration = ++_openRequestGeneration;
    return _enqueue<void>(
      () => _open(
        source,
        preference: preference,
        requestGeneration: requestGeneration,
      ),
    );
  }

  @internal
  Future<void> cancelPendingOpen({VideoSource? restoreSource}) {
    final int requestGeneration = ++_openRequestGeneration;
    if (restoreSource != null) {
      return _enqueue<void>(
        () => _open(restoreSource, requestGeneration: requestGeneration),
      );
    }
    return _enqueue<void>(() => _clearCancelledOpen(requestGeneration));
  }

  Future<void> _open(
    VideoSource source, {
    KernelPreference? preference,
    required int requestGeneration,
  }) async {
    _ensureActive();
    final int generation = _stateGeneration;
    if (!_canCommitAsyncState(
      generation,
      openRequestGeneration: requestGeneration,
    )) {
      return;
    }
    this.preference = preference ?? this.preference;
    value = value.copyWith(
      lifecycle: UnifiedVideoLifecycle.opening,
      source: source,
      clearError: true,
    );

    final List<String> skippedKernelIds = <String>[];
    final List<String> runtimeFailures = <String>[];
    Object? lastRuntimeError;

    try {
      final List<RegisteredVideoKernel> candidates = registry.orderedCandidates(
        this.preference,
      );
      for (final RegisteredVideoKernel kernel in candidates) {
        if (!kernel.descriptor.supports(_platform, source)) {
          skippedKernelIds.add(kernel.descriptor.id);
          continue;
        }

        try {
          final bool opened = await _openKernel(
            kernel,
            source,
            fallbackHistory: skippedKernelIds,
            generation: generation,
            openRequestGeneration: requestGeneration,
          );
          if (!opened) {
            return;
          }
          _startStateRefresh();
          return;
        } catch (error) {
          if (!_canCommitAsyncState(
            generation,
            openRequestGeneration: requestGeneration,
          )) {
            return;
          }
          if (error is KernelRuntimeConflictException &&
              !this.preference.allowRuntimeFallback) {
            rethrow;
          }
          lastRuntimeError = error;
          runtimeFailures.add('${kernel.descriptor.id}: $error');
          skippedKernelIds.add(kernel.descriptor.id);
          if (!this.preference.allowRuntimeFallback) {
            break;
          }
        }
      }

      throw UnsupportedKernelException(
        platform: _platform,
        sourceType: source.type,
        candidateKernelIds: candidates
            .map((RegisteredVideoKernel kernel) => kernel.descriptor.id)
            .toList(growable: false),
        skippedKernelIds: skippedKernelIds,
      );
    } on KernelRuntimeConflictException catch (error) {
      _stopStateRefresh();
      _commitAsyncState(
        value.copyWith(
          lifecycle: UnifiedVideoLifecycle.failed,
          error: UnifiedVideoError(
            code: UnifiedVideoErrorCode.runtimeConflict,
            message: '目标播放器内核运行时与当前占用冲突。',
            backendMessage: error.toString(),
            diagnostics: <String, Object?>{
              'runtimeGroup': error.group,
              'activeIdentity': error.activeIdentity,
              'requestedIdentity': error.requestedIdentity,
              if (error.cleanupError != null)
                'cleanupError': error.cleanupError.toString(),
            },
          ),
          fallbackHistory: skippedKernelIds,
          clearActiveKernelId: true,
        ),
        generation,
        openRequestGeneration: requestGeneration,
      );
      rethrow;
    } on UnsupportedKernelException catch (error) {
      final UnifiedVideoError unifiedError = runtimeFailures.isEmpty
          ? error.toError()
          : UnifiedVideoError(
              code: UnifiedVideoErrorCode.openFailed,
              message: '所有兼容播放器内核都打开失败。',
              backendMessage: lastRuntimeError?.toString(),
              diagnostics: <String, Object?>{
                'platform': _platform.name,
                'sourceType': source.type.name,
                'runtimeFailures': runtimeFailures,
                'skippedKernelIds': skippedKernelIds,
              },
            );
      if (runtimeFailures.isNotEmpty) {
        await _disposeActiveAdapter();
        if (!_canCommitAsyncState(
          generation,
          openRequestGeneration: requestGeneration,
        )) {
          return;
        }
      }
      _stopStateRefresh();
      _commitAsyncState(
        value.copyWith(
          lifecycle: UnifiedVideoLifecycle.failed,
          error: unifiedError,
          fallbackHistory: skippedKernelIds,
          clearActiveKernelId: true,
        ),
        generation,
        openRequestGeneration: requestGeneration,
      );
      rethrow;
    } catch (error) {
      if (!_canCommitAsyncState(
        generation,
        openRequestGeneration: requestGeneration,
      )) {
        return;
      }
      _commitAsyncState(
        value.copyWith(
          lifecycle: UnifiedVideoLifecycle.failed,
          error: UnifiedVideoError(
            code: UnifiedVideoErrorCode.openFailed,
            message: '打开播放源失败。',
            backendMessage: error.toString(),
          ),
        ),
        generation,
        openRequestGeneration: requestGeneration,
      );
      rethrow;
    }
  }

  Future<void> _clearCancelledOpen(int requestGeneration) async {
    _ensureActive();
    final int generation = _stateGeneration;
    if (!_canCommitAsyncState(
      generation,
      openRequestGeneration: requestGeneration,
    )) {
      return;
    }
    await _disposeActiveAdapter();
    if (!_canCommitAsyncState(
      generation,
      openRequestGeneration: requestGeneration,
    )) {
      return;
    }
    _stopStateRefresh();
    _commitAsyncState(
      value.copyWith(
        lifecycle: UnifiedVideoLifecycle.idle,
        position: Duration.zero,
        duration: Duration.zero,
        buffered: const <BufferedRange>[],
        tracks: const <VideoTrack>[],
        fallbackHistory: const <String>[],
        clearSource: true,
        clearActiveKernelId: true,
        clearTargetKernelId: true,
        clearError: true,
      ),
      generation,
      openRequestGeneration: requestGeneration,
    );
  }

  Future<void> play() {
    return _enqueue<void>(_play);
  }

  Future<void> pause() {
    return _enqueue<void>(_pause);
  }

  Future<void> seek(Duration position) {
    return _enqueue<void>(() => _seek(position));
  }

  Future<void> stop() {
    return _enqueue<void>(_stop);
  }

  Future<void> setSpeed(double speed) {
    return _enqueue<void>(() => _setSpeed(speed));
  }

  Future<void> setFit(UnifiedVideoFit fit) {
    return _enqueue<void>(() => _setFit(fit));
  }

  Future<void> setVolume(double volume) {
    return _enqueue<void>(() => _setVolume(volume));
  }

  Future<void> _setVolume(double volume) {
    if (volume.isNaN || volume < 0.0 || volume > 1.0) {
      throw ArgumentError.value(volume, 'volume', '音量必须在 0.0 到 1.0 之间。');
    }
    return _runCommand(
      (VideoKernelAdapter adapter) => adapter.setVolume(volume, value),
    );
  }

  Future<void> _play() {
    return _runCommand((VideoKernelAdapter adapter) => adapter.play(value));
  }

  Future<void> _pause() {
    return _runCommand((VideoKernelAdapter adapter) => adapter.pause(value));
  }

  Future<void> _seek(Duration position) {
    return _runCommand(
      (VideoKernelAdapter adapter) => adapter.seek(position, value),
    );
  }

  Future<void> _stop() {
    return _runCommand((VideoKernelAdapter adapter) => adapter.stop(value));
  }

  Future<void> _setSpeed(double speed) async {
    final VideoKernelAdapter adapter = _requireAdapter();
    if (!adapter.descriptor.supportsSpeed(speed)) {
      _failUnsupportedCapability('当前内核不支持 $speed 倍速。');
    }
    await _runCommand((VideoKernelAdapter adapter) {
      return adapter.setSpeed(speed, value);
    });
  }

  Future<void> _setFit(UnifiedVideoFit fit) async {
    final VideoKernelAdapter adapter = _requireAdapter();
    if (!adapter.descriptor.supportsFit(fit)) {
      _failUnsupportedCapability('当前内核不支持 ${fit.name} 缩放模式。');
    }
    await _runCommand((VideoKernelAdapter adapter) {
      return adapter.setFit(fit, value);
    });
  }

  Future<void> enterFullscreen({
    bool syncPlatform = true,
    UnifiedVideoFullscreenOrientation orientation =
        UnifiedVideoFullscreenOrientation.landscape,
  }) {
    return _enterFullscreen(
      syncPlatform: syncPlatform,
      orientation: orientation,
    );
  }

  Future<void> _enterFullscreen({
    required bool syncPlatform,
    required UnifiedVideoFullscreenOrientation orientation,
  }) async {
    _ensureActive();
    claimFullscreenOwnership();
    value = value.copyWith(fullscreen: true, clearError: true);
    if (syncPlatform) {
      await _enqueueFullscreenPlatform(
        () => UnifiedVideoFullscreenPlatform.enter(_platform, orientation),
      );
    }
  }

  Future<void> exitFullscreen({bool syncPlatform = true}) {
    return _exitFullscreen(syncPlatform: syncPlatform);
  }

  Future<void> _exitFullscreen({required bool syncPlatform}) async {
    _ensureActive();
    value = value.copyWith(fullscreen: false, clearError: true);
    if (syncPlatform) {
      await _enqueueFullscreenPlatform(
        () => UnifiedVideoFullscreenPlatform.exit(_platform),
      );
    }
  }

  Future<void> syncFullscreenPlatform({
    UnifiedVideoFullscreenOrientation orientation =
        UnifiedVideoFullscreenOrientation.landscape,
  }) {
    return _syncFullscreenPlatform(orientation: orientation);
  }

  Future<void> _syncFullscreenPlatform({
    required UnifiedVideoFullscreenOrientation orientation,
  }) async {
    _ensureActive();
    if (value.fullscreen) {
      await _enqueueFullscreenPlatform(
        () => UnifiedVideoFullscreenPlatform.enter(_platform, orientation),
      );
    } else {
      await _enqueueFullscreenPlatform(
        () => UnifiedVideoFullscreenPlatform.exit(_platform),
      );
    }
  }

  Future<void> _enqueueFullscreenPlatform(Future<void> Function() operation) {
    final Completer<void> completer = Completer<void>();
    _fullscreenOperationTail = _fullscreenOperationTail.then((_) async {
      try {
        await operation();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> switchSource(VideoSource source) {
    return open(source);
  }

  Future<void> switchKernel(String kernelId) {
    return _enqueue<void>(() => _switchKernel(kernelId));
  }

  Future<void> _switchKernel(String kernelId) async {
    _ensureActive();
    final int generation = _stateGeneration;
    final _KernelSwitchSnapshot snapshot = await _captureSwitchSnapshot();

    if (!_commitAsyncState(
      value.copyWith(
        lifecycle: UnifiedVideoLifecycle.switchingKernel,
        targetKernelId: kernelId,
        clearError: true,
        clearLastKernelSwitchError: true,
      ),
      generation,
    )) {
      return;
    }

    try {
      try {
        await _disposeActiveAdapter();
      } catch (cleanupError) {
        throw _KernelAdapterCleanupException(
          operationError: StateError('切换目标内核前释放原内核失败。'),
          cleanupError: cleanupError,
        );
      }
      if (!_canCommitAsyncState(generation)) {
        return;
      }
      if (!await _openKernelById(kernelId, snapshot.source, generation)) {
        return;
      }
      if (!await _restoreSwitchSnapshot(snapshot, generation)) {
        return;
      }
      _commitAsyncState(
        value.copyWith(
          clearTargetKernelId: true,
          clearLastKernelSwitchError: true,
          clearError: true,
        ),
        generation,
      );
    } catch (rawTargetError) {
      if (!_canCommitAsyncState(generation)) {
        return;
      }
      Object targetError = rawTargetError;
      Object? cleanupError;
      if (rawTargetError is _KernelAdapterCleanupException) {
        targetError = rawTargetError.operationError;
        cleanupError = rawTargetError.cleanupError;
      }
      try {
        await _disposeActiveAdapter();
      } catch (error) {
        cleanupError ??= error;
      }
      if (!_canCommitAsyncState(generation)) {
        return;
      }
      try {
        if (!await _openKernelById(
          snapshot.kernelId,
          snapshot.source,
          generation,
        )) {
          return;
        }
        if (!await _restoreSwitchSnapshot(snapshot, generation)) {
          return;
        }
        final KernelSwitchException exception = KernelSwitchException(
          fromKernelId: snapshot.kernelId,
          toKernelId: kernelId,
          position: snapshot.position,
          targetError: targetError,
          rollbackSucceeded: true,
          cleanupError: cleanupError,
        );
        final UnifiedVideoError error = _kernelSwitchError(exception);
        if (!_commitAsyncState(
          value.copyWith(
            clearTargetKernelId: true,
            lastKernelSwitchError: error,
            error: error,
          ),
          generation,
        )) {
          return;
        }
        throw exception;
      } catch (rollbackError) {
        if (!_canCommitAsyncState(generation)) {
          return;
        }
        if (rollbackError is KernelSwitchException) {
          rethrow;
        }
        final KernelSwitchException exception = KernelSwitchException(
          fromKernelId: snapshot.kernelId,
          toKernelId: kernelId,
          position: snapshot.position,
          targetError: targetError,
          rollbackSucceeded: false,
          cleanupError: cleanupError,
          rollbackError: rollbackError,
        );
        final UnifiedVideoError error = _kernelSwitchError(exception);
        if (!_commitAsyncState(
          value.copyWith(
            lifecycle: UnifiedVideoLifecycle.failed,
            clearTargetKernelId: true,
            lastKernelSwitchError: error,
            error: error,
          ),
          generation,
        )) {
          return;
        }
        throw exception;
      }
    }
  }

  Future<bool> _openKernel(
    RegisteredVideoKernel kernel,
    VideoSource source, {
    required List<String> fallbackHistory,
    required int generation,
    required int openRequestGeneration,
  }) async {
    final VideoKernelAdapter? activeAdapter = _adapter;
    if (activeAdapter?.descriptor.id == kernel.descriptor.id) {
      if (!_commitAsyncState(
        value.copyWith(
          activeKernelId: activeAdapter!.descriptor.id,
          fallbackHistory: fallbackHistory,
        ),
        generation,
        adapter: activeAdapter,
        openRequestGeneration: openRequestGeneration,
      )) {
        return false;
      }
      final UnifiedVideoState next = await activeAdapter.open(source, value);
      if (!_commitAsyncState(
        next,
        generation,
        adapter: activeAdapter,
        openRequestGeneration: openRequestGeneration,
      )) {
        await _discardAdapterAfterCancellation(activeAdapter, _runtimeLease);
        return false;
      }
      return true;
    }

    await _disposeActiveAdapter();
    if (!_canCommitAsyncState(
      generation,
      openRequestGeneration: openRequestGeneration,
    )) {
      return false;
    }
    return _createAndOpenKernel(
      kernel,
      source,
      fallbackHistory: fallbackHistory,
      generation: generation,
      openRequestGeneration: openRequestGeneration,
    );
  }

  Future<bool> _openKernelById(
    String kernelId,
    VideoSource source,
    int generation,
  ) async {
    final RegisteredVideoKernel? kernel = registry.byId(kernelId);
    if (kernel == null) {
      throw StateError('未注册目标播放器内核：$kernelId。');
    }
    if (!kernel.descriptor.supports(_platform, source)) {
      throw StateError('目标播放器内核 $kernelId 不支持当前播放源。');
    }
    return _createAndOpenKernel(
      kernel,
      source,
      fallbackHistory: const <String>[],
      generation: generation,
      openPosition: Duration.zero,
    );
  }

  Future<bool> _createAndOpenKernel(
    RegisteredVideoKernel kernel,
    VideoSource source, {
    required List<String> fallbackHistory,
    required int generation,
    int? openRequestGeneration,
    Duration? openPosition,
  }) async {
    final VideoKernelAdapter adapter = kernel.create();
    VideoKernelRuntimeLease? lease;
    try {
      lease = await _runtimeCoordinator.acquire(adapter);
      if (!_canCommitAsyncState(
        generation,
        openRequestGeneration: openRequestGeneration,
      )) {
        await _discardAdapterAfterCancellation(adapter, lease);
        return false;
      }
      await adapter.initialize();
      if (!_canCommitAsyncState(
        generation,
        openRequestGeneration: openRequestGeneration,
      )) {
        await _discardAdapterAfterCancellation(adapter, lease);
        return false;
      }
      _adapter = adapter;
      _runtimeLease = lease;
      if (!_commitAsyncState(
        value.copyWith(
          activeKernelId: adapter.descriptor.id,
          fallbackHistory: fallbackHistory,
        ),
        generation,
        adapter: adapter,
        openRequestGeneration: openRequestGeneration,
      )) {
        await _discardAdapterAfterCancellation(adapter, lease);
        return false;
      }
      final UnifiedVideoState next = await adapter.open(
        source,
        openPosition == null ? value : value.copyWith(position: openPosition),
      );
      if (!_commitAsyncState(
        next,
        generation,
        adapter: adapter,
        openRequestGeneration: openRequestGeneration,
      )) {
        await _discardAdapterAfterCancellation(adapter, lease);
        return false;
      }
      return true;
    } catch (error, stackTrace) {
      try {
        await _discardAdapter(adapter, lease);
      } catch (cleanupError) {
        if (!_canCommitAsyncState(
          generation,
          openRequestGeneration: openRequestGeneration,
        )) {
          return false;
        }
        if (error is KernelRuntimeConflictException) {
          throw KernelRuntimeConflictException(
            group: error.group,
            activeIdentity: error.activeIdentity,
            requestedIdentity: error.requestedIdentity,
            cleanupError: cleanupError,
          );
        }
        throw _KernelAdapterCleanupException(
          operationError: error,
          cleanupError: cleanupError,
        );
      }
      if (!_canCommitAsyncState(
        generation,
        openRequestGeneration: openRequestGeneration,
      )) {
        return false;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _discardAdapter(
    VideoKernelAdapter adapter,
    VideoKernelRuntimeLease? lease,
  ) async {
    if (identical(_adapter, adapter)) {
      _adapter = null;
      _runtimeLease = null;
    }
    await _disposeAdapterAndRelease(adapter, lease);
  }

  Future<void> _discardAdapterAfterCancellation(
    VideoKernelAdapter adapter,
    VideoKernelRuntimeLease? lease,
  ) async {
    try {
      await _discardAdapter(adapter, lease);
    } catch (_) {
      // 控制器已被释放或操作已失效，不能再向 notifier 提交清理诊断。
    }
  }

  Future<void> _disposeActiveAdapter() async {
    final VideoKernelAdapter? adapter = _adapter;
    final VideoKernelRuntimeLease? lease = _runtimeLease;
    if (adapter == null) {
      _runtimeLease = null;
      if (lease != null) {
        await lease.release();
      }
      return;
    }

    _adapter = null;
    _runtimeLease = null;
    await _disposeAdapterAndRelease(adapter, lease);
  }

  Future<void> _disposeAdapterAndRelease(
    VideoKernelAdapter adapter,
    VideoKernelRuntimeLease? lease,
  ) async {
    try {
      await adapter.dispose();
    } finally {
      await lease?.release();
    }
  }

  Future<_KernelSwitchSnapshot> _captureSwitchSnapshot() async {
    final VideoSource? source = value.source;
    final String? kernelId = value.activeKernelId;
    if (source == null || kernelId == null) {
      throw StateError('切换内核前必须先打开播放源。');
    }
    final UnifiedVideoState snapshot = await _requireAdapter().snapshot(value);
    final bool isAtEnd =
        snapshot.lifecycle == UnifiedVideoLifecycle.ended ||
        (snapshot.duration > Duration.zero &&
            snapshot.position >= snapshot.duration);
    return _KernelSwitchSnapshot(
      source: snapshot.source ?? source,
      kernelId: kernelId,
      position: isAtEnd ? Duration.zero : snapshot.position,
      wasPlaying: !isAtEnd && snapshot.isPlaying,
      speed: snapshot.speed,
      fit: snapshot.fit,
      volume: snapshot.volume,
      fullscreen: snapshot.fullscreen,
    );
  }

  Future<bool> _restoreSwitchSnapshot(
    _KernelSwitchSnapshot snapshot,
    int generation,
  ) async {
    if (!await _restorePosition(snapshot.position, generation)) {
      return false;
    }
    await _setSpeed(snapshot.speed);
    if (!_canCommitAsyncState(generation)) {
      return false;
    }
    await _setFit(snapshot.fit);
    if (!_canCommitAsyncState(generation)) {
      return false;
    }
    await _setVolume(snapshot.volume);
    if (!_canCommitAsyncState(generation)) {
      return false;
    }
    if (snapshot.wasPlaying) {
      await _play();
      if (!_canCommitAsyncState(generation)) {
        return false;
      }
    } else {
      if (!_commitAsyncState(
        value.copyWith(lifecycle: UnifiedVideoLifecycle.paused),
        generation,
      )) {
        return false;
      }
    }
    return _commitAsyncState(
      value.copyWith(fullscreen: snapshot.fullscreen),
      generation,
    );
  }

  UnifiedVideoError _kernelSwitchError(KernelSwitchException exception) {
    return UnifiedVideoError(
      code: UnifiedVideoErrorCode.kernelSwitchFailed,
      message: exception.rollbackSucceeded
          ? '切换目标播放器内核失败，已恢复原内核。'
          : '切换目标播放器内核失败，且恢复原内核失败。',
      backendMessage: exception.targetError.toString(),
      diagnostics: <String, Object?>{
        'fromKernelId': exception.fromKernelId,
        'toKernelId': exception.toKernelId,
        'positionMilliseconds': exception.position.inMilliseconds,
        'rollbackSucceeded': exception.rollbackSucceeded,
        if (exception.rollbackError != null)
          'rollbackError': exception.rollbackError.toString(),
        if (exception.cleanupError != null)
          'cleanupError': exception.cleanupError.toString(),
      },
    );
  }

  Future<bool> _restorePosition(Duration position, int generation) async {
    if (position == Duration.zero &&
        value.position <= const Duration(seconds: 1)) {
      return _canCommitAsyncState(generation);
    }

    await _seek(position);
    if (!_canCommitAsyncState(generation)) {
      return false;
    }
    bool retriedAfterDurationKnown = value.duration > Duration.zero;

    Object? lastError;
    for (int attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!_canCommitAsyncState(generation)) {
        return false;
      }
      try {
        if (!await _refreshAdapterStateForOperation(generation)) {
          return false;
        }
        lastError = null;
        final int driftMs = (value.position - position).inMilliseconds.abs();
        if (driftMs <= 1000) {
          return true;
        }
        if (!retriedAfterDurationKnown && value.duration > Duration.zero) {
          retriedAfterDurationKnown = true;
          await _seek(position);
          if (!_canCommitAsyncState(generation)) {
            return false;
          }
          final int retryDriftMs = (value.position - position).inMilliseconds
              .abs();
          if (retryDriftMs <= 1000) {
            return true;
          }
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw StateError(
      '播放器内核恢复进度失败：目标 ${position.inMilliseconds}ms，'
      '实际 ${value.position.inMilliseconds}ms。',
    );
  }

  Future<bool> _refreshAdapterStateForOperation(int generation) async {
    final VideoKernelAdapter adapter = _requireAdapter();
    final UnifiedVideoState next = await adapter.snapshot(value);
    return _commitAsyncState(next, generation, adapter: adapter);
  }

  Future<void> _runCommand(
    Future<UnifiedVideoState> Function(VideoKernelAdapter adapter) command,
  ) async {
    final VideoKernelAdapter adapter = _requireAdapter();
    final int generation = _stateGeneration;
    try {
      final UnifiedVideoState next = await command(adapter);
      if (!_commitAsyncState(
        next.copyWith(clearError: true),
        generation,
        adapter: adapter,
      )) {
        return;
      }
      _startStateRefresh();
    } catch (error) {
      if (_disposed) {
        return;
      }
      if (!_canCommitAsyncState(generation, adapter: adapter)) {
        rethrow;
      }
      _commitAsyncState(
        value.copyWith(
          lifecycle: UnifiedVideoLifecycle.failed,
          error: UnifiedVideoError(
            code: UnifiedVideoErrorCode.commandFailed,
            message: '播放器命令执行失败。',
            backendMessage: error.toString(),
          ),
        ),
        generation,
        adapter: adapter,
      );
      rethrow;
    }
  }

  void _startStateRefresh() {
    final Duration? interval = stateRefreshInterval;
    if (_disposed || interval == null) {
      return;
    }
    _stateRefreshTimer ??= Timer.periodic(
      interval,
      (_) => unawaited(_refreshAdapterState()),
    );
  }

  void _stopStateRefresh() {
    _stateRefreshTimer?.cancel();
    _stateRefreshTimer = null;
    _refreshingState = false;
  }

  Future<void> _refreshAdapterState() async {
    if (_disposed || _operationRunning || _refreshingState) {
      return;
    }
    final VideoKernelAdapter? adapter = _adapter;
    if (adapter == null) {
      return;
    }

    final int generation = _stateGeneration;
    _refreshingState = true;
    try {
      final UnifiedVideoState next = await adapter.snapshot(value);
      _commitAsyncState(next, generation, adapter: adapter);
    } catch (_) {
      // 后端异步状态同步失败不应打断 UI；命令调用会返回明确错误。
    } finally {
      _refreshingState = false;
    }
  }

  bool _canCommitAsyncState(
    int generation, {
    VideoKernelAdapter? adapter,
    int? openRequestGeneration,
  }) {
    return !_disposed &&
        !value.isDisposed &&
        (adapter == null || identical(_adapter, adapter)) &&
        (openRequestGeneration == null ||
            _openRequestGeneration == openRequestGeneration) &&
        _stateGeneration == generation;
  }

  bool _commitAsyncState(
    UnifiedVideoState next,
    int generation, {
    VideoKernelAdapter? adapter,
    int? openRequestGeneration,
  }) {
    if (!_canCommitAsyncState(
      generation,
      adapter: adapter,
      openRequestGeneration: openRequestGeneration,
    )) {
      return false;
    }
    value = next.fullscreen == value.fullscreen
        ? next
        : next.copyWith(fullscreen: value.fullscreen);
    return true;
  }

  VideoKernelAdapter _requireAdapter() {
    _ensureActive();
    final VideoKernelAdapter? adapter = _adapter;
    if (adapter == null) {
      throw StateError('尚未打开播放源。');
    }
    return adapter;
  }

  void _ensureActive() {
    if (_disposed || value.isDisposed) {
      throw StateError('控制器已释放。');
    }
  }

  Never _failUnsupportedCapability(String message) {
    value = value.copyWith(
      lifecycle: UnifiedVideoLifecycle.failed,
      error: UnifiedVideoError(
        code: UnifiedVideoErrorCode.unsupportedCapability,
        message: message,
      ),
    );
    throw UnsupportedError(message);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _stateGeneration += 1;
    _disposed = true;
    releaseFullscreenOwnership();
    UnifiedVideoFullscreenPlatform.changes.removeListener(
      _handleNativeFullscreenChanged,
    );
    _stopStateRefresh();
    _cleanupFuture = _operationTail.then<void>((_) => _disposeActiveAdapter());
    unawaited(_cleanupFuture.catchError((Object _) {}));
    value = value.copyWith(
      lifecycle: UnifiedVideoLifecycle.disposed,
      error: const UnifiedVideoError(
        code: UnifiedVideoErrorCode.disposedController,
        message: '控制器已释放。',
      ),
    );
    super.dispose();
  }
}
