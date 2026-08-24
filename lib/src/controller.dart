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
    this.rollbackError,
  });

  final String fromKernelId;
  final String toKernelId;
  final Duration position;
  final Object targetError;
  final bool rollbackSucceeded;
  final Object? rollbackError;

  @override
  String toString() {
    return rollbackSucceeded
        ? '切换内核 $fromKernelId 到 $toKernelId 失败，已恢复原内核。'
        : '切换内核 $fromKernelId 到 $toKernelId 失败，且恢复原内核失败。';
  }
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
  Future<void> _cleanupFuture = Future<void>.value();
  bool _operationRunning = false;
  bool _refreshingState = false;
  bool _disposed = false;

  List<VideoKernelDescriptor> get availableKernels => registry.descriptors;

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
        fullscreen == value.fullscreen ||
        !UnifiedVideoFullscreenPlatform.isFullscreenOwner(this)) {
      return;
    }
    value = value.copyWith(fullscreen: fullscreen, clearError: true);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
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
    return _enqueue<void>(() => _open(source, preference: preference));
  }

  Future<void> _open(VideoSource source, {KernelPreference? preference}) async {
    _ensureActive();
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
          await _openKernel(kernel, source, fallbackHistory: skippedKernelIds);
          _startStateRefresh();
          return;
        } catch (error) {
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
      }
      _stopStateRefresh();
      value = value.copyWith(
        lifecycle: UnifiedVideoLifecycle.failed,
        error: unifiedError,
        fallbackHistory: skippedKernelIds,
        clearActiveKernelId: true,
      );
      rethrow;
    } catch (error) {
      value = value.copyWith(
        lifecycle: UnifiedVideoLifecycle.failed,
        error: UnifiedVideoError(
          code: UnifiedVideoErrorCode.openFailed,
          message: '打开播放源失败。',
          backendMessage: error.toString(),
        ),
      );
      rethrow;
    }
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

  Future<void> enterFullscreen({bool syncPlatform = true}) async {
    _ensureActive();
    claimFullscreenOwnership();
    value = value.copyWith(fullscreen: true, clearError: true);
    if (syncPlatform) {
      await UnifiedVideoFullscreenPlatform.enter(_platform);
    }
  }

  Future<void> exitFullscreen({bool syncPlatform = true}) async {
    _ensureActive();
    value = value.copyWith(fullscreen: false, clearError: true);
    if (syncPlatform) {
      await UnifiedVideoFullscreenPlatform.exit(_platform);
    }
  }

  Future<void> syncFullscreenPlatform() async {
    _ensureActive();
    if (value.fullscreen) {
      await UnifiedVideoFullscreenPlatform.enter(_platform);
    } else {
      await UnifiedVideoFullscreenPlatform.exit(_platform);
    }
  }

  Future<void> switchSource(VideoSource source) {
    return _enqueue<void>(() => _open(source));
  }

  Future<void> switchKernel(String kernelId) {
    return _enqueue<void>(() => _switchKernel(kernelId));
  }

  Future<void> _switchKernel(String kernelId) async {
    _ensureActive();
    final _KernelSwitchSnapshot snapshot = await _captureSwitchSnapshot();

    value = value.copyWith(
      lifecycle: UnifiedVideoLifecycle.switchingKernel,
      targetKernelId: kernelId,
      clearError: true,
      clearLastKernelSwitchError: true,
    );

    try {
      await _disposeActiveAdapter();
      await _openKernelById(kernelId, snapshot.source);
      await _restoreSwitchSnapshot(snapshot);
      value = value.copyWith(
        clearTargetKernelId: true,
        clearLastKernelSwitchError: true,
        clearError: true,
      );
    } catch (targetError) {
      try {
        await _disposeActiveAdapter();
      } catch (_) {
        // 目标内核清理失败不应阻断原内核回滚。
      }
      try {
        await _openKernelById(snapshot.kernelId, snapshot.source);
        await _restoreSwitchSnapshot(snapshot);
        final KernelSwitchException exception = KernelSwitchException(
          fromKernelId: snapshot.kernelId,
          toKernelId: kernelId,
          position: snapshot.position,
          targetError: targetError,
          rollbackSucceeded: true,
        );
        final UnifiedVideoError error = _kernelSwitchError(exception);
        value = value.copyWith(
          clearTargetKernelId: true,
          lastKernelSwitchError: error,
          error: error,
        );
        throw exception;
      } catch (rollbackError) {
        if (rollbackError is KernelSwitchException) {
          rethrow;
        }
        final KernelSwitchException exception = KernelSwitchException(
          fromKernelId: snapshot.kernelId,
          toKernelId: kernelId,
          position: snapshot.position,
          targetError: targetError,
          rollbackSucceeded: false,
          rollbackError: rollbackError,
        );
        final UnifiedVideoError error = _kernelSwitchError(exception);
        value = value.copyWith(
          lifecycle: UnifiedVideoLifecycle.failed,
          clearTargetKernelId: true,
          lastKernelSwitchError: error,
          error: error,
        );
        throw exception;
      }
    }
  }

  Future<void> _openKernel(
    RegisteredVideoKernel kernel,
    VideoSource source, {
    required List<String> fallbackHistory,
  }) async {
    final VideoKernelAdapter? activeAdapter = _adapter;
    if (activeAdapter?.descriptor.id == kernel.descriptor.id) {
      value = value.copyWith(
        activeKernelId: activeAdapter!.descriptor.id,
        fallbackHistory: fallbackHistory,
      );
      value = await activeAdapter.open(source, value);
      return;
    }

    await _disposeActiveAdapter(snapshot: activeAdapter != null);
    await _createAndOpenKernel(
      kernel,
      source,
      fallbackHistory: fallbackHistory,
    );
  }

  Future<void> _openKernelById(String kernelId, VideoSource source) async {
    final RegisteredVideoKernel? kernel = registry.byId(kernelId);
    if (kernel == null) {
      throw StateError('未注册目标播放器内核：$kernelId。');
    }
    if (!kernel.descriptor.supports(_platform, source)) {
      throw StateError('目标播放器内核 $kernelId 不支持当前播放源。');
    }
    await _createAndOpenKernel(
      kernel,
      source,
      fallbackHistory: const <String>[],
    );
  }

  Future<void> _createAndOpenKernel(
    RegisteredVideoKernel kernel,
    VideoSource source, {
    required List<String> fallbackHistory,
  }) async {
    final VideoKernelAdapter adapter = kernel.create();
    VideoKernelRuntimeLease? lease;
    try {
      lease = await _runtimeCoordinator.acquire(adapter);
      await adapter.initialize();
      _adapter = adapter;
      _runtimeLease = lease;
      value = value.copyWith(
        activeKernelId: adapter.descriptor.id,
        fallbackHistory: fallbackHistory,
      );
      value = await adapter.open(source, value);
    } catch (_) {
      if (identical(_adapter, adapter)) {
        _adapter = null;
        _runtimeLease = null;
      }
      try {
        await _disposeAdapterAndRelease(adapter, lease);
      } catch (_) {
        // 保留候选内核的原始失败原因。
      }
      rethrow;
    }
  }

  Future<void> _disposeActiveAdapter({bool snapshot = false}) async {
    final VideoKernelAdapter? adapter = _adapter;
    final VideoKernelRuntimeLease? lease = _runtimeLease;
    if (adapter == null) {
      _runtimeLease = null;
      if (lease != null) {
        await lease.release();
      }
      return;
    }

    if (snapshot) {
      await adapter.snapshot(value);
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
    return _KernelSwitchSnapshot(
      source: snapshot.source ?? source,
      kernelId: kernelId,
      position: snapshot.position,
      wasPlaying: snapshot.isPlaying,
      speed: snapshot.speed,
      fit: snapshot.fit,
      volume: snapshot.volume,
      fullscreen: snapshot.fullscreen,
    );
  }

  Future<void> _restoreSwitchSnapshot(_KernelSwitchSnapshot snapshot) async {
    await _restorePosition(snapshot.position);
    await _setSpeed(snapshot.speed);
    await _setFit(snapshot.fit);
    await _setVolume(snapshot.volume);
    if (snapshot.wasPlaying) {
      await _play();
    } else {
      value = value.copyWith(lifecycle: UnifiedVideoLifecycle.paused);
    }
    value = value.copyWith(fullscreen: snapshot.fullscreen);
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
      },
    );
  }

  Future<void> _restorePosition(Duration position) async {
    Object? lastError;
    for (int attempt = 0; attempt < 6; attempt++) {
      try {
        await _seek(position);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _refreshAdapterState();
        final int driftMs = (value.position - position).inMilliseconds.abs();
        if (driftMs <= 700 || value.position >= position) {
          return;
        }
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    if (lastError != null) {
      throw lastError;
    }
  }

  Future<void> _runCommand(
    Future<UnifiedVideoState> Function(VideoKernelAdapter adapter) command,
  ) async {
    final VideoKernelAdapter adapter = _requireAdapter();
    try {
      value = (await command(adapter)).copyWith(clearError: true);
      _startStateRefresh();
    } catch (error) {
      value = value.copyWith(
        lifecycle: UnifiedVideoLifecycle.failed,
        error: UnifiedVideoError(
          code: UnifiedVideoErrorCode.commandFailed,
          message: '播放器命令执行失败。',
          backendMessage: error.toString(),
        ),
      );
      rethrow;
    }
  }

  void _startStateRefresh() {
    final Duration? interval = stateRefreshInterval;
    if (interval == null) {
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

    _refreshingState = true;
    try {
      final UnifiedVideoState next = await adapter.snapshot(value);
      if (!_disposed && _adapter == adapter && !value.isDisposed) {
        value = next;
      }
    } catch (_) {
      // 后端异步状态同步失败不应打断 UI；命令调用会返回明确错误。
    } finally {
      _refreshingState = false;
    }
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
