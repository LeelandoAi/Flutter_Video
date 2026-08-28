import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video_example/main.dart';

void main() {
  test('Demo 同时注册三个可切换内核', () {
    expect(
      createDemoKernelRegistry().descriptors.map((item) => item.id),
      <String>['media-kit', 'fvp', 'video-player'],
    );
  });
}
