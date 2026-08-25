import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';
import 'package:lee_video_fvp/lee_video_fvp.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingVideoPlayerPlatform platform;
  late VideoKernelAdapter adapter;

  setUp(() async {
    platform = _RecordingVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    adapter = createFvpVideoKernel().create();
    await adapter.initialize();
  });

  tearDown(() async {
    await adapter.dispose();
  });

  test('FVP 私有 controller wrapper 映射完整播放命令和 Surface', () async {
    UnifiedVideoState state = await adapter.open(
      VideoSource.network(
        'https://example.com/video.mp4',
        headers: const <String, String>{'Authorization': 'token'},
      ),
      const UnifiedVideoState(),
    );

    expect(state.lifecycle, UnifiedVideoLifecycle.ready);
    expect(state.activeKernelId, 'fvp');
    expect(state.duration, const Duration(minutes: 2));
    expect(platform.sources.single.uri, 'https://example.com/video.mp4');
    expect(platform.sources.single.httpHeaders, <String, String>{
      'Authorization': 'token',
    });

    state = await adapter.play(state);
    expect(state.lifecycle, UnifiedVideoLifecycle.playing);
    state = await adapter.pause(state);
    expect(state.lifecycle, UnifiedVideoLifecycle.paused);
    state = await adapter.seek(const Duration(seconds: 45), state);
    expect(state.position, const Duration(seconds: 45));
    state = await adapter.snapshot(state);
    expect(state.position, const Duration(seconds: 45));
    state = await adapter.setSpeed(1.5, state);
    expect(state.speed, 1.5);
    state = await adapter.play(state);
    state = await adapter.setFit(UnifiedVideoFit.cover, state);
    expect(state.fit, UnifiedVideoFit.cover);
    state = await adapter.setVolume(0.4, state);
    expect(state.volume, 0.4);
    expect(
      adapter.buildSurface(_UnusedBuildContext(), state),
      isA<VideoPlayer>(),
    );

    state = await adapter.stop(state);
    expect(state.lifecycle, UnifiedVideoLifecycle.idle);
    expect(state.position, Duration.zero);
    expect(
      platform.calls,
      containsAllInOrder(<String>[
        'play',
        'pause',
        'seek:45000',
        'play',
        'speed:1.5',
        'volume:0.4',
        'pause',
        'seek:0',
      ]),
    );
  });

  test('FVP open 支持 asset、file、network 并拒绝 memory', () async {
    UnifiedVideoState state = await adapter.open(
      VideoSource.asset('assets/movie.mp4'),
      const UnifiedVideoState(),
    );
    state = await adapter.open(VideoSource.file('/tmp/movie.mp4'), state);
    state = await adapter.open(
      VideoSource.network('https://example.com/movie.mp4'),
      state,
    );

    expect(
      platform.sources.map((DataSource source) => source.sourceType),
      <DataSourceType>[
        DataSourceType.asset,
        DataSourceType.file,
        DataSourceType.network,
      ],
    );
    await expectLater(
      adapter.open(
        VideoSource(
          uri: Uri.parse('memory:movie'),
          type: VideoSourceType.memory,
        ),
        state,
      ),
      throwsUnsupportedError,
    );
  });

  test('FVP adapter dispose 释放内部 VideoPlayerController', () async {
    await adapter.open(
      VideoSource.network('https://example.com/video.mp4'),
      const UnifiedVideoState(),
    );

    await adapter.dispose();

    expect(platform.calls.last, 'dispose');
  });
}

class _UnusedBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingVideoPlayerPlatform extends VideoPlayerPlatform {
  final List<String> calls = <String>[];
  final List<DataSource> sources = <DataSource>[];
  final Map<int, Duration> _positions = <int, Duration>{};
  final Map<int, StreamController<VideoEvent>> _streams =
      <int, StreamController<VideoEvent>>{};
  int _nextPlayerId = 1;

  @override
  Future<void> init() async {
    calls.add('init');
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final int playerId = _nextPlayerId++;
    final stream = StreamController<VideoEvent>.broadcast(sync: true);
    sources.add(options.dataSource);
    _positions[playerId] = Duration.zero;
    _streams[playerId] = stream;
    calls.add('create');
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final StreamController<VideoEvent> stream = _streams[playerId]!;
    scheduleMicrotask(() {
      stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 2),
          size: const Size(1920, 1080),
        ),
      );
    });
    return stream.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
    calls.add('dispose');
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _positions[playerId] = position;
    calls.add('seek:${position.inMilliseconds}');
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return _positions[playerId] ?? Duration.zero;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('volume:$volume');
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    calls.add('speed:$speed');
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  Widget buildView(int playerId) {
    return const SizedBox(key: ValueKey<String>('recording-video-surface'));
  }
}
