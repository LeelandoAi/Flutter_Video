import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_erika/leelando_video_erika.dart';
import 'package:leelando_video_fvp/leelando_video_fvp.dart';
import 'package:leelando_video_media_kit/leelando_video_media_kit.dart';
import 'package:leelando_video_video_player/leelando_video_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MediaKit 工厂通过公开入口声明完整能力且无运行时组', () {
    final RegisteredVideoKernel kernel = createMediaKitVideoKernel();

    expect(kernel.descriptor.id, 'media-kit');
    expect(kernel.descriptor.supportedPlatforms, <UnifiedVideoPlatform>{
      UnifiedVideoPlatform.android,
      UnifiedVideoPlatform.ios,
      UnifiedVideoPlatform.windows,
      UnifiedVideoPlatform.macos,
    });
    expect(kernel.descriptor.supportedSourceTypes, <VideoSourceType>{
      VideoSourceType.asset,
      VideoSourceType.file,
      VideoSourceType.network,
    });

    final VideoKernelAdapter adapter = kernel.create();
    expect(adapter, isA<MediaKitVideoKernelAdapter>());
    expect(adapter.runtimeGroup, isNull);
  });

  test('Erika、MediaKit、FVP 与官方内核可同时注册', () {
    final VideoKernelRegistry registry = VideoKernelRegistry(
      kernels: <RegisteredVideoKernel>[
        createErikaVideoKernel(),
        createMediaKitVideoKernel(),
        createFvpVideoKernel(),
        createOfficialVideoPlayerKernel(),
      ],
    );

    expect(
      registry.descriptors.map((VideoKernelDescriptor item) => item.id),
      <String>['erika', 'media-kit', 'fvp', 'video-player'],
    );
  });
}
