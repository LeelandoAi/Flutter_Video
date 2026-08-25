import 'dart:io';

import 'package:flutter/material.dart';
import 'package:leelando_video/leelando_video.dart';
import 'package:video_player/video_player.dart';

abstract class VideoPlayerKernelAdapterBase extends VideoKernelAdapter {
  VideoPlayerController? _controller;

  @override
  Future<void> initialize() async {}

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    await _controller?.dispose();
    _controller = createController(source);
    await _controller!.initialize();
    return state.copyWith(
      lifecycle: UnifiedVideoLifecycle.ready,
      source: source,
      activeKernelId: descriptor.id,
      duration: _controller!.value.duration,
      position: _controller!.value.position,
      clearError: true,
    );
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    return stateFromController(state);
  }

  @protected
  VideoPlayerController createController(VideoSource source) {
    switch (source.type) {
      case VideoSourceType.asset:
        return VideoPlayerController.asset(source.uri.path);
      case VideoSourceType.file:
        return VideoPlayerController.file(File(source.uri.toFilePath()));
      case VideoSourceType.network:
        return VideoPlayerController.networkUrl(
          source.uri,
          httpHeaders: source.headers,
        );
      case VideoSourceType.memory:
        throw UnsupportedError('${descriptor.displayName} 不支持 memory 播放源。');
    }
  }

  @override
  Future<UnifiedVideoState> play(UnifiedVideoState state) async {
    final VideoPlayerController controller = requireController();
    await controller.play();
    return stateFromController(state, UnifiedVideoLifecycle.playing);
  }

  @override
  Future<UnifiedVideoState> pause(UnifiedVideoState state) async {
    final VideoPlayerController controller = requireController();
    await controller.pause();
    return stateFromController(state, UnifiedVideoLifecycle.paused);
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    final VideoPlayerController controller = requireController();
    await controller.seekTo(position);
    return stateFromController(state);
  }

  @override
  Future<UnifiedVideoState> stop(UnifiedVideoState state) async {
    final VideoPlayerController controller = requireController();
    await controller.pause();
    await controller.seekTo(Duration.zero);
    return stateFromController(state, UnifiedVideoLifecycle.idle);
  }

  @override
  Future<UnifiedVideoState> setVolume(
    double volume,
    UnifiedVideoState state,
  ) async {
    final VideoPlayerController controller = requireController();
    await controller.setVolume(volume);
    return stateFromController(state).copyWith(volume: volume);
  }

  @override
  Future<UnifiedVideoState> setSpeed(
    double speed,
    UnifiedVideoState state,
  ) async {
    final VideoPlayerController controller = requireController();
    await controller.setPlaybackSpeed(speed);
    return stateFromController(state).copyWith(speed: speed);
  }

  @override
  Future<UnifiedVideoState> setFit(
    UnifiedVideoFit fit,
    UnifiedVideoState state,
  ) async {
    return state.copyWith(fit: fit);
  }

  @override
  Widget buildSurface(BuildContext context, UnifiedVideoState state) {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return VideoPlayer(controller);
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }

  @protected
  VideoPlayerController requireController() {
    final VideoPlayerController? controller = _controller;
    if (controller == null) {
      throw StateError('${descriptor.displayName} 尚未打开播放源。');
    }
    return controller;
  }

  @protected
  UnifiedVideoState stateFromController(
    UnifiedVideoState state, [
    UnifiedVideoLifecycle? lifecycle,
  ]) {
    final VideoPlayerController controller = requireController();
    final VideoPlayerValue value = controller.value;
    if (value.hasError) {
      return state.copyWith(
        lifecycle: UnifiedVideoLifecycle.failed,
        error: UnifiedVideoError(
          code: UnifiedVideoErrorCode.openFailed,
          message: '播放器后端错误。',
          backendMessage: value.errorDescription,
        ),
      );
    }
    final UnifiedVideoLifecycle resolvedLifecycle =
        lifecycle ??
        (value.isCompleted
            ? UnifiedVideoLifecycle.ended
            : value.isBuffering
            ? UnifiedVideoLifecycle.buffering
            : value.isPlaying
            ? UnifiedVideoLifecycle.playing
            : state.lifecycle);
    return state.copyWith(
      lifecycle: resolvedLifecycle,
      duration: value.duration,
      position: value.position,
      buffered: value.buffered
          .map(
            (DurationRange range) =>
                BufferedRange(start: range.start, end: range.end),
          )
          .toList(growable: false),
      clearError: true,
    );
  }
}
