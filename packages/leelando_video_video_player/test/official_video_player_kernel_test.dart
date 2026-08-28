import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_video_player/leelando_video_video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('官方内核工厂声明正确能力和运行时身份', () {
    final RegisteredVideoKernel kernel = createOfficialVideoPlayerKernel();
    expect(kernel.descriptor.id, 'video-player');
    expect(
      kernel.descriptor.supportedPlatforms,
      contains(UnifiedVideoPlatform.ios),
    );
    final VideoKernelAdapter adapter = kernel.create();
    expect(adapter.runtimeGroup, 'video-player-platform');
    expect(adapter.runtimeIdentity, 'video-player-official');
  });

  test('官方内核将音量委托给原生 controller 并返回统一音量状态', () async {
    final VideoPlayerPlatform previousPlatform = VideoPlayerPlatform.instance;
    final _RecordingVideoPlayerPlatform platform =
        _RecordingVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    final VideoKernelAdapter adapter = createOfficialVideoPlayerKernel()
        .create();
    addTearDown(adapter.dispose);

    await adapter.initialize();
    UnifiedVideoState state = await adapter.open(
      VideoSource.network('https://example.com/video.mp4'),
      const UnifiedVideoState(),
    );
    state = await adapter.setVolume(0.35, state);

    expect(state.volume, 0.35);
    expect(platform.calls, contains('volume:0.35'));
  });

  test('官方内核上报考虑旋转校正后的真实视频尺寸', () async {
    final VideoPlayerPlatform previousPlatform = VideoPlayerPlatform.instance;
    final _RecordingVideoPlayerPlatform platform =
        _RecordingVideoPlayerPlatform()
          ..videoSize = const Size(1920, 1080)
          ..rotationCorrection = 90;
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    final VideoKernelAdapter adapter = createOfficialVideoPlayerKernel()
        .create();
    addTearDown(adapter.dispose);

    await adapter.initialize();
    final UnifiedVideoState state = await adapter.open(
      VideoSource.network('https://example.com/rotated-short.mp4'),
      const UnifiedVideoState(),
    );

    expect(
      state.videoDimensions,
      const VideoDimensions(width: 1080, height: 1920),
    );
  });

  testWidgets('官方内核 contain Surface 保持视频原始宽高比', (WidgetTester tester) async {
    final VideoPlayerPlatform previousPlatform = VideoPlayerPlatform.instance;
    final _RecordingVideoPlayerPlatform platform =
        _RecordingVideoPlayerPlatform()..videoSize = const Size(640, 480);
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);
    final VideoKernelAdapter adapter = createOfficialVideoPlayerKernel()
        .create();
    addTearDown(adapter.dispose);

    await adapter.initialize();
    final UnifiedVideoState state = await adapter.open(
      VideoSource.network('https://example.com/video-4x3.mp4'),
      const UnifiedVideoState(),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Builder(
            builder: (BuildContext context) => SizedBox(
              width: 320,
              height: 180,
              child: adapter.buildSurface(context, state),
            ),
          ),
        ),
      ),
    );

    final RenderBox surface = tester.renderObject(
      find.byKey(const ValueKey<String>('recording-video-surface')),
    );
    final Offset topLeft = surface.localToGlobal(Offset.zero);
    final Offset bottomRight = surface.localToGlobal(
      surface.size.bottomRight(Offset.zero),
    );
    final Size renderedSize = Size(
      bottomRight.dx - topLeft.dx,
      bottomRight.dy - topLeft.dy,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(adapter.dispose);

    expect(renderedSize.width, closeTo(240, 0.001));
    expect(renderedSize.height, closeTo(180, 0.001));
  });
}

class _RecordingVideoPlayerPlatform extends VideoPlayerPlatform {
  final List<String> calls = <String>[];
  final Map<int, StreamController<VideoEvent>> _streams =
      <int, StreamController<VideoEvent>>{};
  int _nextPlayerId = 1;
  Size videoSize = const Size(1920, 1080);
  int rotationCorrection = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final int playerId = _nextPlayerId++;
    _streams[playerId] = StreamController<VideoEvent>.broadcast(sync: true);
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
          size: videoSize,
          rotationCorrection: rotationCorrection,
        ),
      );
    });
    return stream.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    await _streams.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('volume:$volume');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

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
