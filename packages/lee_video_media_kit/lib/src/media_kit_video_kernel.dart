import 'package:flutter/material.dart';
import 'package:lee_video/lee_video.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

RegisteredVideoKernel createMediaKitVideoKernel() {
  return RegisteredVideoKernel(
    descriptor: mediaKitVideoKernelDescriptor,
    create: MediaKitVideoKernelAdapter.new,
  );
}

const VideoKernelDescriptor mediaKitVideoKernelDescriptor =
    VideoKernelDescriptor(
      id: 'media-kit',
      displayName: 'Media Kit / libmpv',
      supportedPlatforms: <UnifiedVideoPlatform>{
        UnifiedVideoPlatform.android,
        UnifiedVideoPlatform.ios,
        UnifiedVideoPlatform.windows,
        UnifiedVideoPlatform.macos,
      },
      supportedSourceTypes: <VideoSourceType>{
        VideoSourceType.asset,
        VideoSourceType.file,
        VideoSourceType.network,
      },
      supportsSubtitles: true,
      supportsTracks: true,
      knownLimitations: <String>['首版映射基础播放、暂停、跳转、停止、倍速、画面和基础状态；高级轨道选择命令后续补齐。'],
    );

class MediaKitVideoKernelAdapter extends VideoKernelAdapter {
  MediaKitVideoKernelAdapter({
    VideoKernelDescriptor? descriptor,
    mk.Player? nativePlayer,
  }) : _descriptor = descriptor ?? mediaKitVideoKernelDescriptor,
       _player = nativePlayer;

  final VideoKernelDescriptor _descriptor;
  mk.Player? _player;
  mkv.VideoController? _videoController;

  @override
  VideoKernelDescriptor get descriptor => _descriptor;

  @override
  Future<void> initialize() async {
    mk.MediaKit.ensureInitialized();
    _player ??= mk.Player();
    _videoController ??= mkv.VideoController(_player!);
  }

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    final mk.Player player = _requirePlayer();
    await player.open(
      mk.Media(
        _mediaUri(source),
        httpHeaders: source.headers.isEmpty ? null : source.headers,
        start: state.position > Duration.zero ? state.position : null,
      ),
      play: false,
    );
    return _stateFromPlayer(
      state.copyWith(
        lifecycle: UnifiedVideoLifecycle.ready,
        source: source,
        activeKernelId: descriptor.id,
        clearError: true,
      ),
    );
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    return _stateFromPlayer(state);
  }

  @override
  Future<UnifiedVideoState> play(UnifiedVideoState state) async {
    final mk.Player player = _requirePlayer();
    await player.play();
    return _stateFromPlayer(state, UnifiedVideoLifecycle.playing);
  }

  @override
  Future<UnifiedVideoState> pause(UnifiedVideoState state) async {
    final mk.Player player = _requirePlayer();
    await player.pause();
    return _stateFromPlayer(state, UnifiedVideoLifecycle.paused);
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    final mk.Player player = _requirePlayer();
    await player.seek(position);
    return _stateFromPlayer(state);
  }

  @override
  Future<UnifiedVideoState> stop(UnifiedVideoState state) async {
    final mk.Player player = _requirePlayer();
    await player.stop();
    return _stateFromPlayer(
      state.copyWith(lifecycle: UnifiedVideoLifecycle.idle),
    );
  }

  @override
  Future<UnifiedVideoState> setSpeed(
    double speed,
    UnifiedVideoState state,
  ) async {
    final mk.Player player = _requirePlayer();
    await player.setRate(speed);
    return _stateFromPlayer(state).copyWith(speed: speed);
  }

  @override
  Future<UnifiedVideoState> setVolume(
    double volume,
    UnifiedVideoState state,
  ) async {
    await _requirePlayer().setVolume(volume * 100);
    return _stateFromPlayer(state).copyWith(volume: volume);
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
    final mkv.VideoController? controller = _videoController;
    if (controller == null) {
      return const ColoredBox(color: Colors.black);
    }
    return mkv.Video(
      controller: controller,
      controls: mkv.NoVideoControls,
      fit: _boxFitFor(state.fit),
    );
  }

  @override
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }

  mk.Player _requirePlayer() {
    final mk.Player? player = _player;
    if (player == null) {
      throw StateError('Media Kit 尚未初始化。');
    }
    return player;
  }

  UnifiedVideoState _stateFromPlayer(
    UnifiedVideoState state, [
    UnifiedVideoLifecycle? lifecycle,
  ]) {
    final mk.Player player = _requirePlayer();
    final mk.PlayerState value = player.state;
    final UnifiedVideoLifecycle resolvedLifecycle =
        lifecycle ??
        (value.completed
            ? UnifiedVideoLifecycle.ended
            : value.buffering
            ? UnifiedVideoLifecycle.buffering
            : value.playing
            ? UnifiedVideoLifecycle.playing
            : state.lifecycle);
    return state.copyWith(
      lifecycle: resolvedLifecycle,
      duration: value.duration,
      position: value.position,
      buffered: <BufferedRange>[
        if (value.buffer > Duration.zero)
          BufferedRange(start: Duration.zero, end: value.buffer),
      ],
      speed: value.rate,
      clearError: true,
    );
  }

  String _mediaUri(VideoSource source) {
    switch (source.type) {
      case VideoSourceType.asset:
        return 'asset:///${source.uri.path}';
      case VideoSourceType.file:
      case VideoSourceType.network:
        return source.uri.toString();
      case VideoSourceType.memory:
        throw UnsupportedError('Media Kit 适配器不支持 memory 播放源。');
    }
  }

  BoxFit _boxFitFor(UnifiedVideoFit fit) {
    switch (fit) {
      case UnifiedVideoFit.original:
      case UnifiedVideoFit.contain:
      case UnifiedVideoFit.ratio16x9:
      case UnifiedVideoFit.ratio4x3:
        return BoxFit.contain;
      case UnifiedVideoFit.fill:
        return BoxFit.fill;
      case UnifiedVideoFit.cover:
        return BoxFit.cover;
    }
  }
}
