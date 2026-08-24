import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_video/flutter_video.dart';

void main() {
  Future<UnifiedVideoController> pumpPlayer(
    WidgetTester tester, {
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    VoidCallback? onSwitchContent,
    Duration autoHideControlsDelay = const Duration(seconds: 3),
  }) async {
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[createFakeVideoKernel()],
      ),
      platform: UnifiedVideoPlatform.android,
      stateRefreshInterval: null,
    );
    await controller.open(
      VideoSource.network(
        sampleMp4Url,
        metadata: const VideoMetadata(title: '测试影片'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            onPrevious: onPrevious,
            onNext: onNext,
            onSwitchContent: onSwitchContent,
            autoHideControlsDelay: autoHideControlsDelay,
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('默认播放器显示必需控件和 fake 播放画面', (WidgetTester tester) async {
    await pumpPlayer(tester, onPrevious: () {}, onNext: () {});

    expect(
      find.byKey(const ValueKey<String>('fake-video-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('video-progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('previous-episode')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('next-episode')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('play-pause')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('settings-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('fit-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('speed-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('kernel-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('mirror-action')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('rotate')), findsOneWidget);
  });

  testWidgets('未提供上一集和下一集回调时按钮不可点击', (WidgetTester tester) async {
    await pumpPlayer(tester);

    final IconButton previous = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('previous-episode')),
        matching: find.byType(IconButton),
      ),
    );
    final IconButton next = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('next-episode')),
        matching: find.byType(IconButton),
      ),
    );

    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets('窄屏播放器控制栏不会横向溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPlayer(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('3 秒无触摸操作时控件自动隐藏，轻点播放器后重新显示', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      autoHideControlsDelay: const Duration(milliseconds: 200),
    );

    await controller.play();
    await tester.pump();
    expect(_controlsOverlay(tester).opacity, 1);

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsOverlay(tester).opacity, 0);

    await tester.tapAt(tester.getCenter(find.byType(UnifiedVideoPlayer)));
    await tester.pump();
    expect(_controlsOverlay(tester).opacity, 1);

    await tester.pump(const Duration(milliseconds: 120));
    await tester.tapAt(tester.getCenter(find.byType(UnifiedVideoPlayer)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_controlsOverlay(tester).opacity, 1);

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsOverlay(tester).opacity, 0);

    await controller.pause();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsOverlay(tester).opacity, 0);

    await tester.tapAt(tester.getCenter(find.byType(UnifiedVideoPlayer)));
    await tester.pump();
    expect(_controlsOverlay(tester).opacity, 1);
  });

  testWidgets('播放结束后不显示单独重播按钮，点击播放按钮从头播放', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpPlayer(tester);
    controller.value = controller.value.copyWith(
      lifecycle: UnifiedVideoLifecycle.ended,
      position: controller.value.duration,
    );
    await tester.pump();

    expect(find.byIcon(Icons.replay), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsOverlay(tester).opacity, 0);

    await tester.tapAt(tester.getCenter(find.byType(UnifiedVideoPlayer)));
    await tester.pump();
    expect(_controlsOverlay(tester).opacity, 1);

    await tester.tap(find.byKey(const ValueKey<String>('play-pause')));
    await tester.pump();
    await tester.pump();

    expect(controller.value.lifecycle, UnifiedVideoLifecycle.playing);
    expect(controller.value.position, Duration.zero);
  });

  testWidgets('UI 可以修改缩放、倍速和全屏状态', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpPlayer(tester);

    await tester.tap(find.byKey(const ValueKey<String>('fit-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('fit-option-cover')));
    await tester.pumpAndSettle();
    expect(controller.value.fit, UnifiedVideoFit.cover);

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('speed-option-1.25')));
    await tester.pumpAndSettle();
    expect(controller.value.speed, 1.25);

    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();
    expect(controller.value.fullscreen, isTrue);
  });

  testWidgets('设置面板按钮生效后自动关闭', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpPlayer(tester);

    await tester.tap(find.byKey(const ValueKey<String>('settings-menu')));
    await tester.pumpAndSettle();
    expect(find.text('播放设置'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('speed-option-1.25')));
    await tester.pumpAndSettle();
    expect(controller.value.speed, 1.25);
    expect(find.text('播放设置'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('settings-menu')));
    await tester.pumpAndSettle();
    expect(find.text('播放设置'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('fit-option-cover')));
    await tester.pumpAndSettle();
    expect(controller.value.fit, UnifiedVideoFit.cover);
    expect(find.text('播放设置'), findsNothing);
  });

  testWidgets('失败状态显示错误和重试按钮', (WidgetTester tester) async {
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          createOfficialVideoPlayerKernelPlaceholder(),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    await expectLater(
      controller.open(VideoSource.network(sampleMp4Url)),
      throwsA(isA<UnsupportedKernelException>()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnifiedVideoPlayer(controller: controller)),
      ),
    );
    addTearDown(controller.dispose);

    expect(
      find.byKey(const ValueKey<String>('video-error-message')),
      findsOneWidget,
    );
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('切换到失败内核时显示失败状态且不抛未处理异常', (WidgetTester tester) async {
    const VideoKernelDescriptor failingDescriptor = VideoKernelDescriptor(
      id: 'erika',
      displayName: 'Erika / Rust Renderer',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.macos},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          createFakeVideoKernel(),
          RegisteredVideoKernel(
            descriptor: failingDescriptor,
            create: () => _FailingOpenVideoKernelAdapter(failingDescriptor),
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.macos,
      stateRefreshInterval: null,
    );
    await controller.open(
      VideoSource.network(
        sampleMp4Url,
        metadata: const VideoMetadata(title: '测试影片'),
      ),
      preference: KernelPreference.exact('fake'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnifiedVideoPlayer(controller: controller)),
      ),
    );
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const ValueKey<String>('kernel-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('kernel-option-erika')));
    await tester.pumpAndSettle();

    expect(controller.value.lifecycle, UnifiedVideoLifecycle.failed);
    expect(
      find.byKey(const ValueKey<String>('video-error-message')),
      findsOneWidget,
    );
  });
}

AnimatedOpacity _controlsOverlay(WidgetTester tester) {
  return tester.widget<AnimatedOpacity>(
    find.byKey(const ValueKey<String>('player-controls-overlay')),
  );
}

class _FailingOpenVideoKernelAdapter extends FakeVideoKernelAdapter {
  _FailingOpenVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    throw StateError('模拟打开失败');
  }
}
