import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';

void main() {
  test('核心包通过 leelando_video 公共入口导出统一 API', () {
    final VideoSource source = VideoSource.network(
      'https://example.com/video.mp4',
    );

    expect(source.type, VideoSourceType.network);
  });
}
