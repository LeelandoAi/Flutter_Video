import '../kernel.dart';
import 'erika_video_kernel.dart';
import 'fvp_video_kernel.dart';
import 'media_kit_video_kernel.dart';
import 'official_video_player_kernel.dart';

RegisteredVideoKernel createMediaKitKernelPlaceholder() {
  return createMediaKitVideoKernel();
}

RegisteredVideoKernel createFvpKernelPlaceholder() {
  return createFvpVideoKernel();
}

RegisteredVideoKernel createOfficialVideoPlayerKernelPlaceholder() {
  return createOfficialVideoPlayerKernel();
}

RegisteredVideoKernel createErikaKernelPlaceholder() {
  return createErikaVideoKernel();
}
