import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';
import 'package:lee_video_erika/lee_video_erika.dart';
import 'package:lee_video_fvp/lee_video_fvp.dart';
import 'package:lee_video_media_kit/lee_video_media_kit.dart';
import 'package:lee_video_video_player/lee_video_video_player.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MediaKit 工厂通过公开入口声明完整能力且无运行时组', () {
    final RegisteredVideoKernel kernel = createMediaKitVideoKernel();

    expect(kernel.descriptor.id, 'media-kit');
    expect(kernel.descriptor.supportedPlatforms, <UnifiedVideoPlatform>{
      UnifiedVideoPlatform.android,
      UnifiedVideoPlatform.ios,
      UnifiedVideoPlatform.windows,
      UnifiedVideoPlatform.macos,
    });
    expect(kernel.descriptor.supportedSourceTypes, <VideoSourceType>{
      VideoSourceType.asset,
      VideoSourceType.file,
      VideoSourceType.network,
    });

    final VideoKernelAdapter adapter = kernel.create();
    expect(adapter, isA<MediaKitVideoKernelAdapter>());
    expect(adapter.runtimeGroup, isNull);
  });

  test('Erika、MediaKit、FVP 与官方内核可同时注册', () {
    final VideoKernelRegistry registry = VideoKernelRegistry(
      kernels: <RegisteredVideoKernel>[
        createErikaVideoKernel(),
        createMediaKitVideoKernel(),
        createFvpVideoKernel(),
        createOfficialVideoPlayerKernel(),
      ],
    );

    expect(
      registry.descriptors.map((VideoKernelDescriptor item) => item.id),
      <String>['erika', 'media-kit', 'fvp', 'video-player'],
    );
  });

  test('MediaKit adapter 只创建、绑定并处置一次自有 Player', () async {
    final _OwnedPlayerMediaKitVideoKernelAdapter adapter =
        _OwnedPlayerMediaKitVideoKernelAdapter();

    await adapter.initialize();
    await adapter.initialize();

    expect(adapter.createPlayerCalls, 1);
    expect(adapter.initializeVideoSurfaceCalls, 1);
    expect(adapter.surfacePlayer, same(adapter.ownedPlayer));

    await adapter.dispose();
    await adapter.dispose();

    expect(adapter.platformPlayer.disposeCalls, 1);
  });

  test('MediaKit 将统一音量乘 100 后调用原生接口', () async {
    final _OwnedPlayerMediaKitVideoKernelAdapter adapter =
        _OwnedPlayerMediaKitVideoKernelAdapter();
    await adapter.initialize();
    addTearDown(adapter.dispose);

    final UnifiedVideoState result = await adapter.setVolume(
      0.42,
      const UnifiedVideoState(volume: 1),
    );

    expect(adapter.platformPlayer.volume, 42);
    expect(result.volume, 0.42);
  });

  test('MediaKit 将非零恢复进度保留为 Media start 提示', () async {
    final _OwnedPlayerMediaKitVideoKernelAdapter adapter =
        _OwnedPlayerMediaKitVideoKernelAdapter();
    await adapter.initialize();
    addTearDown(adapter.dispose);
    const Duration position = Duration(seconds: 37);
    final VideoSource source = VideoSource.network(
      'https://example.com/episode.mp4',
    );

    await adapter.open(source, const UnifiedVideoState(position: position));

    final mk.Media media = adapter.platformPlayer.openedPlayable! as mk.Media;
    expect(media.start, position);
    expect(adapter.platformPlayer.openPlay, isFalse);
  });
}

class _OwnedPlayerMediaKitVideoKernelAdapter
    extends MediaKitVideoKernelAdapter {
  final _RecordingPlatformPlayer platformPlayer = _RecordingPlatformPlayer();
  late final mk.Player ownedPlayer = mk.Player(platformPlayer: platformPlayer);

  int createPlayerCalls = 0;
  int initializeVideoSurfaceCalls = 0;
  mk.Player? surfacePlayer;

  @override
  void ensureMediaKitInitialized() {}

  @override
  mk.Player createPlayer() {
    createPlayerCalls += 1;
    return ownedPlayer;
  }

  @override
  void initializeVideoSurface(mk.Player player) {
    initializeVideoSurfaceCalls += 1;
    surfacePlayer = player;
  }
}

class _RecordingPlatformPlayer extends mk.PlatformPlayer {
  _RecordingPlatformPlayer()
    : super(configuration: const mk.PlayerConfiguration());

  double? volume;
  mk.Playable? openedPlayable;
  bool? openPlay;
  int disposeCalls = 0;

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    openedPlayable = playable;
    openPlay = play;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await super.dispose();
  }
}
