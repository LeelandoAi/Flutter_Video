import 'package:flutter/material.dart';

import '../kernel.dart';
import '../models.dart';

class FakeVideoKernelAdapter extends VideoKernelAdapter {
  FakeVideoKernelAdapter({
    this.duration = const Duration(minutes: 42),
    VideoKernelDescriptor? descriptor,
  }) : _descriptor = descriptor ?? fakeVideoKernelDescriptor;

  final Duration duration;
  final VideoKernelDescriptor _descriptor;
  bool _initialized = false;
  bool _disposed = false;

  @override
  VideoKernelDescriptor get descriptor => _descriptor;

  @override
  Future<void> initialize() async {
    _ensureNotDisposed();
    _initialized = true;
  }

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    _ensureReady();
    return state.copyWith(
      lifecycle: UnifiedVideoLifecycle.ready,
      source: source,
      duration: duration,
      position: Duration.zero,
      activeKernelId: descriptor.id,
      clearError: true,
    );
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    _ensureReady();
    return state;
  }

  @override
  Future<UnifiedVideoState> play(UnifiedVideoState state) async {
    _ensureReady();
    return state.copyWith(lifecycle: UnifiedVideoLifecycle.playing);
  }

  @override
  Future<UnifiedVideoState> pause(UnifiedVideoState state) async {
    _ensureReady();
    return state.copyWith(lifecycle: UnifiedVideoLifecycle.paused);
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    _ensureReady();
    final Duration clamped = position < Duration.zero
        ? Duration.zero
        : position > state.duration
        ? state.duration
        : position;
    return state.copyWith(position: clamped);
  }

  @override
  Future<UnifiedVideoState> stop(UnifiedVideoState state) async {
    _ensureReady();
    return state.copyWith(
      lifecycle: UnifiedVideoLifecycle.idle,
      position: Duration.zero,
    );
  }

  @override
  Future<UnifiedVideoState> setSpeed(
    double speed,
    UnifiedVideoState state,
  ) async {
    _ensureReady();
    return state.copyWith(speed: speed);
  }

  @override
  Future<UnifiedVideoState> setFit(
    UnifiedVideoFit fit,
    UnifiedVideoState state,
  ) async {
    _ensureReady();
    return state.copyWith(fit: fit);
  }

  @override
  Future<UnifiedVideoState> setVolume(
    double volume,
    UnifiedVideoState state,
  ) async {
    _ensureReady();
    return state.copyWith(volume: volume.clamp(0.0, 1.0).toDouble());
  }

  @override
  Widget buildSurface(BuildContext context, UnifiedVideoState state) {
    final String title = state.source?.metadata.title ?? 'Unified Video';
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.movie_filter, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              key: const ValueKey<String>('fake-video-title'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              descriptor.displayName,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  void _ensureReady() {
    _ensureNotDisposed();
    if (!_initialized) {
      throw StateError('fake adapter 尚未初始化。');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('fake adapter 已释放。');
    }
  }
}

const VideoKernelDescriptor fakeVideoKernelDescriptor = VideoKernelDescriptor(
  id: 'fake',
  displayName: 'Fake 测试内核',
  supportedPlatforms: <UnifiedVideoPlatform>{
    UnifiedVideoPlatform.android,
    UnifiedVideoPlatform.ios,
    UnifiedVideoPlatform.windows,
    UnifiedVideoPlatform.macos,
    UnifiedVideoPlatform.web,
    UnifiedVideoPlatform.linux,
    UnifiedVideoPlatform.unknown,
  },
  supportedSourceTypes: <VideoSourceType>{
    VideoSourceType.asset,
    VideoSourceType.file,
    VideoSourceType.network,
    VideoSourceType.memory,
  },
  supportsSubtitles: true,
  supportsTracks: true,
);

RegisteredVideoKernel createFakeVideoKernel({
  String id = 'fake',
  String displayName = 'Fake 测试内核',
  Duration duration = const Duration(minutes: 42),
  Set<UnifiedVideoPlatform>? supportedPlatforms,
  Set<VideoSourceType>? supportedSourceTypes,
}) {
  final VideoKernelDescriptor descriptor = VideoKernelDescriptor(
    id: id,
    displayName: displayName,
    supportedPlatforms:
        supportedPlatforms ?? fakeVideoKernelDescriptor.supportedPlatforms,
    supportedSourceTypes:
        supportedSourceTypes ?? fakeVideoKernelDescriptor.supportedSourceTypes,
    supportsSubtitles: true,
    supportsTracks: true,
  );
  return RegisteredVideoKernel(
    descriptor: descriptor,
    create: () =>
        FakeVideoKernelAdapter(duration: duration, descriptor: descriptor),
  );
}
