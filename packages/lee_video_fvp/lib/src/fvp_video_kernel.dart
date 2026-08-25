import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:lee_video/lee_video.dart';
import 'package:video_player/video_player.dart';

part 'fvp_video_player_adapter.dart';

RegisteredVideoKernel createFvpVideoKernel() {
  return RegisteredVideoKernel(
    descriptor: fvpVideoKernelDescriptor,
    create: _FvpVideoPlayerAdapter.new,
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
    'FVP 通过 registerWith 替换 video_player 平台实现，同一 View 仅支持与官方内核串行切换。',
    '不同 View 不能并发占用 FVP 与官方 video_player 平台实现。',
    '高级音轨和字幕选择需要后续在统一 API 中补充轨道选择命令。',
  ],
);
