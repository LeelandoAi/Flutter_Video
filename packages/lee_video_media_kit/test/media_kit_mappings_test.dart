import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';
import 'package:lee_video_media_kit/src/media_kit_mappings.dart';

void main() {
  test('MediaKit 原生音量映射为百分制', () {
    expect(mediaKitNativeVolume(0.42), 42.0);
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
