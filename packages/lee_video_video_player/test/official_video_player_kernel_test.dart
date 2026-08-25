import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';
import 'package:lee_video_video_player/lee_video_video_player.dart';

void main() {
  test('官方内核工厂声明正确能力和运行时身份', () {
    final RegisteredVideoKernel kernel = createOfficialVideoPlayerKernel();
    expect(kernel.descriptor.id, 'video-player');
    expect(
      kernel.descriptor.supportedPlatforms,
      contains(UnifiedVideoPlatform.ios),
    );
    final VideoKernelAdapter adapter = kernel.create();
    expect(adapter.runtimeGroup, 'video-player-platform');
    expect(adapter.runtimeIdentity, 'video-player-official');
  });
}
