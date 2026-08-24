import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';

void main() {
  test('注册表保留顺序并支持批量注册、查询和注销', () {
    final registry = VideoKernelRegistry();
    registry.registerAll(<RegisteredVideoKernel>[
      createFakeVideoKernel(id: 'first', displayName: '第一内核'),
      createFakeVideoKernel(id: 'second', displayName: '第二内核'),
    ]);

    expect(
      registry.descriptors.map((item) => item.id),
      <String>['first', 'second'],
    );
    expect(registry.contains('first'), isTrue);
    expect(registry.unregister('first')?.descriptor.id, 'first');
    expect(registry.contains('first'), isFalse);
  });

  test('重复内核 ID 抛出明确异常而不是静默覆盖', () {
    final registry = VideoKernelRegistry(
      kernels: <RegisteredVideoKernel>[createFakeVideoKernel(id: 'same')],
    );

    expect(
      () => registry.register(createFakeVideoKernel(id: 'same')),
      throwsA(isA<DuplicateVideoKernelException>()),
    );
  });

  test('重复内核异常提供中文诊断消息', () {
    expect(
      const DuplicateVideoKernelException('same').toString(),
      'DuplicateVideoKernelException(内核 ID 已重复注册: same)',
    );
  });
}
