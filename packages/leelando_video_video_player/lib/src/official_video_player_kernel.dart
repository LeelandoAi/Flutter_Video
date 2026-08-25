import 'package:leelando_video/leelando_video.dart';

import 'video_player_kernel_base.dart';

RegisteredVideoKernel createOfficialVideoPlayerKernel() {
  return RegisteredVideoKernel(
    descriptor: officialVideoPlayerKernelDescriptor,
    create: OfficialVideoPlayerKernelAdapter.new,
  );
}

const VideoKernelDescriptor officialVideoPlayerKernelDescriptor =
    VideoKernelDescriptor(
      id: 'video-player',
      displayName: 'Flutter 官方 Video Player',
      supportedPlatforms: <UnifiedVideoPlatform>{
        UnifiedVideoPlatform.android,
        UnifiedVideoPlatform.ios,
        UnifiedVideoPlatform.macos,
      },
      supportedSourceTypes: <VideoSourceType>{
        VideoSourceType.asset,
        VideoSourceType.file,
        VideoSourceType.network,
      },
      supportsSubtitles: false,
      supportsTracks: false,
      knownLimitations: <String>[
        '官方 video_player 不覆盖 Windows。',
        '字幕和音轨选择能力需要上层或其他内核补齐。',
      ],
    );

class OfficialVideoPlayerKernelAdapter extends VideoPlayerKernelAdapterBase {
  @override
  VideoKernelDescriptor get descriptor => officialVideoPlayerKernelDescriptor;

  @override
  String get runtimeGroup => 'video-player-platform';

  @override
  String get runtimeIdentity => 'video-player-official';
}
