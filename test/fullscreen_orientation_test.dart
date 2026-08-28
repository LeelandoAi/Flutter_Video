import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';

void main() {
  group('自动全屏方向', () {
    test('Android 和 iOS 优先使用内核上报的真实视频尺寸', () {
      for (final UnifiedVideoPlatform platform in <UnifiedVideoPlatform>[
        UnifiedVideoPlatform.android,
        UnifiedVideoPlatform.ios,
      ]) {
        expect(
          resolveUnifiedVideoFullscreenOrientation(
            configuredOrientation: UnifiedVideoFullscreenOrientation.auto,
            platform: platform,
            aspectRatio: 16 / 9,
            videoDimensions: const VideoDimensions(width: 1080, height: 1920),
          ),
          UnifiedVideoFullscreenOrientation.portrait,
        );
        expect(
          resolveUnifiedVideoFullscreenOrientation(
            configuredOrientation: UnifiedVideoFullscreenOrientation.auto,
            platform: platform,
            aspectRatio: 9 / 16,
            videoDimensions: const VideoDimensions(width: 1920, height: 1080),
          ),
          UnifiedVideoFullscreenOrientation.landscape,
        );
      }
    });

    test('移动端尺寸未知、无效或为正方形时默认竖屏', () {
      for (final VideoDimensions? dimensions in <VideoDimensions?>[
        null,
        const VideoDimensions(width: 0, height: 0),
        const VideoDimensions(width: 1080, height: 1080),
      ]) {
        expect(
          resolveUnifiedVideoFullscreenOrientation(
            configuredOrientation: UnifiedVideoFullscreenOrientation.auto,
            platform: UnifiedVideoPlatform.android,
            aspectRatio: 16 / 9,
            videoDimensions: dimensions,
          ),
          UnifiedVideoFullscreenOrientation.portrait,
        );
      }
    });

    test('桌面端保持按外部比例判断的旧逻辑', () {
      expect(
        resolveUnifiedVideoFullscreenOrientation(
          configuredOrientation: UnifiedVideoFullscreenOrientation.auto,
          platform: UnifiedVideoPlatform.macos,
          aspectRatio: 16 / 9,
          videoDimensions: const VideoDimensions(width: 1080, height: 1920),
        ),
        UnifiedVideoFullscreenOrientation.landscape,
      );
      expect(
        resolveUnifiedVideoFullscreenOrientation(
          configuredOrientation: UnifiedVideoFullscreenOrientation.auto,
          platform: UnifiedVideoPlatform.windows,
          aspectRatio: 9 / 16,
          videoDimensions: const VideoDimensions(width: 1920, height: 1080),
        ),
        UnifiedVideoFullscreenOrientation.portrait,
      );
    });

    test('明确指定横屏或竖屏时不受真实尺寸影响', () {
      expect(
        resolveUnifiedVideoFullscreenOrientation(
          configuredOrientation: UnifiedVideoFullscreenOrientation.landscape,
          platform: UnifiedVideoPlatform.android,
          aspectRatio: 9 / 16,
          videoDimensions: const VideoDimensions(width: 1080, height: 1920),
        ),
        UnifiedVideoFullscreenOrientation.landscape,
      );
    });
  });
}
