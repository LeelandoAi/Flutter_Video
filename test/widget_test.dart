import 'dart:async';
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';

void main() {
  late _DelayedOpenVideoKernelAdapter delayedSwitchAdapter;

  Future<UnifiedVideoController> pumpPlayer(
    WidgetTester tester, {
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    VoidCallback? onSwitchContent,
    Duration autoHideControlsDelay = const Duration(seconds: 3),
    UnifiedVideoPlatform platform = UnifiedVideoPlatform.android,
    List<VideoEpisode> episodes = const <VideoEpisode>[],
    String? initialEpisodeId,
    ValueChanged<VideoEpisode>? onEpisodeChanged,
    Size viewSize = const Size(800, 600),
    double viewPaddingLeft = 0,
    double viewPaddingRight = 0,
    double viewPaddingBottom = 0,
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = FakeViewPadding(
      left: viewPaddingLeft,
      right: viewPaddingRight,
      bottom: viewPaddingBottom,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[createFakeVideoKernel()],
      ),
      platform: platform,
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
            episodes: episodes,
            initialEpisodeId: initialEpisodeId,
            onEpisodeChanged: onEpisodeChanged,
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<UnifiedVideoController> pumpSwitchablePlayer(
    WidgetTester tester,
  ) async {
    const VideoKernelDescriptor delayedDescriptor = VideoKernelDescriptor(
      id: 'delayed',
      displayName: '延迟测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    delayedSwitchAdapter = _DelayedOpenVideoKernelAdapter(delayedDescriptor);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          createFakeVideoKernel(),
          RegisteredVideoKernel(
            descriptor: delayedDescriptor,
            create: () => delayedSwitchAdapter,
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.android,
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
    return controller;
  }

  void completeDelayedOpen() => delayedSwitchAdapter.completeOpen();

  List<VideoEpisode> testEpisodes() => <VideoEpisode>[
    VideoEpisode(
      id: 'e1',
      title: '第 1 集',
      subtitle: '启程',
      source: VideoSource.network('https://example.com/e1.mp4'),
    ),
    VideoEpisode(
      id: 'e2',
      title: '第 2 集',
      subtitle: '雾港',
      source: VideoSource.network('https://example.com/e2.mp4'),
    ),
    VideoEpisode(
      id: 'e3',
      title: '第 3 集',
      subtitle: '回声',
      source: VideoSource.network('https://example.com/e3.mp4'),
    ),
  ];

  UnifiedVideoController createFakeController() {
    return UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[createFakeVideoKernel()],
      ),
      platform: UnifiedVideoPlatform.android,
      stateRefreshInterval: null,
    );
  }

  testWidgets('传入选集后上一集和下一集由播放器直接打开', (WidgetTester tester) async {
    // Catches navigation regressing to the legacy next callback.
    final List<VideoEpisode> episodes = <VideoEpisode>[
      VideoEpisode(
        id: 'e1',
        title: '第 1 集',
        source: VideoSource.network('https://example.com/e1.mp4'),
      ),
      VideoEpisode(
        id: 'e2',
        title: '第 2 集',
        source: VideoSource.network('https://example.com/e2.mp4'),
      ),
      VideoEpisode(
        id: 'e3',
        title: '第 3 集',
        source: VideoSource.network('https://example.com/e3.mp4'),
      ),
    ];
    final List<String> changed = <String>[];
    int legacyNextCalls = 0;
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      episodes: episodes,
      initialEpisodeId: 'e2',
      onEpisodeChanged: (VideoEpisode episode) => changed.add(episode.id),
      onNext: () => legacyNextCalls += 1,
    );

    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();

    expect(controller.value.source?.uri, episodes[2].source.uri);
    expect(changed, <String>['e3']);
    expect(legacyNextCalls, 0);
  });

  testWidgets('首集上一集和末集下一集禁用且不回退旧回调', (WidgetTester tester) async {
    // Catches boundary buttons delegating to legacy callbacks.
    int previousCalls = 0;
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      onPrevious: () => previousCalls += 1,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('previous-episode')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(previousCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    int nextCalls = 0;
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e3',
      onNext: () => nextCalls += 1,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('next-episode')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(nextCalls, 0);
  });

  testWidgets('未传选集时上一集仍调用旧回调', (WidgetTester tester) async {
    // Catches loss of the legacy navigation contract when episodes are absent.
    int calls = 0;
    await pumpPlayer(tester, onPrevious: () => calls++);

    await tester.tap(find.byKey(const ValueKey<String>('previous-episode')));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('重复选集 ID 在建立播放器时失败', (WidgetTester tester) async {
    // Catches ambiguous active-episode resolution from duplicate IDs.
    final List<VideoEpisode> episodes = <VideoEpisode>[
      VideoEpisode(
        id: 'duplicate',
        title: '第 1 集',
        source: VideoSource.network('https://example.com/e1.mp4'),
      ),
      VideoEpisode(
        id: 'duplicate',
        title: '第 2 集',
        source: VideoSource.network('https://example.com/e2.mp4'),
      ),
    ];

    await pumpPlayer(tester, episodes: episodes);

    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('空白选集标题在建立播放器时失败', (WidgetTester tester) async {
    // Catches invalid episode labels reaching the future picker UI.
    final List<VideoEpisode> episodes = <VideoEpisode>[
      VideoEpisode(
        id: 'e1',
        title: '   ',
        source: VideoSource.network('https://example.com/e1.mp4'),
      ),
    ];

    await pumpPlayer(tester, episodes: episodes);

    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('initialEpisodeId 只建立高亮且不会自动打开播放源', (WidgetTester tester) async {
    // Catches initial selection eagerly opening its source during first build.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'counting',
      displayName: '计数测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _CountingOpenVideoKernelAdapter adapter =
        _CountingOpenVideoKernelAdapter(descriptor);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: testEpisodes(),
            initialEpisodeId: 'e2',
          ),
        ),
      ),
    );

    expect(adapter.openCount, 0);
    expect(controller.value.source, isNull);
  });

  testWidgets('替换控制器后按新控制器播放源同步活动选集', (WidgetTester tester) async {
    // Catches controller replacement incorrectly reapplying initialEpisodeId.
    final List<VideoEpisode> episodes = testEpisodes();
    final UnifiedVideoController firstController = createFakeController();
    final UnifiedVideoController replacementController = createFakeController();
    addTearDown(firstController.dispose);
    addTearDown(replacementController.dispose);
    await firstController.open(episodes[0].source);
    await replacementController.open(episodes[0].source);
    UnifiedVideoController visibleController = firstController;
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: visibleController,
                episodes: episodes,
                initialEpisodeId: 'e2',
              );
            },
          ),
        ),
      ),
    );

    updateHost(() => visibleController = replacementController);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();

    expect(replacementController.value.source?.uri, episodes[1].source.uri);
  });

  testWidgets('旧控制器延迟打开不会覆盖新控制器状态或回调', (WidgetTester tester) async {
    // Catches an old async open mutating the replacement controller's player.
    const VideoKernelDescriptor delayedDescriptor = VideoKernelDescriptor(
      id: 'episode-delayed',
      displayName: '选集延迟内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _DelayedOpenVideoKernelAdapter delayedAdapter =
        _DelayedOpenVideoKernelAdapter(delayedDescriptor);
    final UnifiedVideoController firstController = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: delayedDescriptor,
            create: () => delayedAdapter,
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.android,
      stateRefreshInterval: null,
    );
    final UnifiedVideoController replacementController = createFakeController();
    addTearDown(firstController.dispose);
    addTearDown(replacementController.dispose);
    final List<VideoEpisode> episodes = testEpisodes();
    await replacementController.open(episodes[0].source);
    UnifiedVideoController visibleController = firstController;
    bool usingReplacementCallback = false;
    final List<String> replacementChanges = <String>[];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: visibleController,
                episodes: episodes,
                initialEpisodeId: 'e1',
                onEpisodeChanged: (VideoEpisode episode) {
                  if (usingReplacementCallback) {
                    replacementChanges.add(episode.id);
                  }
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pump();

    updateHost(() {
      visibleController = replacementController;
      usingReplacementCallback = true;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();
    expect(replacementController.value.source?.uri, episodes[1].source.uri);
    expect(replacementChanges, <String>['e2']);

    delayedAdapter.completeOpen();
    await tester.pumpAndSettle();

    expect(replacementController.value.source?.uri, episodes[1].source.uri);
    expect(replacementChanges, <String>['e2']);
  });

  testWidgets('控制器 A 经 B 重装后旧打开不会触发当前回调', (WidgetTester tester) async {
    // Catches a stale A open becoming valid again after an A→B→A swap.
    const VideoKernelDescriptor delayedDescriptor = VideoKernelDescriptor(
      id: 'episode-delayed-reinstall',
      displayName: '选集重装延迟内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _DelayedOpenVideoKernelAdapter delayedAdapter =
        _DelayedOpenVideoKernelAdapter(delayedDescriptor);
    final UnifiedVideoController firstController = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: delayedDescriptor,
            create: () => delayedAdapter,
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.android,
      stateRefreshInterval: null,
    );
    final UnifiedVideoController replacementController = createFakeController();
    addTearDown(firstController.dispose);
    addTearDown(replacementController.dispose);
    final List<VideoEpisode> episodes = testEpisodes();
    await replacementController.open(episodes[0].source);
    UnifiedVideoController visibleController = firstController;
    int callbackGeneration = 0;
    final List<String> changes = <String>[];
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: visibleController,
                episodes: episodes,
                initialEpisodeId: 'e1',
                onEpisodeChanged: (VideoEpisode episode) {
                  changes.add('$callbackGeneration:${episode.id}');
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pump();
    updateHost(() {
      visibleController = replacementController;
      callbackGeneration = 1;
    });
    await tester.pumpAndSettle();
    updateHost(() {
      visibleController = firstController;
      callbackGeneration = 2;
    });
    await tester.pump();

    delayedAdapter.completeOpen();
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
  });

  testWidgets('后续外部播放源变更会重匹配活动选集', (WidgetTester tester) async {
    // Catches controller source changes leaving the old active episode selected.
    final List<VideoEpisode> episodes = testEpisodes();
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      episodes: episodes,
      initialEpisodeId: 'e1',
    );

    await controller.open(episodes[1].source);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();

    expect(controller.value.source?.uri, episodes[2].source.uri);
  });

  testWidgets('更新选集列表时保留仍存在的活动选集', (WidgetTester tester) async {
    // Catches list updates discarding an active ID that remains available.
    final List<VideoEpisode> episodes = testEpisodes();
    final UnifiedVideoController controller = createFakeController();
    addTearDown(controller.dispose);
    List<VideoEpisode> visibleEpisodes = episodes;
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: controller,
                episodes: visibleEpisodes,
                initialEpisodeId: 'e2',
              );
            },
          ),
        ),
      ),
    );

    updateHost(() {
      visibleEpisodes = <VideoEpisode>[episodes[1], episodes[0], episodes[2]];
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();

    expect(controller.value.source?.uri, episodes[0].source.uri);
  });

  testWidgets('移除活动选集后按当前播放源重匹配', (WidgetTester tester) async {
    // Catches removal of the active episode leaving stale navigation state.
    final List<VideoEpisode> episodes = testEpisodes();
    final UnifiedVideoController controller = createFakeController();
    addTearDown(controller.dispose);
    await controller.open(episodes[0].source);
    List<VideoEpisode> visibleEpisodes = episodes;
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: controller,
                episodes: visibleEpisodes,
                initialEpisodeId: 'e2',
              );
            },
          ),
        ),
      ),
    );

    updateHost(
      () => visibleEpisodes = <VideoEpisode>[episodes[0], episodes[2]],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();

    expect(controller.value.source?.uri, episodes[2].source.uri);
  });

  testWidgets('无法重匹配时清除已移除的活动选集', (WidgetTester tester) async {
    // Catches an unresolved list update retaining a stale active ID.
    final List<VideoEpisode> episodes = testEpisodes();
    final UnifiedVideoController controller = createFakeController();
    addTearDown(controller.dispose);
    List<VideoEpisode> visibleEpisodes = episodes;
    int legacyNextCalls = 0;
    late StateSetter updateHost;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: controller,
                episodes: visibleEpisodes,
                initialEpisodeId: 'e2',
                onNext: () => legacyNextCalls += 1,
              );
            },
          ),
        ),
      ),
    );

    updateHost(
      () => visibleEpisodes = <VideoEpisode>[episodes[0], episodes[2]],
    );
    await tester.pumpAndSettle();
    updateHost(() => visibleEpisodes = episodes);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pump();

    expect(legacyNextCalls, 1);
    expect(controller.value.source, isNull);
  });

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
    expect(find.byKey(const ValueKey<String>('more-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('speed-menu')), findsOneWidget);
  });

  testWidgets('主控行不保留旧中央与底部的重复运输控件', (WidgetTester tester) async {
    // Catches the obsolete center transport and horizontal action strip returning.
    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    expect(
      find.byKey(const ValueKey<String>('action-play-pause')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('previous-episode-action')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('next-episode-action')),
      findsNothing,
    );
  });

  testWidgets('倍速选中态使用视频背景上的蓝色强调', (WidgetTester tester) async {
    // Catches the retired yellow menu-selection treatment returning.
    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    final Text selectedSpeed = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('speed-option-1.0')),
        matching: find.text('1.0x'),
      ),
    );

    expect(selectedSpeed.style?.color, const Color(0xFF7EC3FF));
  });

  testWidgets('竖屏嵌入隐藏选集且主控没有可见背景', (WidgetTester tester) async {
    // Catches compact layouts exposing episodes or restoring a toolbar surface.
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      viewSize: const Size(393, 852),
    );

    expect(find.byKey(const ValueKey<String>('episode-picker')), findsNothing);
    final Finder controls = find.byKey(
      const ValueKey<String>('primary-controls-row'),
    );
    expect(controls, findsOneWidget);
    expect(
      find.descendant(of: controls, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
  });

  testWidgets('桌面宽布局显示选集并保持 44 像素热区', (WidgetTester tester) async {
    // Catches wide mode hiding episodes or shrinking the primary hit target.
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    expect(
      find.byKey(const ValueKey<String>('episode-picker')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('play-pause'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('嵌入主控行严格使用移动 1 和桌面 2 的底距', (WidgetTester tester) async {
    // Catches compact or wide controls drifting away from the visual baseline.
    await pumpPlayer(tester, viewSize: const Size(393, 852));
    final double mobileBottom = tester
        .getBottomRight(find.byKey(const ValueKey<String>('player-frame')))
        .dy;
    final double mobileControlsBottom = tester
        .getBottomRight(
          find.byKey(const ValueKey<String>('primary-controls-row')),
        )
        .dy;
    expect(mobileBottom - mobileControlsBottom, 1);

    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    final double desktopBottom = tester
        .getBottomRight(find.byKey(const ValueKey<String>('player-frame')))
        .dy;
    final double desktopControlsBottom = tester
        .getBottomRight(
          find.byKey(const ValueKey<String>('primary-controls-row')),
        )
        .dy;
    expect(desktopBottom - desktopControlsBottom, 2);
  });

  testWidgets('手机横屏主控贴住系统底部安全区', (WidgetTester tester) async {
    // Catches expanded mode hard-coding a device inset or adding visual padding.
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      viewSize: const Size(852, 393),
      viewPaddingBottom: 21,
    );

    final double playerBottom = tester
        .getBottomRight(find.byKey(const ValueKey<String>('player-frame')))
        .dy;
    final double controlsBottom = tester
        .getBottomRight(
          find.byKey(const ValueKey<String>('primary-controls-row')),
        )
        .dy;
    expect(playerBottom - controlsBottom, 21);
    expect(
      find.byKey(const ValueKey<String>('episode-picker')),
      findsOneWidget,
    );
  });

  testWidgets('手机横屏主控遵守左右安全区和视觉边界', (WidgetTester tester) async {
    // Catches Expanded mode dropping asymmetric horizontal safe-area insets.
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      viewSize: const Size(852, 393),
      viewPaddingLeft: 51,
      viewPaddingRight: 6,
    );

    final Finder frame = find.byKey(const ValueKey<String>('player-frame'));
    final Finder controls = find.byKey(
      const ValueKey<String>('primary-controls-row'),
    );
    expect(tester.getTopLeft(controls).dx - tester.getTopLeft(frame).dx, 59);
    expect(tester.getTopRight(frame).dx - tester.getTopRight(controls).dx, 30);
  });

  testWidgets('进度拖动热区至少 44 且视觉轨道保持 2 与 3', (WidgetTester tester) async {
    // Catches the slider render/hit box collapsing to the visual track region.
    final UnifiedVideoController compactController = await pumpPlayer(
      tester,
      viewSize: const Size(393, 852),
    );
    compactController.value = compactController.value.copyWith(
      duration: const Duration(seconds: 100),
      position: Duration.zero,
    );
    await tester.pump();

    final Finder compactProgress = find.byKey(
      const ValueKey<String>('video-progress'),
    );
    expect(tester.getSize(compactProgress).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .widget<SliderTheme>(
            find.ancestor(
              of: compactProgress,
              matching: find.byType(SliderTheme),
            ),
          )
          .data
          .trackHeight,
      2,
    );
    final Rect compactRect = tester.getRect(compactProgress);
    await tester.tapAt(
      Offset(compactRect.left + compactRect.width * 0.75, compactRect.top + 2),
    );
    await tester.pump();
    expect(compactController.value.position.inSeconds, greaterThan(50));

    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    final Finder wideProgress = find.byKey(
      const ValueKey<String>('video-progress'),
    );
    expect(tester.getSize(wideProgress).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .widget<SliderTheme>(
            find.ancestor(of: wideProgress, matching: find.byType(SliderTheme)),
          )
          .data
          .trackHeight,
      3,
    );
  });

  testWidgets('更多面板交互项保持 44 热区', (WidgetTester tester) async {
    // Catches legacy settings actions retaining their old 34-pixel targets.
    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();

    final Finder speedOption = find.byKey(
      const ValueKey<String>('speed-option-1.25'),
    );
    expect(tester.getSize(speedOption).height, greaterThanOrEqualTo(44));
    await tester.tap(speedOption);
    await tester.pumpAndSettle();
    expect(find.text('播放设置'), findsNothing);
  });

  testWidgets('弹幕开关同时更新语义蓝色和实心图标', (WidgetTester tester) async {
    // Catches danmaku state being conveyed by neither semantics nor a visual signal.
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpPlayer(tester, viewSize: const Size(393, 852));
    final Finder toggle = find.byKey(const ValueKey<String>('danmaku-toggle'));

    expect(tester.getSemantics(toggle).label, '打开弹幕');
    final Icon disabledIcon = tester.widget<Icon>(
      find.descendant(
        of: toggle,
        matching: find.byIcon(Icons.chat_bubble_outline),
      ),
    );
    expect(disabledIcon.color, Colors.white);

    await tester.tap(toggle);
    await tester.pump();

    expect(tester.getSemantics(toggle).label, '关闭弹幕');
    final Icon enabledIcon = tester.widget<Icon>(
      find.descendant(of: toggle, matching: find.byIcon(Icons.chat_bubble)),
    );
    expect(enabledIcon.color, const Color(0xFF7EC3FF));
    semantics.dispose();
  });

  testWidgets('紧凑隐藏标题且非紧凑只显示批准标题', (WidgetTester tester) async {
    // Catches legacy top actions returning or title typography ignoring the mode.
    await pumpPlayer(tester, viewSize: const Size(393, 852));
    expect(find.byKey(const ValueKey<String>('player-title')), findsNothing);

    await pumpPlayer(tester, viewSize: const Size(852, 393));
    expect(find.byKey(const ValueKey<String>('player-title')), findsOneWidget);
    final Text expandedTitle = tester.widget<Text>(
      find.byKey(const ValueKey<String>('player-title')),
    );
    final Text expandedSubtitle = tester.widget<Text>(
      find.byKey(const ValueKey<String>('player-subtitle')),
    );
    expect(expandedTitle.data, '测试影片');
    expect(expandedTitle.style?.fontSize, 18);
    expect(expandedTitle.style?.letterSpacing, -0.36);
    expect(expandedSubtitle.style?.fontSize, 11);
    for (final String key in <String>[
      'player-back',
      'night-mode',
      'favorite',
      'settings-menu',
      'cast',
      'info',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsNothing);
    }

    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    expect(find.byKey(const ValueKey<String>('player-title')), findsOneWidget);
    final Text wideTitle = tester.widget<Text>(
      find.byKey(const ValueKey<String>('player-title')),
    );
    final Text wideSubtitle = tester.widget<Text>(
      find.byKey(const ValueKey<String>('player-subtitle')),
    );
    expect(wideTitle.style?.fontSize, 17);
    expect(wideSubtitle.style?.fontSize, 10);
  });

  testWidgets('没有选集数据时宽布局不显示空选集入口', (WidgetTester tester) async {
    // Catches responsive visibility bypassing the hasEpisodes requirement.
    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    expect(
      find.byKey(const ValueKey<String>('primary-controls-row')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('episode-picker')), findsNothing);
  });

  testWidgets('未提供上一集和下一集回调时按钮不可点击', (WidgetTester tester) async {
    // Catches disabled transport controls remaining tappable or semantically enabled.
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpPlayer(tester);

    expect(
      tester
          .getSemantics(find.byKey(const ValueKey<String>('previous-episode')))
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey<String>('next-episode')))
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
    semantics.dispose();
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

  testWidgets('桌面鼠标进入隐藏播放器时恢复控件', (WidgetTester tester) async {
    // Catches desktop hover events bypassing the existing show-controls path.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
      autoHideControlsDelay: const Duration(milliseconds: 100),
    );
    await controller.play();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsOverlay(tester).opacity, 0);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey<String>('player-frame')),
      ),
    );
    await tester.pump();

    expect(_controlsOverlay(tester).opacity, 1);
    await mouse.removePointer();
  });

  testWidgets('桌面键盘活动恢复隐藏控件', (WidgetTester tester) async {
    // Catches keyboard events lacking a focused reveal path through the player.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
      autoHideControlsDelay: const Duration(milliseconds: 100),
    );
    await controller.play();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsOverlay(tester).opacity, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();

    expect(_controlsOverlay(tester).opacity, 1);
  });

  testWidgets('播放状态刷新不会阻止控件自动隐藏', (WidgetTester tester) async {
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'refreshing',
      displayName: '刷新测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: descriptor,
            create: () => _RefreshingSnapshotVideoKernelAdapter(descriptor),
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.android,
      stateRefreshInterval: const Duration(milliseconds: 50),
    );
    await controller.open(VideoSource.network(sampleMp4Url));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            autoHideControlsDelay: const Duration(milliseconds: 200),
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await controller.play();
    await tester.pump();
    expect(_controlsOverlay(tester).opacity, 1);

    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsOverlay(tester).opacity, 0);

    controller.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
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

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
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

  testWidgets('全屏切换复用同一个播放器 Surface，不创建第二套播放器 View', (
    WidgetTester tester,
  ) async {
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.unknown,
    );
    final Element embeddedSurface = tester.element(
      find.byKey(const ValueKey<String>('fake-video-title')),
    );

    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('fake-video-title')),
      findsOneWidget,
    );
    expect(
      tester.element(find.byKey(const ValueKey<String>('fake-video-title'))),
      same(embeddedSurface),
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget.runtimeType.toString() == '_FullscreenVideoPage',
      ),
      findsNothing,
    );
    expect(controller.value.fullscreen, isTrue);

    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('fake-video-title')),
      findsOneWidget,
    );
    expect(
      tester.element(find.byKey(const ValueKey<String>('fake-video-title'))),
      same(embeddedSurface),
    );
    expect(controller.value.fullscreen, isFalse);
  });

  testWidgets('平台全屏失败时回滚播放器全屏状态和 Overlay', (WidgetTester tester) async {
    const MethodChannel channel = MethodChannel('leelando_video/fullscreen');
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'enter') {
        throw PlatformException(
          code: 'fullscreen_transition_failed',
          message: '模拟系统全屏失败',
        );
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.macos,
    );

    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();

    expect(controller.value.fullscreen, isFalse);
    expect(
      find.byKey(const ValueKey<String>('fake-video-title')),
      findsOneWidget,
    );
  });

  testWidgets('macOS 原生退出全屏后自动收回播放器 Overlay', (WidgetTester tester) async {
    const MethodChannel channel = MethodChannel('leelando_video/fullscreen');
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.macos,
    );

    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();
    expect(controller.value.fullscreen, isTrue);

    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('fullscreenChanged', <String, Object?>{
          'fullscreen': false,
        }),
      ),
      null,
    );
    await tester.pumpAndSettle();

    expect(controller.value.fullscreen, isFalse);
    expect(
      find.byKey(const ValueKey<String>('fake-video-title')),
      findsOneWidget,
    );
  });

  testWidgets('macOS 原生全屏状态只同步给已发起全屏的控制器', (WidgetTester tester) async {
    UnifiedVideoController createController() => UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[createFakeVideoKernel()],
      ),
      platform: UnifiedVideoPlatform.macos,
      stateRefreshInterval: null,
    );

    final UnifiedVideoController activeController = createController();
    final UnifiedVideoController inactiveController = createController();
    addTearDown(activeController.dispose);
    addTearDown(inactiveController.dispose);
    await activeController.enterFullscreen(syncPlatform: false);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'leelando_video/fullscreen',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('fullscreenChanged', <String, Object?>{
              'fullscreen': true,
            }),
          ),
          null,
        );

    expect(activeController.value.fullscreen, isTrue);
    expect(inactiveController.value.fullscreen, isFalse);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'leelando_video/fullscreen',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('fullscreenChanged', <String, Object?>{
              'fullscreen': false,
            }),
          ),
          null,
        );
  });

  testWidgets('macOS 系统快捷键进入全屏时当前播放器自动铺满', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.macos,
    );

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'leelando_video/fullscreen',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('fullscreenChanged', <String, Object?>{
              'fullscreen': false,
            }),
          ),
          null,
        );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'leelando_video/fullscreen',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('fullscreenChanged', <String, Object?>{
              'fullscreen': true,
            }),
          ),
          null,
        );
    await tester.pumpAndSettle();

    expect(controller.value.fullscreen, isTrue);
    expect(
      find.byKey(const ValueKey<String>('fake-video-title')),
      findsOneWidget,
    );
  });

  testWidgets('已全屏播放器不会被动态挂载的另一个播放器抢走所有权', (WidgetTester tester) async {
    UnifiedVideoController createController() => UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[createFakeVideoKernel()],
      ),
      platform: UnifiedVideoPlatform.macos,
      stateRefreshInterval: null,
    );

    final UnifiedVideoController activeController = createController();
    final UnifiedVideoController backgroundController = createController();
    addTearDown(activeController.dispose);
    addTearDown(backgroundController.dispose);
    await activeController.open(VideoSource.network(sampleMp4Url));
    await backgroundController.open(VideoSource.network(sampleMp4Url));
    late StateSetter updateHost;
    bool showBackgroundPlayer = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return Column(
                children: <Widget>[
                  SizedBox(
                    width: 320,
                    child: UnifiedVideoPlayer(controller: activeController),
                  ),
                  if (showBackgroundPlayer)
                    SizedBox(
                      width: 320,
                      child: UnifiedVideoPlayer(
                        controller: backgroundController,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await activeController.enterFullscreen(syncPlatform: false);
    await tester.pumpAndSettle();
    updateHost(() => showBackgroundPlayer = true);
    await tester.pumpAndSettle();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'leelando_video/fullscreen',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('fullscreenChanged', <String, Object?>{
              'fullscreen': true,
            }),
          ),
          null,
        );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'leelando_video/fullscreen',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('fullscreenChanged', <String, Object?>{
              'fullscreen': false,
            }),
          ),
          null,
        );
    await tester.pumpAndSettle();

    expect(activeController.value.fullscreen, isFalse);
    expect(backgroundController.value.fullscreen, isFalse);
  });

  testWidgets('打开视频和缓冲视频时显示明确的加载层', (WidgetTester tester) async {
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'delayed-open',
      displayName: '延迟打开测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _DelayedOpenVideoKernelAdapter adapter =
        _DelayedOpenVideoKernelAdapter(descriptor);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
        ],
      ),
      platform: UnifiedVideoPlatform.android,
      stateRefreshInterval: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnifiedVideoPlayer(controller: controller)),
      ),
    );
    addTearDown(controller.dispose);

    final Future<void> opening = controller.open(
      VideoSource.network(sampleMp4Url),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('video-loading-indicator')),
      findsOneWidget,
    );
    expect(find.text('正在加载视频'), findsOneWidget);

    adapter.completeOpen();
    await opening;
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('video-loading-indicator')),
      findsNothing,
    );

    controller.value = controller.value.copyWith(
      lifecycle: UnifiedVideoLifecycle.buffering,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('video-loading-indicator')),
      findsOneWidget,
    );
    expect(find.text('正在缓冲'), findsOneWidget);
  });

  testWidgets('切换内核时保持播放器 View 并显示目标内核 Loading', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpSwitchablePlayer(
      tester,
    );
    final Finder playerHost = find.byKey(
      const ValueKey<String>('video-surface-host'),
    );
    expect(playerHost, findsOneWidget);

    final Future<void> switching = controller.switchKernel('delayed');
    await tester.pump();

    expect(playerHost, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('video-loading-indicator')),
      findsOneWidget,
    );
    expect(find.text('正在切换到 延迟测试内核'), findsOneWidget);

    completeDelayedOpen();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await switching;
    await tester.pumpAndSettle();
    expect(playerHost, findsOneWidget);
  });

  testWidgets('桌面菜单和移动设置仅显示兼容当前播放源的内核', (WidgetTester tester) async {
    const VideoKernelDescriptor compatibleDescriptor = VideoKernelDescriptor(
      id: 'compatible',
      displayName: '兼容测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    const VideoKernelDescriptor unsupportedPlatformDescriptor =
        VideoKernelDescriptor(
          id: 'unsupported-platform',
          displayName: '不兼容平台内核',
          supportedPlatforms: <UnifiedVideoPlatform>{
            UnifiedVideoPlatform.macos,
          },
          supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
        );
    const VideoKernelDescriptor unsupportedSourceDescriptor =
        VideoKernelDescriptor(
          id: 'unsupported-source',
          displayName: '不兼容播放源内核',
          supportedPlatforms: <UnifiedVideoPlatform>{
            UnifiedVideoPlatform.android,
          },
          supportedSourceTypes: <VideoSourceType>{VideoSourceType.asset},
        );
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          createFakeVideoKernel(),
          RegisteredVideoKernel(
            descriptor: compatibleDescriptor,
            create: () =>
                FakeVideoKernelAdapter(descriptor: compatibleDescriptor),
          ),
          RegisteredVideoKernel(
            descriptor: unsupportedPlatformDescriptor,
            create: () => FakeVideoKernelAdapter(
              descriptor: unsupportedPlatformDescriptor,
            ),
          ),
          RegisteredVideoKernel(
            descriptor: unsupportedSourceDescriptor,
            create: () =>
                FakeVideoKernelAdapter(descriptor: unsupportedSourceDescriptor),
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.android,
      stateRefreshInterval: null,
    );
    await controller.open(
      VideoSource.network(sampleMp4Url),
      preference: KernelPreference.exact('fake'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnifiedVideoPlayer(controller: controller)),
      ),
    );
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('kernel-option-compatible')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kernel-option-unsupported-platform')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('kernel-option-unsupported-source')),
      findsNothing,
    );

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('kernel-option-compatible')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kernel-option-unsupported-platform')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('kernel-option-unsupported-source')),
      findsNothing,
    );
  });

  testWidgets('设置面板按钮生效后自动关闭', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpPlayer(tester);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    expect(find.text('播放设置'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('speed-option-1.25')));
    await tester.pumpAndSettle();
    expect(controller.value.speed, 1.25);
    expect(find.text('播放设置'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
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
        kernels: <RegisteredVideoKernel>[_createPlatformTestKernel()],
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

  testWidgets('切换到失败内核后保留原播放画面和生命周期并提示错误', (WidgetTester tester) async {
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
    await controller.play();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnifiedVideoPlayer(controller: controller)),
      ),
    );
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('kernel-option-erika')));
    await tester.pumpAndSettle();

    expect(controller.value.lifecycle, UnifiedVideoLifecycle.playing);
    expect(controller.value.activeKernelId, 'fake');
    expect(
      find.byKey(const ValueKey<String>('fake-video-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('video-error-message')),
      findsNothing,
    );
    expect(find.text('切换目标播放器内核失败，已恢复原内核。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

RegisteredVideoKernel _createPlatformTestKernel() {
  const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
    id: 'video-player',
    displayName: '平台测试内核',
    supportedPlatforms: <UnifiedVideoPlatform>{
      UnifiedVideoPlatform.android,
      UnifiedVideoPlatform.ios,
      UnifiedVideoPlatform.macos,
    },
    supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
  );
  return RegisteredVideoKernel(
    descriptor: descriptor,
    create: () => FakeVideoKernelAdapter(descriptor: descriptor),
  );
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

class _RefreshingSnapshotVideoKernelAdapter extends FakeVideoKernelAdapter {
  _RefreshingSnapshotVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    if (!state.isPlaying) {
      return state;
    }
    return state.copyWith(
      position: state.position + const Duration(milliseconds: 50),
    );
  }
}

class _DelayedOpenVideoKernelAdapter extends FakeVideoKernelAdapter {
  _DelayedOpenVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  final Completer<void> _openCompleter = Completer<void>();

  void completeOpen() => _openCompleter.complete();

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    await _openCompleter.future;
    return super.open(source, state);
  }
}

class _CountingOpenVideoKernelAdapter extends FakeVideoKernelAdapter {
  _CountingOpenVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  int openCount = 0;

  @override
  Future<UnifiedVideoState> open(VideoSource source, UnifiedVideoState state) {
    openCount += 1;
    return super.open(source, state);
  }
}
