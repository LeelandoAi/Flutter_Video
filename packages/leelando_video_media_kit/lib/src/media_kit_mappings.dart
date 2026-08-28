import 'package:leelando_video/leelando_video.dart';
import 'package:media_kit/media_kit.dart' as mk;

double mediaKitNativeVolume(double volume) => volume * 100;

VideoDimensions? mediaKitVideoDimensions(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return VideoDimensions(width: width.toDouble(), height: height.toDouble());
}

UnifiedVideoState mediaKitStateFromPlayer(
  UnifiedVideoState state,
  mk.PlayerState value, [
  UnifiedVideoLifecycle? lifecycle,
]) {
  final UnifiedVideoLifecycle resolvedLifecycle =
      lifecycle ??
      (value.completed
          ? UnifiedVideoLifecycle.ended
          : value.buffering
          ? UnifiedVideoLifecycle.buffering
          : value.playing
          ? UnifiedVideoLifecycle.playing
          : state.lifecycle);
  final VideoDimensions? videoDimensions = mediaKitVideoDimensions(
    value.width,
    value.height,
  );
  return state.copyWith(
    lifecycle: resolvedLifecycle,
    duration: value.duration,
    position: value.position,
    videoDimensions: videoDimensions,
    clearVideoDimensions: videoDimensions == null,
    buffered: <BufferedRange>[
      if (value.buffer > Duration.zero)
        BufferedRange(start: Duration.zero, end: value.buffer),
    ],
    speed: value.rate,
    clearError: true,
  );
}

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
