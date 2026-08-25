import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video_example/main.dart';

void main() {
  test('Demo 同时注册四个可切换内核', () {
    expect(
      createDemoKernelRegistry().descriptors.map((item) => item.id),
      <String>['erika', 'media-kit', 'fvp', 'video-player'],
    );
  });
}
