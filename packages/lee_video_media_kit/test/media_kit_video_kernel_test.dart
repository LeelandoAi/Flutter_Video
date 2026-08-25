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

  test('MediaKit 将统一音量乘 100 后调用原生接口', () async {
    final _RecordingPlatformPlayer platformPlayer = _RecordingPlatformPlayer();
    final MediaKitVideoKernelAdapter adapter = MediaKitVideoKernelAdapter(
      nativePlayer: mk.Player(platformPlayer: platformPlayer),
    );

    final UnifiedVideoState result = await adapter.setVolume(
      0.42,
      const UnifiedVideoState(volume: 1),
    );

    expect(platformPlayer.volume, 42);
    expect(result.volume, 0.42);
  });

  test('MediaKit 将非零恢复进度保留为 Media start 提示', () async {
    final _RecordingPlatformPlayer platformPlayer = _RecordingPlatformPlayer();
    final MediaKitVideoKernelAdapter adapter = MediaKitVideoKernelAdapter(
      nativePlayer: mk.Player(platformPlayer: platformPlayer),
    );
    const Duration position = Duration(seconds: 37);
    final VideoSource source = VideoSource.network(
      'https://example.com/episode.mp4',
    );

    await adapter.open(source, const UnifiedVideoState(position: position));

    final mk.Media media = platformPlayer.openedPlayable! as mk.Media;
    expect(media.start, position);
    expect(platformPlayer.openPlay, isFalse);
  });
}

class _RecordingPlatformPlayer extends mk.PlatformPlayer {
  _RecordingPlatformPlayer()
    : super(configuration: const mk.PlayerConfiguration());

  double? volume;
  mk.Playable? openedPlayable;
  bool? openPlay;

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    openedPlayable = playable;
    openPlay = play;
  }
}
