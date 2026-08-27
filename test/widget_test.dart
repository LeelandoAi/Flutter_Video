import 'dart:async';

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
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

  List<VideoEpisode> _testEpisodes() => <VideoEpisode>[
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

  UnifiedVideoController _createFakeController() {
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
      episodes: _testEpisodes(),
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
      episodes: _testEpisodes(),
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
            episodes: _testEpisodes(),
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
    final List<VideoEpisode> episodes = _testEpisodes();
    final UnifiedVideoController firstController = _createFakeController();
    final UnifiedVideoController replacementController =
        _createFakeController();
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
    final UnifiedVideoController replacementController =
        _createFakeController();
    addTearDown(firstController.dispose);
    addTearDown(replacementController.dispose);
    final List<VideoEpisode> episodes = _testEpisodes();
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
    final UnifiedVideoController replacementController =
        _createFakeController();
    addTearDown(firstController.dispose);
    addTearDown(replacementController.dispose);
    final List<VideoEpisode> episodes = _testEpisodes();
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
    final List<VideoEpisode> episodes = _testEpisodes();
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
    final List<VideoEpisode> episodes = _testEpisodes();
    final UnifiedVideoController controller = _createFakeController();
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
    final List<VideoEpisode> episodes = _testEpisodes();
    final UnifiedVideoController controller = _createFakeController();
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
    final List<VideoEpisode> episodes = _testEpisodes();
    final UnifiedVideoController controller = _createFakeController();
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

    await tester.tap(find.byKey(const ValueKey<String>('kernel-menu')));
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
    await tester.tap(find.byKey(const ValueKey<String>('settings-menu')));
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

    await tester.tap(find.byKey(const ValueKey<String>('kernel-menu')));
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
