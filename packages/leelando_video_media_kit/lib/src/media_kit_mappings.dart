import 'package:leelando_video/leelando_video.dart';
import 'package:media_kit/media_kit.dart' as mk;

double mediaKitNativeVolume(double volume) => volume * 100;

final class MediaKitOpenRequest {
  MediaKitOpenRequest({required this.media, required this.play});

  final mk.Media media;
  final bool play;
}

MediaKitOpenRequest createMediaKitOpenRequest(
  VideoSource source,
  Duration position,
) {
  return MediaKitOpenRequest(
    media: mk.Media(
      _mediaUri(source),
      httpHeaders: source.headers.isEmpty ? null : source.headers,
      start: position > Duration.zero ? position : null,
    ),
    play: false,
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
