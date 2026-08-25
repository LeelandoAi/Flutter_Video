import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video_media_kit/lee_video_media_kit.dart';

void main() {
  test('公开构造器不接受外部 native Player', () {
    expect(
      () => Function.apply(
        MediaKitVideoKernelAdapter.new,
        const <Object?>[],
        <Symbol, Object?>{#nativePlayer: null},
      ),
      throwsA(isA<NoSuchMethodError>()),
    );
  });
}
