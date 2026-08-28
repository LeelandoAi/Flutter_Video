part of 'fvp_video_kernel.dart';

class FvpVideoKernelAdapter extends VideoKernelAdapter {
  VideoPlayerController? _controller;

  @override
  VideoKernelDescriptor get descriptor => fvpVideoKernelDescriptor;

  @override
  String get runtimeGroup => 'video-player-platform';

  @override
  String get runtimeIdentity => 'video-player-fvp';

  @override
  Future<void> activateRuntime() async {
    fvp.registerWith(
      options: createFvpRuntimeOptions(currentUnifiedVideoPlatform()),
    );
  }

  @override
  Future<void> deactivateRuntime() async {
    fvp.registerWith(options: <String, Object>{'platforms': const <String>[]});
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    await _controller?.dispose();
    _controller = _createController(source);
    await _controller!.initialize();
    final VideoDimensions? videoDimensions = _videoDimensions(
      _controller!.value,
    );
    return state.copyWith(
      lifecycle: UnifiedVideoLifecycle.ready,
      source: source,
      activeKernelId: descriptor.id,
      duration: _controller!.value.duration,
      position: _controller!.value.position,
      videoDimensions: videoDimensions,
      clearVideoDimensions: videoDimensions == null,
      clearError: true,
    );
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    return _stateFromController(state);
  }

  VideoPlayerController _createController(VideoSource source) {
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
    final VideoPlayerController controller = _requireController();
    await controller.play();
    return _stateFromController(state, UnifiedVideoLifecycle.playing);
  }

  @override
  Future<UnifiedVideoState> pause(UnifiedVideoState state) async {
    final VideoPlayerController controller = _requireController();
    await controller.pause();
    return _stateFromController(state, UnifiedVideoLifecycle.paused);
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    final VideoPlayerController controller = _requireController();
    await controller.seekTo(position);
    return _stateFromController(state);
  }

  @override
  Future<UnifiedVideoState> stop(UnifiedVideoState state) async {
    final VideoPlayerController controller = _requireController();
    await controller.pause();
    await controller.seekTo(Duration.zero);
    return _stateFromController(state, UnifiedVideoLifecycle.idle);
  }

  @override
  Future<UnifiedVideoState> setSpeed(
    double speed,
    UnifiedVideoState state,
  ) async {
    final VideoPlayerController controller = _requireController();
    await controller.setPlaybackSpeed(speed);
    return _stateFromController(state).copyWith(speed: speed);
  }

  @override
  Future<UnifiedVideoState> setFit(
    UnifiedVideoFit fit,
    UnifiedVideoState state,
  ) async {
    return state.copyWith(fit: fit);
  }

  @override
  Future<UnifiedVideoState> setVolume(
    double volume,
    UnifiedVideoState state,
  ) async {
    final VideoPlayerController controller = _requireController();
    await controller.setVolume(volume);
    return _stateFromController(state).copyWith(volume: volume);
  }

  @override
  Widget buildSurface(BuildContext context, UnifiedVideoState state) {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return FittedBox(
      fit: _boxFitFor(state.fit),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: _displayAspectRatio(controller.value),
        height: 1,
        child: VideoPlayer(controller),
      ),
    );
  }

  double _displayAspectRatio(VideoPlayerValue value) {
    final double aspectRatio = value.aspectRatio;
    return value.rotationCorrection % 180 == 0 ? aspectRatio : 1 / aspectRatio;
  }

  VideoDimensions? _videoDimensions(VideoPlayerValue value) {
    final Size size = value.size;
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return null;
    }
    return value.rotationCorrection % 180 == 0
        ? VideoDimensions(width: size.width, height: size.height)
        : VideoDimensions(width: size.height, height: size.width);
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

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }

  VideoPlayerController _requireController() {
    final VideoPlayerController? controller = _controller;
    if (controller == null) {
      throw StateError('${descriptor.displayName} 尚未打开播放源。');
    }
    return controller;
  }

  UnifiedVideoState _stateFromController(
    UnifiedVideoState state, [
    UnifiedVideoLifecycle? lifecycle,
  ]) {
    final VideoPlayerValue value = _requireController().value;
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
    final VideoDimensions? videoDimensions = _videoDimensions(value);
    return state.copyWith(
      lifecycle: resolvedLifecycle,
      duration: value.duration,
      position: value.position,
      videoDimensions: videoDimensions,
      clearVideoDimensions: videoDimensions == null,
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
