import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_media_kit/src/media_kit_mappings.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  test('MediaKit 原生音量映射为百分制', () {
    expect(mediaKitNativeVolume(0.42), 42.0);
  });

  test('MediaKit 将播放器宽高映射为统一真实视频尺寸', () {
    expect(
      mediaKitVideoDimensions(1080, 1920),
      const VideoDimensions(width: 1080, height: 1920),
    );
    expect(mediaKitVideoDimensions(null, 1920), isNull);
    expect(mediaKitVideoDimensions(0, 1920), isNull);
  });

  test('MediaKit 播放器快照将真实尺寸写入统一状态', () {
    final UnifiedVideoState state = mediaKitStateFromPlayer(
      const UnifiedVideoState(lifecycle: UnifiedVideoLifecycle.ready),
      const mk.PlayerState(
        width: 1080,
        height: 1920,
        duration: Duration(minutes: 2),
        position: Duration(seconds: 12),
      ),
    );

    expect(
      state.videoDimensions,
      const VideoDimensions(width: 1080, height: 1920),
    );
    expect(state.duration, const Duration(minutes: 2));
    expect(state.position, const Duration(seconds: 12));
  });

  test('MediaKit open 保留非零 start 提示且不自动播放', () {
    const Duration position = Duration(seconds: 37);
    final MediaKitOpenRequest request = createMediaKitOpenRequest(
      VideoSource.network('https://example.com/episode.mp4'),
      position,
    );

    expect(request.media.start, position);
    expect(request.play, isFalse);
  });
}
