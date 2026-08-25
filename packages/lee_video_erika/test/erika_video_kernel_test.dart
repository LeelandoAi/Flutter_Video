import 'package:erika_flutter/erika_flutter.dart' as erika;
import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';
import 'package:lee_video_erika/lee_video_erika.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Erika 工厂通过公开入口声明完整能力且无运行时组', () {
    final RegisteredVideoKernel kernel = createErikaVideoKernel();

    expect(kernel.descriptor.id, 'erika');
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
    expect(adapter, isA<ErikaVideoKernelAdapter>());
    expect(adapter.runtimeGroup, isNull);
  });

  test('Erika 音量使用原生 0 到 1 映射并更新统一状态', () async {
    final _RecordingErikaPlayer player = _RecordingErikaPlayer();
    final ErikaVideoKernelAdapter adapter = ErikaVideoKernelAdapter(
      player: player,
    );

    final UnifiedVideoState result = await adapter.setVolume(
      0.37,
      const UnifiedVideoState(volume: 1),
    );

    expect(player.volume, 0.37);
    expect(result.volume, 0.37);
  });

  test('Erika 打开本地播放源后恢复非零进度', () async {
    final _RecordingErikaPlayer player = _RecordingErikaPlayer();
    final ErikaVideoKernelAdapter adapter = ErikaVideoKernelAdapter(
      player: player,
    );
    const Duration position = Duration(seconds: 37);
    final VideoSource source = VideoSource.file('/tmp/episode.mp4');

    final UnifiedVideoState result = await adapter.open(
      source,
      const UnifiedVideoState(position: position),
    );

    expect(player.openedUri, '/tmp/episode.mp4');
    expect(player.seekPosition, position);
    expect(result.position, position);
  });
}

class _RecordingErikaPlayer extends erika.ErikaPlayer {
  double? volume;
  String? openedUri;
  Duration? seekPosition;

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> open(
    String uri, {
    Map<String, String>? httpHeaders,
    erika.ErikaMediaMetadata? metadata,
  }) async {
    openedUri = uri;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPosition = position;
  }
}
