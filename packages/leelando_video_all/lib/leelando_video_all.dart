library;

import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_fvp/leelando_video_fvp.dart';
import 'package:leelando_video_media_kit/leelando_video_media_kit.dart';
import 'package:leelando_video_video_player/leelando_video_video_player.dart';

export 'package:leelando_video/leelando_video.dart';
export 'package:leelando_video_fvp/leelando_video_fvp.dart';
export 'package:leelando_video_media_kit/leelando_video_media_kit.dart';
export 'package:leelando_video_video_player/leelando_video_video_player.dart';

List<RegisteredVideoKernel> createAllVideoKernels() {
  return <RegisteredVideoKernel>[
    createMediaKitVideoKernel(),
    createFvpVideoKernel(),
    createOfficialVideoPlayerKernel(),
  ];
}
