import 'dart:async';
import 'dart:io';

import 'package:erika_flutter/erika_flutter.dart' as erika;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kernel.dart';
import '../models.dart';

RegisteredVideoKernel createErikaVideoKernel() {
  return RegisteredVideoKernel(
    descriptor: erikaVideoKernelDescriptor,
    create: ErikaVideoKernelAdapter.new,
  );
}

const VideoKernelDescriptor erikaVideoKernelDescriptor = VideoKernelDescriptor(
  id: 'erika',
  displayName: 'Erika / Rust Renderer',
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
  knownLimitations: <String>[
    '依赖 erika_flutter 原生插件和 Erika native library，构建机必须满足对应平台的 Rust、Xcode、NDK、MSVC 等工具链要求。',
    'Flutter asset 会先复制到系统临时文件，再以本地文件路径交给 Erika 打开。',
    '当前 Erika 官方预编译 macOS 运行库的 FFmpeg HTTPS 协议能力不稳定，网络 MP4 会先缓存到本地临时文件再打开。',
  ],
);

class ErikaVideoKernelAdapter implements VideoKernelAdapter {
  ErikaVideoKernelAdapter({erika.ErikaPlayer? player})
    : _player =
          player ?? erika.ErikaPlayer(outputMode: erika.ErikaOutputMode.auto);

  final erika.ErikaPlayer _player;
  StreamSubscription<erika.ErikaPlayerEvent>? _eventsSubscription;
  erika.ErikaPlayerEvent? _lastEvent;

  @override
  VideoKernelDescriptor get descriptor => erikaVideoKernelDescriptor;

  @override
  Future<void> initialize() async {
    await _player.ensureCreated();
    _eventsSubscription ??= _player.events.listen(
      (erika.ErikaPlayerEvent event) {
        _lastEvent = event;
      },
      onError: (Object error) {
        _lastEvent = erika.ErikaPlayerEvent(
          playerId: _player.id ?? 0,
          kind: erika.ErikaEventKind.error,
          state: erika.ErikaPlaybackState.error,
          duration: Duration.zero,
          position: Duration.zero,
          buffering: false,
          video: const erika.ErikaVideoParams(
            width: 0,
            height: 0,
            primaries: 0,
            transfer: 0,
          ),
          tracks: const erika.ErikaTrackCounts(video: 0, audio: 0, subtitle: 0),
          trackList: const <erika.ErikaTrackInfo>[],
          trackSelection: const erika.ErikaTrackSelection(
            video: null,
            audio: null,
            subtitle: null,
          ),
          error: error.toString(),
        );
      },
    );
  }

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    final String uri = await _mediaUri(source);
    await _player.open(
      uri,
      httpHeaders: source.headers.isEmpty ? null : source.headers,
      metadata: _metadataFor(source.metadata),
    );

    final Duration requestedPosition = state.position;
    if (requestedPosition > Duration.zero) {
      await _player.seek(requestedPosition);
    }

    return _stateFromEvent(
      state.copyWith(
        lifecycle: UnifiedVideoLifecycle.ready,
        source: source,
        position: requestedPosition,
        activeKernelId: descriptor.id,
        clearError: true,
      ),
      fallbackLifecycle: UnifiedVideoLifecycle.ready,
    );
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    return _stateFromEvent(state);
  }

  @override
  Future<UnifiedVideoState> play(UnifiedVideoState state) async {
    await _player.play();
    return _stateFromEvent(
      state.copyWith(lifecycle: UnifiedVideoLifecycle.playing),
      fallbackLifecycle: UnifiedVideoLifecycle.playing,
    );
  }

  @override
  Future<UnifiedVideoState> pause(UnifiedVideoState state) async {
    await _player.pause();
    return _stateFromEvent(
      state.copyWith(lifecycle: UnifiedVideoLifecycle.paused),
      fallbackLifecycle: UnifiedVideoLifecycle.paused,
    );
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    await _player.seek(position);
    return _stateFromEvent(state.copyWith(position: position));
  }

  @override
  Future<UnifiedVideoState> stop(UnifiedVideoState state) async {
    await _player.stop();
    return _stateFromEvent(
      state.copyWith(
        lifecycle: UnifiedVideoLifecycle.idle,
        position: Duration.zero,
      ),
      fallbackLifecycle: UnifiedVideoLifecycle.idle,
    );
  }

  @override
  Future<UnifiedVideoState> setSpeed(
    double speed,
    UnifiedVideoState state,
  ) async {
    await _player.setPlaybackRate(speed);
    return _stateFromEvent(state.copyWith(speed: speed)).copyWith(speed: speed);
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
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget videoView = _buildErikaVideoView();
          if (state.fit == UnifiedVideoFit.fill) {
            return SizedBox.expand(child: videoView);
          }

          final double maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 1280;
          final double maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 720;
          final Size sourceSize = _sourceSizeFor(state.fit);
          final FittedSizes fitted = applyBoxFit(
            _boxFitFor(state.fit),
            sourceSize,
            Size(maxWidth, maxHeight),
          );

          return ClipRect(
            child: Center(
              child: SizedBox(
                width: fitted.destination.width,
                height: fitted.destination.height,
                child: videoView,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErikaVideoView() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      return erika.ErikaWindowOverlayVideoView(
        player: _player,
        debugLabel: 'flutter_video_erika',
      );
    }
    return erika.ErikaVideoView(
      player: _player,
      debugLabel: 'flutter_video_erika',
    );
  }

  @override
  Future<void> dispose() async {
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _lastEvent = null;
    await _player.dispose();
  }

  UnifiedVideoState _stateFromEvent(
    UnifiedVideoState state, {
    UnifiedVideoLifecycle? fallbackLifecycle,
  }) {
    final erika.ErikaPlayerEvent? event = _lastEvent;
    if (event == null) {
      return state.copyWith(
        lifecycle: fallbackLifecycle ?? state.lifecycle,
        activeKernelId: descriptor.id,
        clearError: true,
      );
    }

    if (event.kind == erika.ErikaEventKind.error ||
        event.state == erika.ErikaPlaybackState.error) {
      return state.copyWith(
        lifecycle: UnifiedVideoLifecycle.failed,
        error: UnifiedVideoError(
          code: UnifiedVideoErrorCode.openFailed,
          message: 'Erika 播放失败。',
          backendMessage: event.error ?? event.message,
          diagnostics: <String, Object?>{
            'status': event.status,
            'decoder': event.decoder?.activeBackend,
          },
        ),
      );
    }

    return state.copyWith(
      lifecycle: _lifecycleFor(event, fallbackLifecycle ?? state.lifecycle),
      duration: event.duration > Duration.zero
          ? event.duration
          : state.duration,
      position: event.position,
      buffered: event.duration > Duration.zero
          ? <BufferedRange>[
              BufferedRange(start: Duration.zero, end: event.duration),
            ]
          : state.buffered,
      tracks: _tracksFor(event),
      activeKernelId: descriptor.id,
      clearError: true,
    );
  }

  UnifiedVideoLifecycle _lifecycleFor(
    erika.ErikaPlayerEvent event,
    UnifiedVideoLifecycle fallback,
  ) {
    if (event.buffering) {
      return UnifiedVideoLifecycle.buffering;
    }
    switch (event.state) {
      case erika.ErikaPlaybackState.idle:
        return UnifiedVideoLifecycle.idle;
      case erika.ErikaPlaybackState.opening:
        return UnifiedVideoLifecycle.opening;
      case erika.ErikaPlaybackState.ready:
        return UnifiedVideoLifecycle.ready;
      case erika.ErikaPlaybackState.playing:
        return UnifiedVideoLifecycle.playing;
      case erika.ErikaPlaybackState.paused:
        return UnifiedVideoLifecycle.paused;
      case erika.ErikaPlaybackState.stopped:
      case erika.ErikaPlaybackState.closed:
        return UnifiedVideoLifecycle.idle;
      case erika.ErikaPlaybackState.error:
        return UnifiedVideoLifecycle.failed;
    }
  }

  List<VideoTrack> _tracksFor(erika.ErikaPlayerEvent event) {
    return event.trackList
        .map(
          (erika.ErikaTrackInfo track) => VideoTrack(
            id: track.id.toString(),
            type: _trackTypeFor(track.kind),
            label: track.title ?? '${track.kind.name} ${track.id}',
            language: track.language,
            selected: _isSelected(track, event.trackSelection),
          ),
        )
        .toList(growable: false);
  }

  VideoTrackType _trackTypeFor(erika.ErikaTrackKind kind) {
    switch (kind) {
      case erika.ErikaTrackKind.video:
        return VideoTrackType.video;
      case erika.ErikaTrackKind.audio:
        return VideoTrackType.audio;
      case erika.ErikaTrackKind.subtitle:
        return VideoTrackType.subtitle;
    }
  }

  bool _isSelected(
    erika.ErikaTrackInfo track,
    erika.ErikaTrackSelection selection,
  ) {
    return switch (track.kind) {
      erika.ErikaTrackKind.video => selection.video == track.id,
      erika.ErikaTrackKind.audio => selection.audio == track.id,
      erika.ErikaTrackKind.subtitle => selection.subtitle == track.id,
    };
  }

  erika.ErikaMediaMetadata? _metadataFor(VideoMetadata metadata) {
    final String? title = metadata.title ?? metadata.episodeTitle;
    if (title == null || title.isEmpty) {
      return null;
    }
    return erika.ErikaMediaMetadata(title: title);
  }

  Future<String> _mediaUri(VideoSource source) async {
    switch (source.type) {
      case VideoSourceType.asset:
        return _copyAssetToTempFile(source.uri.path);
      case VideoSourceType.file:
        return source.uri.toFilePath();
      case VideoSourceType.network:
        return _downloadNetworkSourceToTempFile(source);
      case VideoSourceType.memory:
        throw UnsupportedError('Erika 适配器不支持 memory 播放源。');
    }
  }

  Future<String> _downloadNetworkSourceToTempFile(VideoSource source) async {
    final Uri uri = source.uri;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return uri.toString();
    }

    final String extension = _extensionFor(uri);
    final String fileName = '${_stableHash(uri.toString())}$extension';
    final Directory directory = Directory(
      '${Directory.systemTemp.path}/flutter_video_erika_network',
    );
    await directory.create(recursive: true);
    final File file = File('${directory.path}/$fileName');
    if (await file.exists() && await file.length() > 0) {
      return file.path;
    }

    final File partial = File('${file.path}.part');
    if (await partial.exists()) {
      await partial.delete();
    }

    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      for (final MapEntry<String, String> header in source.headers.entries) {
        request.headers.set(header.key, header.value);
      }
      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Erika 网络播放源下载失败，HTTP ${response.statusCode}。',
          uri: uri,
        );
      }
      final IOSink sink = partial.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }
      await partial.rename(file.path);
      return file.path;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _copyAssetToTempFile(String assetPath) async {
    final String sanitizedName = assetPath.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    final Directory directory = Directory(
      '${Directory.systemTemp.path}/flutter_video_erika_assets',
    );
    await directory.create(recursive: true);
    final File file = File('${directory.path}/$sanitizedName');
    if (!await file.exists()) {
      final ByteData data = await rootBundle.load(assetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  String _extensionFor(Uri uri) {
    final String lastSegment = uri.pathSegments.isEmpty
        ? ''
        : uri.pathSegments.last;
    final int dot = lastSegment.lastIndexOf('.');
    if (dot <= 0 || dot == lastSegment.length - 1) {
      return '.media';
    }
    final String extension = lastSegment.substring(dot);
    if (extension.length > 12) {
      return '.media';
    }
    return extension.replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
  }

  String _stableHash(String value) {
    int hash = 0x811c9dc5;
    for (final int unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Size _sourceSizeFor(UnifiedVideoFit fit) {
    switch (fit) {
      case UnifiedVideoFit.ratio16x9:
        return const Size(16, 9);
      case UnifiedVideoFit.ratio4x3:
        return const Size(4, 3);
      case UnifiedVideoFit.original:
      case UnifiedVideoFit.contain:
      case UnifiedVideoFit.fill:
      case UnifiedVideoFit.cover:
        final erika.ErikaVideoParams? video = _lastEvent?.video;
        if (video != null && video.width > 0 && video.height > 0) {
          return Size(video.width.toDouble(), video.height.toDouble());
        }
        return const Size(16, 9);
    }
  }

  BoxFit _boxFitFor(UnifiedVideoFit fit) {
    switch (fit) {
      case UnifiedVideoFit.cover:
        return BoxFit.cover;
      case UnifiedVideoFit.fill:
        return BoxFit.fill;
      case UnifiedVideoFit.original:
      case UnifiedVideoFit.ratio16x9:
      case UnifiedVideoFit.ratio4x3:
      case UnifiedVideoFit.contain:
        return BoxFit.contain;
    }
  }
}
