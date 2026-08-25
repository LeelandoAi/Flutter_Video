import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video_all/lee_video_all.dart';

void main() {
  test('全量工厂按稳定顺序返回四个真实内核', () {
    expect(
      createAllVideoKernels().map((kernel) => kernel.descriptor.id),
      <String>['erika', 'media-kit', 'fvp', 'video-player'],
    );
  });

  test('全量工厂每次调用返回新的可变列表', () {
    final List<RegisteredVideoKernel> first = createAllVideoKernels();
    final List<RegisteredVideoKernel> second = createAllVideoKernels();

    expect(first, isNot(same(second)));
  });

  test('全量工厂返回的 descriptor 标识唯一', () {
    final List<String> ids = createAllVideoKernels()
        .map((RegisteredVideoKernel kernel) => kernel.descriptor.id)
        .toList();

    expect(ids.toSet(), hasLength(4));
  });

  test('四个公开内核工厂可同时注册', () {
    final VideoKernelRegistry registry = VideoKernelRegistry(
      kernels: <RegisteredVideoKernel>[
        createErikaVideoKernel(),
        createMediaKitVideoKernel(),
        createFvpVideoKernel(),
        createOfficialVideoPlayerKernel(),
      ],
    );

    expect(
      registry.descriptors.map((descriptor) => descriptor.id),
      <String>['erika', 'media-kit', 'fvp', 'video-player'],
    );
  });
}
