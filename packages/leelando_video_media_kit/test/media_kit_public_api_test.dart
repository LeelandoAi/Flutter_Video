import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video_media_kit/leelando_video_media_kit.dart';

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

  test('公开 adapter 不允许外部继承并替换 Player 创建', () async {
    final File fixture = File(
      '${Directory.current.path}/.dart_tool/'
      'media_kit_external_subclass_contract.dart',
    );
    await fixture.writeAsString('''
import 'package:leelando_video_media_kit/leelando_video_media_kit.dart';

final class ExternalMediaKitAdapter extends MediaKitVideoKernelAdapter {}

void main() {
  MediaKitVideoKernelAdapter();
}
''');

    try {
      final String? flutterRoot = Platform.environment['FLUTTER_ROOT'];
      final String dartExecutable = flutterRoot == null
          ? 'dart'
          : '$flutterRoot/bin/cache/dart-sdk/bin/dart'
                '${Platform.isWindows ? '.exe' : ''}';
      final ProcessResult result = await Process.run(dartExecutable, <String>[
        'analyze',
        '--format=machine',
        fixture.path,
      ], workingDirectory: Directory.current.path);
      final String output = '${result.stdout}\n${result.stderr}';

      expect(result.exitCode, isNot(0), reason: output);
      expect(output, contains('INVALID_USE_OF_TYPE_OUTSIDE_LIBRARY'));
    } finally {
      if (await fixture.exists()) {
        await fixture.delete();
      }
    }
  });
}
