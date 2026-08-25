library;

import 'package:lee_video/lee_video.dart';
import 'package:lee_video_erika/lee_video_erika.dart';
import 'package:lee_video_fvp/lee_video_fvp.dart';
import 'package:lee_video_media_kit/lee_video_media_kit.dart';
import 'package:lee_video_video_player/lee_video_video_player.dart';

export 'package:lee_video/lee_video.dart';
export 'package:lee_video_erika/lee_video_erika.dart';
export 'package:lee_video_fvp/lee_video_fvp.dart';
export 'package:lee_video_media_kit/lee_video_media_kit.dart';
export 'package:lee_video_video_player/lee_video_video_player.dart';

List<RegisteredVideoKernel> createAllVideoKernels() {
  return <RegisteredVideoKernel>[
    createErikaVideoKernel(),
    createMediaKitVideoKernel(),
    createFvpVideoKernel(),
    createOfficialVideoPlayerKernel(),
  ];
}
