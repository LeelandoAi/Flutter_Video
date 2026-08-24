import 'dart:async';

import 'package:flutter/foundation.dart';

import 'fullscreen_platform.dart';
import 'kernel.dart';
import 'models.dart';

class UnifiedVideoController extends ValueNotifier<UnifiedVideoState> {
  UnifiedVideoController({
    required this.registry,
    UnifiedVideoPlatform? platform,
    this.preference = const KernelPreference.automatic(),
    this.stateRefreshInterval = const Duration(milliseconds: 300),
    UnifiedVideoState initialState = const UnifiedVideoState(),
  }) : _platform = platform ?? currentUnifiedVideoPlatform(),
       super(initialState) {
    UnifiedVideoFullscreenPlatform.ensureChangeHandlerInitialized();
    UnifiedVideoFullscreenPlatform.changes.addListener(
      _handleNativeFullscreenChanged,
    );
  }

  final VideoKernelRegistry registry;
  final UnifiedVideoPlatform _platform;
  final Duration? stateRefreshInterval;
  KernelPreference preference;
  VideoKernelAdapter? _adapter;
  Timer? _stateRefreshTimer;
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

  Future<void> open(VideoSource source, {KernelPreference? preference}) async {
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

        final bool reuseActiveAdapter =
            _adapter?.descriptor.id == kernel.descriptor.id;
        final VideoKernelAdapter adapter = reuseActiveAdapter
            ? _adapter!
            : kernel.create();

        try {
          if (!reuseActiveAdapter) {
            await _adapter?.dispose();
            _adapter = adapter;
            await adapter.initialize();
          }
          value = value.copyWith(
            activeKernelId: adapter.descriptor.id,
            fallbackHistory: skippedKernelIds,
          );
          value = await adapter.open(source, value);
          _startStateRefresh();
          return;
        } catch (error) {
          lastRuntimeError = error;
          runtimeFailures.add('${kernel.descriptor.id}: $error');
          skippedKernelIds.add(kernel.descriptor.id);
          if (!reuseActiveAdapter) {
            await adapter.dispose();
            if (_adapter == adapter) {
              _adapter = null;
            }
          }
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
        await _adapter?.dispose();
        _adapter = null;
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
    return _runCommand((VideoKernelAdapter adapter) => adapter.play(value));
  }

  Future<void> pause() {
    return _runCommand((VideoKernelAdapter adapter) => adapter.pause(value));
  }

  Future<void> seek(Duration position) {
    return _runCommand(
      (VideoKernelAdapter adapter) => adapter.seek(position, value),
    );
  }

  Future<void> stop() {
    return _runCommand((VideoKernelAdapter adapter) => adapter.stop(value));
  }

  Future<void> setSpeed(double speed) async {
    final VideoKernelAdapter adapter = _requireAdapter();
    if (!adapter.descriptor.supportsSpeed(speed)) {
      _failUnsupportedCapability('当前内核不支持 $speed 倍速。');
    }
    await _runCommand((VideoKernelAdapter adapter) {
      return adapter.setSpeed(speed, value);
    });
  }

  Future<void> setFit(UnifiedVideoFit fit) async {
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
    return open(source);
  }

  Future<void> switchKernel(String kernelId) {
    final VideoSource? source = value.source;
    if (source == null) {
      throw StateError('切换内核前必须先打开播放源。');
    }
    final Duration previousPosition = value.position;
    final double previousSpeed = value.speed;
    final bool wasPlaying = value.isPlaying;
    return _switchKernelAndRestorePlayback(
      source: source,
      kernelId: kernelId,
      previousPosition: previousPosition,
      previousSpeed: previousSpeed,
      wasPlaying: wasPlaying,
    );
  }

  Future<void> _switchKernelAndRestorePlayback({
    required VideoSource source,
    required String kernelId,
    required Duration previousPosition,
    required double previousSpeed,
    required bool wasPlaying,
  }) async {
    await open(source, preference: KernelPreference.exact(kernelId));
    if (previousPosition > Duration.zero) {
      await _restorePosition(previousPosition);
    }
    if (previousSpeed != value.speed) {
      await setSpeed(previousSpeed);
    }
    if (wasPlaying) {
      await play();
    }
  }

  Future<void> _restorePosition(Duration position) async {
    Object? lastError;
    for (int attempt = 0; attempt < 6; attempt++) {
      try {
        await seek(position);
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
    if (_disposed || _refreshingState) {
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
    _adapter?.dispose();
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
