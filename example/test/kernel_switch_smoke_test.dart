import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video_all/leelando_video_all.dart';
import 'package:leelando_video_example/main.dart';

void main() {
  test('Demo 同时注册三个可切换内核', () {
    expect(
      createDemoKernelRegistry().descriptors.map((item) => item.id),
      <String>['media-kit', 'fvp', 'video-player'],
    );
  });

  test('短剧默认场景使用指定地址和 9:16 自动全屏方向', () {
    expect(
      shortDramaPlaybackScenario.source.uri.toString(),
      'http://qiniu.jxkfxz.com/wz_mp41213chunfengbushig1.mp4'
      '?sign=a212327e975c39bd42787ece2ca1254c&t=6a915f5d',
    );
    expect(shortDramaPlaybackScenario.aspectRatio, 9 / 16);
    expect(
      shortDramaPlaybackScenario.fullscreenOrientation,
      UnifiedVideoFullscreenOrientation.auto,
    );
  });

  testWidgets('Demo 默认播放器消费短剧的竖屏配置', (WidgetTester tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    final UnifiedVideoPlayer player = tester.widget<UnifiedVideoPlayer>(
      find.byType(UnifiedVideoPlayer),
    );
    expect(player.aspectRatio, 9 / 16);
    expect(
      player.fullscreenOrientation,
      UnifiedVideoFullscreenOrientation.auto,
    );
  });

  testWidgets('桌面端默认短剧播放器完整显示在首屏业务区域', (WidgetTester tester) async {
    // Catches the scroll page giving a 9:16 player the full desktop width,
    // which makes the player several viewport heights tall.
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    final Rect businessViewport = tester.getRect(find.byType(ListView));
    final Rect playerFrame = tester.getRect(
      find.byKey(const ValueKey<String>('player-frame')),
    );
    expect(playerFrame.top, greaterThanOrEqualTo(businessViewport.top));
    expect(playerFrame.bottom, lessThanOrEqualTo(businessViewport.bottom));
    expect(playerFrame.size.aspectRatio, closeTo(9 / 16, 0.001));
  });
}
