import 'package:fvp/fvp.dart' as fvp;

import '../kernel.dart';
import '../models.dart';
import 'video_player_kernel_base.dart';

RegisteredVideoKernel createFvpVideoKernel() {
  return RegisteredVideoKernel(
    descriptor: fvpVideoKernelDescriptor,
    create: FvpVideoKernelAdapter.new,
  );
}

const VideoKernelDescriptor fvpVideoKernelDescriptor = VideoKernelDescriptor(
  id: 'fvp',
  displayName: 'FVP / libmdk',
  supportedPlatforms: <UnifiedVideoPlatform>{
    UnifiedVideoPlatform.android,
    UnifiedVideoPlatform.ios,
    UnifiedVideoPlatform.windows,
    UnifiedVideoPlatform.macos,
  },
  supportedSourceTypes: <VideoSourceType>{
    VideoSourceType.asset,
    VideoSourceType.file,
    VideoSourceType.network,
  },
  supportsSubtitles: true,
  supportsTracks: true,
  knownLimitations: <String>[
    'FVP 通过 registerWith 替换 video_player 平台实现；注册后同进程内 video_player 也会走 libmdk 平台实现。',
    '高级音轨/字幕选择需要后续在统一 API 中补充轨道选择命令。',
  ],
);

class FvpVideoKernelAdapter extends VideoPlayerKernelAdapterBase {
  static bool _registered = false;

  @override
  VideoKernelDescriptor get descriptor => fvpVideoKernelDescriptor;

  @override
  Future<void> initialize() async {
    if (!_registered) {
      fvp.registerWith();
      _registered = true;
    }
  }
}
