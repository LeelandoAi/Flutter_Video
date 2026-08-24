import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';

void main() {
  test('GSYVideoPreviewVttParser 解析独立图片和雪碧图坐标', () {
    const String content = '''
WEBVTT

00:00:00.000 --> 00:00:01.000
160p-00001.jpg#xywh=0,0,284,160

00:00:01.000 --> 00:00:03.500
https://cdn.example.test/160p-00002.jpg
''';

    final GSYVideoPreviewProvider provider = const GSYVideoPreviewVttParser()
        .parse(
          content,
          baseUri: Uri.parse('https://cdn.example.test/previews/'),
        );

    expect(provider.frames, hasLength(2));

    final GSYVideoPreviewFrame first = provider.frames.first;
    expect(first.start, Duration.zero);
    expect(first.end, const Duration(seconds: 1));
    expect(
      first.imageUri.toString(),
      'https://cdn.example.test/previews/160p-00001.jpg',
    );
    expect(first.cropRect, const Rect.fromLTWH(0, 0, 284, 160));

    final GSYVideoPreviewFrame second = provider.frames.last;
    expect(second.start, const Duration(seconds: 1));
    expect(second.end, const Duration(seconds: 3, milliseconds: 500));
    expect(second.cropRect, isNull);
  });

  test('GSYVideoPreviewProvider 按拖动进度命中对应缩略图', () {
    const String content = '''
WEBVTT

00:00:00.000 --> 00:00:10.000
first.jpg

00:00:10.000 --> 00:00:20.000
second.jpg
''';

    final GSYVideoPreviewProvider provider = const GSYVideoPreviewVttParser()
        .parse(content);

    expect(
      provider.frameFor(const Duration(seconds: 5))?.imageUri.path,
      'first.jpg',
    );
    expect(
      provider.frameFor(const Duration(seconds: 12))?.imageUri.path,
      'second.jpg',
    );
    expect(
      provider.frameFor(const Duration(seconds: 22))?.imageUri.path,
      'second.jpg',
    );
  });
}
