import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/foundation.dart'
    show FlutterErrorDetails, FlutterExceptionHandler;
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
    double aspectRatio = 16 / 9,
    UnifiedVideoFullscreenOrientation fullscreenOrientation =
        UnifiedVideoFullscreenOrientation.landscape,
    VideoDimensions? videoDimensions,
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
    if (videoDimensions != null) {
      controller.value = controller.value.copyWith(
        videoDimensions: videoDimensions,
      );
    }
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
            aspectRatio: aspectRatio,
            fullscreenOrientation: fullscreenOrientation,
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

  testWidgets('选集面板显示外部名称并点击后直接播放', (WidgetTester tester) async {
    // Catches the picker delegating to legacy callbacks instead of opening the episode.
    final List<VideoEpisode> episodes = testEpisodes();
    final List<String> changed = <String>[];
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      episodes: episodes,
      initialEpisodeId: 'e1',
      onEpisodeChanged: (VideoEpisode episode) => changed.add(episode.id),
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    expect(find.text('第 2 集'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
    await tester.pumpAndSettle();

    expect(controller.value.source?.uri, episodes[1].source.uri);
    expect(changed, <String>['e2']);
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsNothing);
  });

  testWidgets('选集打开失败不改变高亮且不通知外部', (WidgetTester tester) async {
    // Catches the controller's opening source being committed as selection before success.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'selective-fail',
      displayName: '选集失败测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _SelectiveFailVideoKernelAdapter adapter =
        _SelectiveFailVideoKernelAdapter(descriptor);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    final List<VideoEpisode> episodes = testEpisodes();
    final List<String> changed = <String>[];
    await controller.open(episodes.first.source);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: episodes,
            initialEpisodeId: 'e1',
            onEpisodeChanged: (VideoEpisode episode) => changed.add(episode.id),
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
    await tester.pumpAndSettle();

    expect(changed, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('episode-option-e1-selected')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsOneWidget);
    expect(controller.value.lifecycle, UnifiedVideoLifecycle.failed);
  });

  testWidgets('外部直接换源后选集高亮同步到匹配条目', (WidgetTester tester) async {
    // Catches external controller opens leaving the picker on stale selection.
    final List<VideoEpisode> episodes = testEpisodes();
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      episodes: episodes,
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await controller.open(episodes[1].source);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('episode-option-e2-selected')),
      findsOneWidget,
    );
  });

  testWidgets('选集列表替换 ID 后按当前播放源重新匹配', (WidgetTester tester) async {
    // Catches list replacement clearing selection instead of rematching source identity.
    final List<VideoEpisode> episodes = testEpisodes();
    final UnifiedVideoController controller = createFakeController();
    addTearDown(controller.dispose);
    await controller.open(episodes[1].source);
    List<VideoEpisode> visibleEpisodes = episodes;
    late StateSetter updateHost;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      visibleEpisodes = <VideoEpisode>[
        episodes.first,
        VideoEpisode(
          id: 'e2-renamed',
          title: '第 2 集（新 ID）',
          source: episodes[1].source,
        ),
        episodes.last,
      ];
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('episode-option-e2-renamed-selected')),
      findsOneWidget,
    );
  });

  testWidgets('选集列表替换会使旧列表中的在途打开失效', (WidgetTester tester) async {
    // Catches an old-list episode committing after the host replaces episodes.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'delayed-episode-list',
      displayName: '选集列表延迟内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _SelectiveDelayedEpisodeAdapter adapter =
        _SelectiveDelayedEpisodeAdapter(descriptor);
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
    final List<VideoEpisode> original = testEpisodes();
    List<VideoEpisode> visibleEpisodes = original;
    final List<String> changed = <String>[];
    late StateSetter updateHost;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: controller,
                episodes: visibleEpisodes,
                initialEpisodeId: 'e1',
                onEpisodeChanged: (VideoEpisode episode) {
                  changed.add(episode.id);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
    await tester.pump();
    expect(adapter.delayedOpenStarted, isTrue);

    updateHost(() {
      visibleEpisodes = <VideoEpisode>[
        VideoEpisode(
          id: 'e1',
          title: '第 1 集（新源）',
          source: VideoSource.network('https://example.com/e1-new.mp4'),
        ),
        VideoEpisode(
          id: 'e2',
          title: '第 2 集（新源）',
          source: VideoSource.network('https://example.com/e2-new.mp4'),
        ),
        original.last,
      ];
    });
    await tester.pump();
    adapter.completeDelayedOpen();
    await tester.pumpAndSettle();

    expect(changed, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('episode-option-e1-selected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('episode-option-e2-selected')),
      findsNothing,
    );
  });

  testWidgets('重复选择当前集仅关闭面板且不重新打开或回调', (WidgetTester tester) async {
    // Catches current-row taps performing a redundant controller open.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'counting-episode-picker',
      displayName: '选集计数测试内核',
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
    final List<VideoEpisode> episodes = testEpisodes();
    final List<String> changed = <String>[];
    await controller.open(episodes.first.source);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: episodes,
            initialEpisodeId: 'e1',
            onEpisodeChanged: (VideoEpisode episode) => changed.add(episode.id),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e1')));
    await tester.pumpAndSettle();

    expect(adapter.openCount, 1);
    expect(changed, isEmpty);
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsNothing);
  });

  testWidgets('选集成功回调不会造成第二次打开', (WidgetTester tester) async {
    // Catches host callbacks reopening a source already opened by the player.
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
    final List<VideoEpisode> episodes = testEpisodes();
    await controller.open(episodes.first.source);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: episodes,
            initialEpisodeId: 'e1',
            onEpisodeChanged: (_) {},
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);

    expect(adapter.openCount, 1);
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
    await tester.pumpAndSettle();

    expect(adapter.openCount, 2);

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
    await tester.pumpAndSettle();

    expect(adapter.openCount, 2);
  });

  testWidgets('Expanded 与 Wide 使用批准的选集面板位置和尺寸', (WidgetTester tester) async {
    // Catches mode placement drifting from edge-sheet and anchored-popover rules.
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      viewSize: const Size(852, 393),
    );
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    final Rect expandedFrame = tester.getRect(
      find.byKey(const ValueKey<String>('player-frame')),
    );
    final Rect expandedPanel = tester.getRect(
      find.byKey(const ValueKey<String>('episode-panel')),
    );
    expect(expandedPanel.right, expandedFrame.right);
    expect(expandedPanel.top, expandedFrame.top);
    expect(expandedPanel.bottom, expandedFrame.bottom);
    expect(expandedPanel.width, math.min(360, expandedFrame.width * 0.58));

    await tester.tap(
      find.byKey(const ValueKey<String>('context-overlay-close')),
    );
    await tester.pumpAndSettle();

    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    final Rect wideFrame = tester.getRect(
      find.byKey(const ValueKey<String>('player-frame')),
    );
    final Rect widePanel = tester.getRect(
      find.byKey(const ValueKey<String>('episode-panel')),
    );
    expect(wideFrame.right - widePanel.right, 14);
    expect(wideFrame.bottom - widePanel.bottom, 52);
    expect(widePanel.width, 320);
    expect(widePanel.height, lessThanOrEqualTo(420));
  });

  testWidgets('选集使用单一玻璃表面发丝分隔和蓝色勾选', (WidgetTester tester) async {
    // Catches fragmented per-row cards or color-only current selection returning.
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();

    final Finder panel = find.byKey(const ValueKey<String>('episode-panel'));
    final Finder selected = find.byKey(
      const ValueKey<String>('episode-option-e1-selected'),
    );
    expect(
      find.descendant(of: panel, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(Divider)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: find.byType(Card)),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(Chip)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('episode-option-e1')),
        matching: selected,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: selected, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    final Text selectedTitle = tester.widget<Text>(
      find.descendant(of: selected, matching: find.text('第 1 集')),
    );
    expect(selectedTitle.style?.color, const Color(0xFF7EC3FF));
    expect(
      tester.getSemantics(selected).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('episode-option-e2')))
          .height,
      greaterThanOrEqualTo(44),
    );
    for (final String id in <String>['e1', 'e2', 'e3']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey<String>('episode-option-$id')),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    }
    semantics.dispose();
  });

  testWidgets('降低动态效果时面板只淡入且高对比时使用不透明材质', (WidgetTester tester) async {
    // Catches accessibility preferences retaining travel or translucent blur.
    final UnifiedVideoController controller = createFakeController();
    addTearDown(controller.dispose);
    await controller.open(testEpisodes().first.source);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: true, highContrast: true),
            child: child!,
          );
        },
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: testEpisodes(),
            initialEpisodeId: 'e1',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pump(const Duration(milliseconds: 100));

    final Finder panel = find.byKey(const ValueKey<String>('episode-panel'));
    final Rect frameRect = tester.getRect(
      find.byKey(const ValueKey<String>('player-frame')),
    );
    expect(tester.getRect(panel).right, frameRect.right);
    expect(
      find.descendant(of: panel, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    final DecoratedBox surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('episode-panel-surface')),
    );
    expect(
      (surface.decoration as BoxDecoration).color,
      const Color(0xFF1E1E22),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsOneWidget);
  });

  testWidgets('选集进入动画中可通过明确出口关闭并切换更多浮层', (WidgetTester tester) async {
    // Catches transition state locking the explicit close escape.
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.byKey(const ValueKey<String>('context-overlay-close')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.byKey(const ValueKey<String>('context-overlay-close')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsNothing);
    expect(find.text('播放设置'), findsOneWidget);
  });

  testWidgets('选集关闭后切换倍速或更多时任一帧只显示一个浮层', (WidgetTester tester) async {
    // Catches a replacement surface appearing before the modal reverse completes.
    for (final String actionKey in <String>['speed-menu', 'more-menu']) {
      await pumpPlayer(
        tester,
        episodes: testEpisodes(),
        initialEpisodeId: 'e1',
        platform: UnifiedVideoPlatform.windows,
        viewSize: const Size(1280, 720),
      );
      await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey<String>('context-overlay-close')),
      );
      await tester.pump(const Duration(milliseconds: 20));

      final bool episodeVisible = find
          .byKey(const ValueKey<String>('episode-panel'), skipOffstage: false)
          .evaluate()
          .isNotEmpty;
      final String replacementKey = actionKey == 'speed-menu'
          ? 'speed-panel'
          : 'settings-panel';
      final bool replacementVisible = find
          .byKey(ValueKey<String>(replacementKey), skipOffstage: false)
          .evaluate()
          .isNotEmpty;
      expect(
        episodeVisible,
        isTrue,
        reason: 'episode=$episodeVisible replacement=$replacementVisible',
      );
      expect(
        replacementVisible,
        isFalse,
        reason: 'episode=$episodeVisible replacement=$replacementVisible',
      );
      expect(episodeVisible && replacementVisible, isFalse);
      expect(episodeVisible || replacementVisible, isTrue);

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('episode-panel')), findsNothing);
      await tester.tap(find.byKey(ValueKey<String>(actionKey)));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey<String>(replacementKey)), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('context-overlay-close')),
      );
      await tester.pumpAndSettle();
    }
  });

  testWidgets('倍速更多和选集通过明确出口顺序切换且保持单实例', (WidgetTester tester) async {
    // Catches close-and-retarget sequencing leaving multiple surfaces mounted.
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    int visibleOverlayCount() {
      return <String>['episode-panel', 'speed-panel', 'settings-panel']
          .map(
            (String key) => find
                .byKey(ValueKey<String>(key), skipOffstage: false)
                .evaluate()
                .length,
          )
          .fold(0, (int total, int count) => total + count);
    }

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(visibleOverlayCount(), 1);
    await tester.tap(
      find.byKey(const ValueKey<String>('context-overlay-close')),
    );
    await tester.pumpAndSettle();
    expect(visibleOverlayCount(), 0);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(visibleOverlayCount(), 1);
    await tester.tap(
      find.byKey(const ValueKey<String>('context-overlay-close')),
    );
    await tester.pumpAndSettle();
    expect(visibleOverlayCount(), 0);

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(visibleOverlayCount(), 1);
    await tester.pumpAndSettle();
    expect(visibleOverlayCount(), 1);
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsOneWidget);
  });

  testWidgets('失败选集源在后续通知中保持隔离且外部重开成功后同步', (WidgetTester tester) async {
    // Catches retained failed sources being mistaken for successful external opens.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'fail-once-episode',
      displayName: '选集单次失败内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _FailOnceEpisodeTracker tracker = _FailOnceEpisodeTracker();
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: descriptor,
            create: () => _FailOnceEpisodeAdapter(descriptor, tracker),
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    final List<VideoEpisode> episodes = testEpisodes();
    await controller.open(episodes.first.source);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: episodes,
            initialEpisodeId: 'e1',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
    await tester.pumpAndSettle();
    expect(controller.value.lifecycle, UnifiedVideoLifecycle.failed);

    await controller.enterFullscreen(syncPlatform: false);
    controller.value = controller.value.copyWith(
      position: const Duration(seconds: 7),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('episode-option-e1-selected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('episode-option-e2-selected')),
      findsNothing,
    );

    await controller.open(episodes[1].source);
    await tester.pumpAndSettle();
    expect(controller.value.lifecycle, UnifiedVideoLifecycle.ready);
    expect(
      find.byKey(const ValueKey<String>('episode-option-e2-selected')),
      findsOneWidget,
    );
  });

  testWidgets('选集进入动画中仍可退出全屏', (WidgetTester tester) async {
    // Catches a full-height episode sheet intercepting the fullscreen exit control.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.unknown,
      viewSize: const Size(852, 393),
    );
    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();
    expect(controller.value.fullscreen, isTrue);

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey<String>('player-frame'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('fullscreen')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('episode-panel')).hitTestable(),
      findsNothing,
    );
    await tester.pumpAndSettle();

    expect(controller.value.fullscreen, isFalse);
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsNothing);
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

  testWidgets('倍速浮层包含全部预设并以蓝色勾选当前值', (WidgetTester tester) async {
    // Catches a partial preset list, color-only selection, or yellow returning.
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    final Finder panel = find.byKey(const ValueKey<String>('speed-panel'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    for (final double speed in unifiedVideoSpeedPresets) {
      final Finder option = find.byKey(ValueKey<String>('speed-option-$speed'));
      expect(option, findsOneWidget);
      expect(tester.getSize(option).height, greaterThanOrEqualTo(44));
    }
    final Finder selected = find.byKey(
      const ValueKey<String>('speed-option-1.0'),
    );
    final Text selectedSpeed = tester.widget<Text>(
      find.descendant(of: selected, matching: find.byType(Text)),
    );

    expect(selectedSpeed.style?.color, const Color(0xFF7EC3FF));
    expect(
      find.descendant(of: selected, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(selected).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(selectedSpeed.style?.color, isNot(const Color(0xFFFFD700)));
    semantics.dispose();
  });

  testWidgets('Compact 嵌入倍速浮层可滚动并实际选择首尾预设', (WidgetTester tester) async {
    // Catches a full-height popover clipping both extremes outside a short embed.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      viewSize: const Size(393, 221),
      aspectRatio: 393 / 221,
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    final Finder panel = find.byKey(const ValueKey<String>('speed-panel'));
    final Finder scrollable = find.descendant(
      of: panel,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    expect(
      tester.getRect(panel).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey<String>('player-frame'))).top,
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-option-0.5')));
    await tester.pumpAndSettle();
    expect(controller.value.speed, 0.5);

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    final ScrollPosition position = tester
        .state<ScrollableState>(scrollable)
        .position;
    expect(position.pixels, 0);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('speed-option-3.0')),
      80,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey<String>('speed-option-3.0')));
    await tester.pumpAndSettle();

    expect(controller.value.speed, 3.0);
    expect(find.byKey(const ValueKey<String>('speed-panel')), findsNothing);
  });

  testWidgets('Expanded 倍速浮层按局部高度滚动并实际选择首尾预设', (WidgetTester tester) async {
    // Catches viewport-based sizing or a non-scrollable 8-row Expanded popover.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      viewSize: const Size(852, 393),
      aspectRatio: 852 / 393,
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    final Finder panel = find.byKey(const ValueKey<String>('speed-panel'));
    final Finder scrollable = find.descendant(
      of: panel,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    expect(
      tester.getRect(panel).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey<String>('player-frame'))).top,
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-option-0.5')));
    await tester.pumpAndSettle();
    expect(controller.value.speed, 0.5);

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    final ScrollPosition position = tester
        .state<ScrollableState>(scrollable)
        .position;
    expect(position.pixels, 0);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('speed-option-3.0')),
      80,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey<String>('speed-option-3.0')));
    await tester.pumpAndSettle();

    expect(controller.value.speed, 3.0);
    expect(find.byKey(const ValueKey<String>('speed-panel')), findsNothing);
  });

  testWidgets('Wide 倍速末行中心真实指针不被进度条遮挡', (WidgetTester tester) async {
    // Catches the later full-width Slider winning the 3.0x row hit test.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    final Rect lastRow = tester.getRect(
      find.byKey(const ValueKey<String>('speed-option-3.0')),
    );
    final Rect progress = tester.getRect(
      find.byKey(const ValueKey<String>('video-progress')),
    );
    await tester.tapAt(lastRow.center);
    await tester.pumpAndSettle();

    expect(controller.value.speed, 3.0);
    expect(lastRow.bottom, lessThanOrEqualTo(progress.top));
    expect(find.byKey(const ValueKey<String>('speed-panel')), findsNothing);
  });

  testWidgets('更多设置使用连续分组行而不是 Chip 网格', (WidgetTester tester) async {
    // Catches legacy card/chip grids or the approved group order drifting.
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();

    final Finder panel = find.byKey(const ValueKey<String>('settings-panel'));
    final Finder picture = find.byKey(
      const ValueKey<String>('settings-group-picture'),
    );
    final Finder playback = find.byKey(
      const ValueKey<String>('settings-group-playback'),
    );
    final Finder kernel = find.byKey(
      const ValueKey<String>('settings-group-kernel'),
    );
    final Finder diagnostics = find.byKey(
      const ValueKey<String>('settings-group-diagnostics'),
    );
    expect(panel, findsOneWidget);
    expect(picture, findsOneWidget);
    expect(playback, findsOneWidget);
    expect(kernel, findsOneWidget);
    expect(diagnostics, findsOneWidget);
    expect(
      tester.getTopLeft(picture).dy,
      lessThan(tester.getTopLeft(playback).dy),
    );
    expect(
      tester.getTopLeft(playback).dy,
      lessThan(tester.getTopLeft(kernel).dy),
    );
    expect(
      tester.getTopLeft(kernel).dy,
      lessThan(tester.getTopLeft(diagnostics).dy),
    );
    expect(
      find.byKey(const ValueKey<String>('settings-chip-grid')),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(Chip)),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(Card)),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(Divider)),
      findsWidgets,
    );
    expect(
      find.byKey(const ValueKey<String>('fit-option-cover')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kernel-option-fake')),
      findsOneWidget,
    );
    for (final String selectedKey in <String>[
      'fit-option-contain',
      'kernel-option-fake',
    ]) {
      final Finder selected = find.byKey(ValueKey<String>(selectedKey));
      expect(
        find.descendant(
          of: selected,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(selected).flagsCollection.isSelected,
        Tristate.isTrue,
      );
    }
    semantics.dispose();
  });

  testWidgets('倍速成功后关闭而更多设置选项保持面板打开', (WidgetTester tester) async {
    // Catches speed closing before apply and More reverting to one-shot actions.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('speed-option-1.25')));
    await tester.pumpAndSettle();
    expect(controller.value.speed, 1.25);
    expect(find.byKey(const ValueKey<String>('speed-panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('settings-panel')),
        matching: find.byKey(const ValueKey<String>('mirror-toggle')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('fit-option-cover')));
    await tester.pumpAndSettle();
    expect(controller.value.fit, UnifiedVideoFit.cover);
    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('settings-panel')), findsNothing);
  });

  testWidgets('倍速应用失败时保留浮层与原选中值', (WidgetTester tester) async {
    // Catches a rejected speed being presented as applied or closing the popover.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'speed-fails',
      displayName: '倍速失败内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: descriptor,
            create: () => _FailingSpeedVideoKernelAdapter(descriptor),
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    await controller.open(VideoSource.network(sampleMp4Url));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            autoHideControlsDelay: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('speed-option-1.25')));
    await tester.pumpAndSettle();

    expect(controller.value.speed, 1.0);
    expect(find.byKey(const ValueKey<String>('speed-panel')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('speed-option-1.0')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('较早倍速成功不能在最新倍速失败后关闭浮层', (WidgetTester tester) async {
    // Catches overlay-only generations treating concurrent speed requests as one.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'delayed-speed-sequence',
      displayName: '延迟倍速序列内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _DelayedThenFailingSpeedVideoKernelAdapter adapter =
        _DelayedThenFailingSpeedVideoKernelAdapter(descriptor);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    await controller.open(VideoSource.network(sampleMp4Url));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnifiedVideoPlayer(controller: controller)),
      ),
    );
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('speed-option-1.25')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('speed-option-1.5')));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('speed-panel')), findsOneWidget);

    adapter.completeFirstRequest();
    await tester.pumpAndSettle();

    expect(controller.value.speed, 1.25);
    expect(controller.value.lifecycle, UnifiedVideoLifecycle.failed);
    expect(find.byKey(const ValueKey<String>('speed-panel')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('speed-option-1.25')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('短剧在横屏窄宽嵌入时控件分行且不溢出', (WidgetTester tester) async {
    // Catches a 9:16 player becoming about 203 px wide after leaving fullscreen.
    await pumpPlayer(
      tester,
      viewSize: const Size(780, 360),
      aspectRatio: 9 / 16,
    );

    expect(
      find.byKey(const ValueKey<String>('compact-playback-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('compact-utility-row')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('9:16 嵌入滚动业务页在手机和电视尺寸均完整收进一屏', (WidgetTester tester) async {
    // Catches an unbounded vertical parent sizing portrait video from the
    // entire wide-screen width and producing a player several screens tall.
    final List<({Size viewport, UnifiedVideoPlatform platform})> cases =
        <({Size viewport, UnifiedVideoPlatform platform})>[
          (
            viewport: const Size(393, 852),
            platform: UnifiedVideoPlatform.android,
          ),
          (
            viewport: const Size(1920, 1080),
            platform: UnifiedVideoPlatform.windows,
          ),
        ];
    final List<UnifiedVideoController> controllers = <UnifiedVideoController>[];
    addTearDown(() {
      for (final UnifiedVideoController controller in controllers) {
        controller.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final fixture in cases) {
      tester.view.physicalSize = fixture.viewport;
      tester.view.devicePixelRatio = 1;
      final UnifiedVideoController controller = UnifiedVideoController(
        registry: VideoKernelRegistry(
          kernels: <RegisteredVideoKernel>[createFakeVideoKernel()],
        ),
        platform: fixture.platform,
        stateRefreshInterval: null,
      );
      controllers.add(controller);
      await controller.open(VideoSource.network(sampleMp4Url));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnifiedVideoPlayer(
                controller: controller,
                aspectRatio: 9 / 16,
              ),
            ),
          ),
        ),
      );

      final Size frameSize = tester.getSize(
        find.byKey(const ValueKey<String>('player-frame')),
      );
      expect(
        frameSize.width,
        lessThanOrEqualTo(fixture.viewport.width),
        reason: '${fixture.platform.name} 播放器宽度不能超出屏幕',
      );
      expect(
        frameSize.height,
        lessThanOrEqualTo(fixture.viewport.height),
        reason: '${fixture.platform.name} 播放器高度不能超出屏幕',
      );
      expect(frameSize.aspectRatio, closeTo(9 / 16, 0.001));
    }
  });

  testWidgets('9:16 内核 Surface 按播放器宽高等比适配', (WidgetTester tester) async {
    // Catches the host forcing every kernel through an intermediate 16:9 box.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'portrait-surface',
      displayName: '竖屏 Surface',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _PortraitSurfaceVideoKernelAdapter adapter =
        _PortraitSurfaceVideoKernelAdapter(descriptor);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
        ],
      ),
      platform: UnifiedVideoPlatform.android,
      stateRefreshInterval: null,
    );
    await controller.open(VideoSource.network(sampleMp4Url));
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: UnifiedVideoPlayer(
              controller: controller,
              aspectRatio: 9 / 16,
            ),
          ),
        ),
      ),
    );

    final Size frameSize = tester.getSize(
      find.byKey(const ValueKey<String>('player-frame')),
    );
    final RenderBox surface = tester.renderObject(
      find.byKey(const ValueKey<String>('portrait-surface-content')),
    );
    final Offset surfaceTopLeft = surface.localToGlobal(Offset.zero);
    final Offset surfaceBottomRight = surface.localToGlobal(
      surface.size.bottomRight(Offset.zero),
    );
    final Size surfaceSize = Size(
      surfaceBottomRight.dx - surfaceTopLeft.dx,
      surfaceBottomRight.dy - surfaceTopLeft.dy,
    );
    expect(surfaceSize.width, closeTo(frameSize.width, 0.001));
    expect(surfaceSize.height, closeTo(frameSize.height, 0.001));
  });

  testWidgets('手机竖屏嵌入显示设置入口且仍隐藏选集', (WidgetTester tester) async {
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      viewSize: const Size(393, 852),
    );

    expect(find.byKey(const ValueKey<String>('episode-picker')), findsNothing);
    expect(find.byKey(const ValueKey<String>('more-menu')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
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

  testWidgets('更多设置行和状态操作保持至少 44 像素热区', (WidgetTester tester) async {
    // Catches settings rows or split rotation/state actions shrinking below touch size.
    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();

    for (final String key in <String>[
      'fit-option-cover',
      'mirror-toggle',
      'rotation-left',
      'rotation-right',
      'kernel-option-fake',
      'settings-close',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey<String>(key))).height,
        greaterThanOrEqualTo(44),
        reason: key,
      );
    }
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('fit-option-cover')))
          .height,
      greaterThanOrEqualTo(46),
    );
    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
    );
  });

  testWidgets('手机更多设置收窄居中贴底而 Wide 锚定右下', (WidgetTester tester) async {
    // Catches mobile settings expanding back to a full-width bottom sheet.
    await pumpPlayer(
      tester,
      viewSize: const Size(852, 393),
      viewPaddingBottom: 21,
    );
    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    Rect frame = tester.getRect(
      find.byKey(const ValueKey<String>('player-frame')),
    );
    Rect panel = tester.getRect(
      find.byKey(const ValueKey<String>('settings-panel')),
    );
    expect(panel.width, closeTo(math.min(352, frame.width - 32), 0.01));
    expect(panel.center.dx, closeTo(frame.center.dx, 0.01));
    expect(panel.bottom, frame.bottom);

    await tester.tap(
      find.byKey(const ValueKey<String>('context-overlay-close')),
    );
    await tester.pumpAndSettle();

    await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    frame = tester.getRect(find.byKey(const ValueKey<String>('player-frame')));
    panel = tester.getRect(
      find.byKey(const ValueKey<String>('settings-panel')),
    );
    expect(panel.width, lessThanOrEqualTo(400));
    expect(frame.right - panel.right, 14);
    expect(frame.bottom - panel.bottom, 52);
  });

  testWidgets('倍速和更多在降低效果时原地淡入并使用不透明材质', (WidgetTester tester) async {
    // Catches reduced-motion travel or translucent blur surviving accessibility mode.
    final UnifiedVideoController controller = createFakeController();
    addTearDown(controller.dispose);
    await controller.open(VideoSource.network(sampleMp4Url));
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: true, highContrast: true),
            child: child!,
          );
        },
        home: Scaffold(body: UnifiedVideoPlayer(controller: controller)),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pump(const Duration(milliseconds: 100));
    final Finder speed = find.byKey(const ValueKey<String>('speed-panel'));
    final Offset speedAtHalf = tester.getTopLeft(speed);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(speed), speedAtHalf);
    expect(
      find.descendant(of: speed, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    final DecoratedBox speedSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('speed-panel-surface')),
    );
    expect(
      (speedSurface.decoration as BoxDecoration).color,
      const Color(0xFF1E1E22),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('context-overlay-close')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pump(const Duration(milliseconds: 100));
    final Finder settings = find.byKey(
      const ValueKey<String>('settings-panel'),
    );
    final Offset settingsAtHalf = tester.getTopLeft(settings);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(settings), settingsAtHalf);
    expect(
      find.descendant(of: settings, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
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

  testWidgets('无内置选集时更多设置保留旧换源回调', (WidgetTester tester) async {
    // Catches the compatibility-only change-source action being dropped.
    int calls = 0;
    await pumpPlayer(
      tester,
      onSwitchContent: () => calls += 1,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('change-source')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
    );
  });

  testWidgets('有内置选集时更多设置不调用旧换源回调', (WidgetTester tester) async {
    // Catches legacy source switching bypassing the episode ownership model.
    int calls = 0;
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      onSwitchContent: () => calls += 1,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('change-source')), findsNothing);
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey<String>('settings-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
    await tester.pumpAndSettle();
    expect(calls, 0);
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

  testWidgets('播放时自动隐藏而暂停状态持续保留主控', (WidgetTester tester) async {
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
    expect(_controlsOverlay(tester).opacity, 1);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsOverlay(tester).opacity, 0);

    await controller.pause();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 200));
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

  testWidgets('结束状态不显示重播和下一集且持续保留主控', (WidgetTester tester) async {
    // Catches redundant ended actions returning or the controls auto-hiding.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      autoHideControlsDelay: const Duration(milliseconds: 100),
    );
    controller.value = controller.value.copyWith(
      lifecycle: UnifiedVideoLifecycle.ended,
      position: controller.value.duration,
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('ended-state-indicator')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('state-replay')), findsNothing);
    expect(find.byKey(const ValueKey<String>('state-next')), findsNothing);
    await tester.pump(const Duration(milliseconds: 320));
    expect(_controlsOverlay(tester).opacity, 1);
  });

  testWidgets('UI 可以修改缩放、倍速和全屏状态', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpPlayer(tester);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('fit-option-cover')));
    await tester.pumpAndSettle();
    expect(controller.value.fit, UnifiedVideoFit.cover);
    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('speed-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('speed-option-1.25')));
    await tester.pumpAndSettle();
    expect(controller.value.speed, 1.25);

    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();
    expect(controller.value.fullscreen, isTrue);
  });

  testWidgets('手机端外部固定 16:9 时 auto 仍按真实 9:16 尺寸进入竖屏', (
    WidgetTester tester,
  ) async {
    final List<List<Object?>> orientationCalls = <List<Object?>>[];
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientationCalls.add(List<Object?>.from(call.arguments as List));
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      viewSize: const Size(393, 852),
      aspectRatio: 16 / 9,
      fullscreenOrientation: UnifiedVideoFullscreenOrientation.auto,
      videoDimensions: const VideoDimensions(width: 1080, height: 1920),
    );

    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();

    expect(controller.value.fullscreen, isTrue);
    expect(orientationCalls.last, <Object?>['DeviceOrientation.portraitUp']);
    expect(
      find.byKey(const ValueKey<String>('fullscreen-orientation-toggle')),
      findsOneWidget,
    );
  });

  testWidgets('全屏方向按钮切换横屏时保持同一 Surface', (WidgetTester tester) async {
    final List<List<Object?>> orientationCalls = <List<Object?>>[];
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientationCalls.add(List<Object?>.from(call.arguments as List));
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      viewSize: const Size(393, 852),
      aspectRatio: 9 / 16,
      fullscreenOrientation: UnifiedVideoFullscreenOrientation.auto,
    );
    final Element embeddedSurface = tester.element(
      find.byKey(const ValueKey<String>('fake-video-title')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('fullscreen-orientation-toggle')),
    );
    await tester.pumpAndSettle();

    expect(controller.value.fullscreen, isTrue);
    expect(orientationCalls.last, <Object?>[
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    expect(
      tester.element(find.byKey(const ValueKey<String>('fake-video-title'))),
      same(embeddedSurface),
    );
  });

  testWidgets('竖屏全屏使用双行主控并保留选集入口', (WidgetTester tester) async {
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      viewSize: const Size(393, 852),
      aspectRatio: 9 / 16,
      fullscreenOrientation: UnifiedVideoFullscreenOrientation.portrait,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
    );

    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();

    expect(controller.value.fullscreen, isTrue);
    expect(
      find.byKey(const ValueKey<String>('portrait-fullscreen-playback-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('portrait-fullscreen-utility-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('episode-picker')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
    expect(_controlsOverlay(tester).opacity, 0);

    adapter.completeOpen();
    await opening;
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('video-loading-indicator')),
      findsNothing,
    );

    controller.value = controller.value.copyWith(
      lifecycle: UnifiedVideoLifecycle.buffering,
      position: const Duration(minutes: 18, seconds: 32),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('video-loading-indicator')),
      findsOneWidget,
    );
    expect(find.text('正在缓冲'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('buffering-position')),
      findsOneWidget,
    );
    expect(find.text('18:32 已保留'), findsOneWidget);
  });

  testWidgets('暂停状态显示中心反馈且贴底主控保持可用', (WidgetTester tester) async {
    // Catches paused feedback disappearing or controls continuing to auto-hide.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      autoHideControlsDelay: const Duration(milliseconds: 100),
    );
    await controller.play();
    await controller.pause();
    await tester.pump();

    final Finder paused = find.byKey(
      const ValueKey<String>('paused-state-indicator'),
    );
    expect(paused, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('play-pause')), findsOneWidget);
    expect(tester.getSize(paused).height, greaterThanOrEqualTo(44));
    await tester.pump(const Duration(milliseconds: 320));
    expect(_controlsOverlay(tester).opacity, 1);

    await tester.tap(paused);
    await tester.pumpAndSettle();
    expect(controller.value.lifecycle, UnifiedVideoLifecycle.playing);
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

  testWidgets('更多设置仅通过关闭按钮或遮罩退出', (WidgetTester tester) async {
    // Catches options dismissing the persistent More surface.
    final UnifiedVideoController controller = await pumpPlayer(tester);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('fit-option-cover')));
    await tester.pumpAndSettle();
    expect(controller.value.fit, UnifiedVideoFit.cover);
    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('settings-panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('settings-panel')), findsNothing);
  });

  testWidgets('失败状态显示错误但不显示重试按钮', (WidgetTester tester) async {
    final _FailOnceOpenTracker tracker = _FailOnceOpenTracker();
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'retry',
      displayName: '重试测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: descriptor,
            create: () => _FailOnceOpenVideoKernelAdapter(descriptor, tracker),
          ),
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
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            autoHideControlsDelay: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
    addTearDown(controller.dispose);

    expect(
      find.byKey(const ValueKey<String>('video-error-message')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('state-retry')), findsNothing);
    expect(find.text('重试'), findsNothing);
    expect(find.byKey(const ValueKey<String>('play-pause')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 320));
    expect(_controlsOverlay(tester).opacity, 1);
  });

  testWidgets('切换到失败内核后保留原播放画面和生命周期并提示错误', (WidgetTester tester) async {
    const VideoKernelDescriptor failingDescriptor = VideoKernelDescriptor(
      id: 'failing-kernel',
      displayName: '失败测试内核',
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
    final Finder failingKernel = find.byKey(
      const ValueKey<String>('kernel-option-failing-kernel'),
    );
    await tester.ensureVisible(failingKernel);
    await tester.pumpAndSettle();
    await tester.tap(failingKernel);
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
    expect(
      find.byKey(const ValueKey<String>('settings-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kernel-switch-diagnostic')),
      findsOneWidget,
    );
    expect(find.text('切换目标播放器内核失败，已恢复原内核。'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('语义等价的选集列表重建不会取消同一在途目标', (WidgetTester tester) async {
    // Catches list identity, rather than episode identity and source, cancelling
    // an otherwise unchanged open.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'equivalent-episode-rebuild',
      displayName: '等价列表重建测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _SelectiveDelayedEpisodeAdapter adapter =
        _SelectiveDelayedEpisodeAdapter(descriptor);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    final List<VideoEpisode> original = testEpisodes();
    await controller.open(original.first.source);
    addTearDown(controller.dispose);
    List<VideoEpisode> visibleEpisodes = original;
    final List<String> changed = <String>[];
    late StateSetter updateHost;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: controller,
                episodes: visibleEpisodes,
                initialEpisodeId: 'e1',
                onEpisodeChanged: (VideoEpisode episode) {
                  changed.add('${episode.id}:${episode.title}');
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pump();
    expect(adapter.delayedOpenStarted, isTrue);

    updateHost(() {
      visibleEpisodes = <VideoEpisode>[
        for (final VideoEpisode episode in original)
          VideoEpisode(
            id: episode.id,
            title: episode.id == 'e2' ? '第 2 集（重建）' : episode.title,
            subtitle: episode.subtitle,
            source: VideoSource.network(episode.source.uri.toString()),
          ),
      ];
    });
    await tester.pump();
    adapter.completeDelayedOpen();
    await tester.pumpAndSettle();

    expect(controller.value.source?.uri, original[1].source.uri);
    expect(changed, <String>['e2:第 2 集（重建）']);
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();
    expect(controller.value.source?.uri, original[2].source.uri);
    expect(changed, <String>['e2:第 2 集（重建）', 'e3:第 3 集']);
  });

  testWidgets('语义变化使旧选集完成失效并恢复真实播放源与导航', (WidgetTester tester) async {
    // Catches View-only invalidation leaving the stale adapter source playing.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'semantic-episode-rebuild',
      displayName: '语义列表变化测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _EpisodeCancellationTracker tracker = _EpisodeCancellationTracker();
    final VideoEpisode first = VideoEpisode(
      id: 'e1',
      title: '第 1 集',
      source: VideoSource.network(
        'https://example.com/e1.mp4',
        metadata: const VideoMetadata(title: 'Surface A'),
      ),
    );
    final VideoEpisode stale = VideoEpisode(
      id: 'e2',
      title: '第 2 集（旧源）',
      source: VideoSource.network(
        'https://example.com/e2-old.mp4',
        metadata: const VideoMetadata(title: 'Surface stale B'),
      ),
    );
    final VideoEpisode last = VideoEpisode(
      id: 'e3',
      title: '第 3 集',
      source: VideoSource.network('https://example.com/e3.mp4'),
    );
    final VideoEpisode replacement = VideoEpisode(
      id: 'e2',
      title: '第 2 集（新源）',
      source: VideoSource.network(
        'https://example.com/e2-new.mp4',
        metadata: const VideoMetadata(title: 'Surface new B'),
      ),
    );
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: descriptor,
            create: () => tracker.createAdapter(descriptor),
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    await controller.open(first.source);
    addTearDown(controller.dispose);
    List<VideoEpisode> visibleEpisodes = <VideoEpisode>[first, stale, last];
    final List<String> changed = <String>[];
    late StateSetter updateHost;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: controller,
                episodes: visibleEpisodes,
                initialEpisodeId: 'e1',
                onEpisodeChanged: (VideoEpisode episode) {
                  changed.add(episode.id);
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tracker.staleStarted.future;
    updateHost(
      () => visibleEpisodes = <VideoEpisode>[first, replacement, last],
    );
    await tester.pump();
    tracker.releaseStale();
    await tester.pumpAndSettle();

    expect(controller.value.source?.uri, first.source.uri);
    expect(find.text('Surface A'), findsOneWidget);
    expect(tracker.adapters.first.disposed, isTrue);
    expect(changed, isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();
    expect(controller.value.source?.uri, replacement.source.uri);
    expect(find.text('Surface new B'), findsOneWidget);
    expect(changed, <String>['e2']);
  });

  testWidgets('控制器 A→B→A 后旧完成不能改变 A 的真实源或当前导航', (WidgetTester tester) async {
    // Catches controller identity becoming current again and legitimizing an
    // operation that was superseded while detached.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'episode-a-b-a',
      displayName: 'A→B→A 测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.windows},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _EpisodeCancellationTracker tracker = _EpisodeCancellationTracker();
    final List<VideoEpisode> episodes = <VideoEpisode>[
      VideoEpisode(
        id: 'e1',
        title: '第 1 集',
        source: VideoSource.network(
          'https://example.com/e1.mp4',
          metadata: const VideoMetadata(title: 'Controller A source'),
        ),
      ),
      VideoEpisode(
        id: 'e2',
        title: '第 2 集',
        source: VideoSource.network(
          'https://example.com/e2-old.mp4',
          metadata: const VideoMetadata(title: 'Stale source'),
        ),
      ),
    ];
    final UnifiedVideoController firstController = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: descriptor,
            create: () => tracker.createAdapter(descriptor),
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.windows,
      stateRefreshInterval: null,
    );
    final UnifiedVideoController replacementController = createFakeController();
    await firstController.open(episodes.first.source);
    await replacementController.open(episodes.first.source);
    addTearDown(firstController.dispose);
    addTearDown(replacementController.dispose);
    UnifiedVideoController visibleController = firstController;
    final List<String> changed = <String>[];
    late StateSetter updateHost;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                  changed.add(episode.id);
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tracker.staleStarted.future;
    updateHost(() => visibleController = replacementController);
    await tester.pump();
    updateHost(() => visibleController = firstController);
    await tester.pump();
    tracker.releaseStale();
    await tester.pumpAndSettle();

    expect(firstController.value.source?.uri, episodes.first.source.uri);
    expect(find.text('Controller A source'), findsOneWidget);
    expect(changed, isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
    await tester.pumpAndSettle();
    expect(firstController.value.source?.uri, episodes[1].source.uri);
    expect(changed, <String>['e2']);
  });

  testWidgets('选集回调异常通过 FlutterError 报告且成功播放仍提交', (WidgetTester tester) async {
    // Catches host callback failures being mistaken for controller.open failures.
    final FlutterExceptionHandler? previousHandler = FlutterError.onError;
    final List<FlutterErrorDetails> reported = <FlutterErrorDetails>[];
    FlutterError.onError = reported.add;
    final List<VideoEpisode> episodes = testEpisodes();
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      episodes: episodes,
      initialEpisodeId: 'e1',
      onEpisodeChanged: (_) => throw StateError('host callback failed'),
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );

    try {
      await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = previousHandler;
    }

    expect(controller.value.lifecycle, UnifiedVideoLifecycle.ready);
    expect(controller.value.source?.uri, episodes[1].source.uri);
    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<StateError>());
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsNothing);
  });

  testWidgets('标题副标题优先活动选集并随换源和保留 ID 的列表更新', (WidgetTester tester) async {
    // Catches Expanded/Wide headings ignoring the resolved VideoEpisode.
    final List<VideoEpisode> episodes = <VideoEpisode>[
      VideoEpisode(
        id: 'e1',
        title: '选集标题一',
        subtitle: '选集副标题一',
        source: VideoSource.network(
          'https://example.com/title-e1.mp4',
          metadata: const VideoMetadata(title: '媒体标题一', episodeTitle: '媒体副标题一'),
        ),
      ),
      VideoEpisode(
        id: 'e2',
        title: '选集标题二',
        subtitle: '选集副标题二',
        source: VideoSource.network(
          'https://example.com/title-e2.mp4',
          metadata: const VideoMetadata(title: '媒体标题二', episodeTitle: '媒体副标题二'),
        ),
      ),
    ];
    final UnifiedVideoController controller = createFakeController();
    await controller.open(episodes.first.source);
    addTearDown(controller.dispose);
    List<VideoEpisode> visibleEpisodes = episodes;
    late StateSetter updateHost;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateHost = setState;
              return UnifiedVideoPlayer(
                controller: controller,
                episodes: visibleEpisodes,
                initialEpisodeId: 'e1',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('选集标题一'), findsOneWidget);
    expect(find.text('选集副标题一'), findsOneWidget);

    await controller.open(episodes[1].source);
    await tester.pumpAndSettle();
    expect(find.text('选集标题二'), findsOneWidget);
    expect(find.text('选集副标题二'), findsOneWidget);

    updateHost(() {
      visibleEpisodes = <VideoEpisode>[
        episodes.first,
        VideoEpisode(
          id: 'e2',
          title: '保留 ID 的新标题',
          subtitle: '保留 ID 的新副标题',
          source: episodes[1].source,
        ),
      ];
    });
    await tester.pumpAndSettle();
    expect(find.text('保留 ID 的新标题'), findsOneWidget);
    expect(find.text('保留 ID 的新副标题'), findsOneWidget);

    updateHost(() => visibleEpisodes = const <VideoEpisode>[]);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('player-title')))
          .data,
      '媒体标题二',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('player-subtitle')))
          .data,
      '媒体副标题二',
    );
  });

  testWidgets('桌面嵌入使用 18 圆角而全屏为 0 且 Surface 唯一', (WidgetTester tester) async {
    // Catches desktop clipping being absent or leaking into fullscreen.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    expect(
      find.byKey(const ValueKey<String>('player-frame-clip')),
      findsOneWidget,
    );
    ClipRRect clip() => tester.widget<ClipRRect>(
      find.byKey(const ValueKey<String>('player-frame-clip')),
    );

    expect(clip().borderRadius, BorderRadius.circular(18));
    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();
    expect(clip().borderRadius, BorderRadius.zero);
    expect(
      find.byKey(const ValueKey<String>('video-surface-host')),
      findsOneWidget,
    );
    expect(controller.value.fullscreen, isTrue);
  });

  testWidgets('Windows 639 与 640 宽嵌入都保持桌面 2 像素底距', (WidgetTester tester) async {
    // Catches compact desktop layouts inheriting the mobile one-pixel gap.
    Future<double> bottomGap(double width) async {
      await pumpPlayer(
        tester,
        platform: UnifiedVideoPlatform.windows,
        viewSize: Size(width, 600),
      );
      final double frameBottom = tester
          .getBottomRight(find.byKey(const ValueKey<String>('player-frame')))
          .dy;
      final double controlsBottom = tester
          .getBottomRight(
            find.byKey(const ValueKey<String>('primary-controls-row')),
          )
          .dy;
      return frameBottom - controlsBottom;
    }

    expect(await bottomGap(639), 2);
    expect(await bottomGap(640), 2);
  });

  testWidgets('选集和设置使用圆角中性组表面且行不是 Card 或 Chip', (WidgetTester tester) async {
    // Catches either missing visual grouping or per-row card/chip regressions.
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    const Color expectedColor = Color(0x14FFFFFF);
    const BorderRadius expectedRadius = BorderRadius.all(Radius.circular(12));

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('episode-list-group-surface')),
      findsOneWidget,
    );
    final DecoratedBox episodeGroup = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('episode-list-group-surface')),
    );
    final BoxDecoration episodeDecoration =
        episodeGroup.decoration as BoxDecoration;
    expect(episodeDecoration.color, expectedColor);
    expect(episodeDecoration.borderRadius, expectedRadius);
    final Finder episodePanel = find.byKey(
      const ValueKey<String>('episode-panel'),
    );
    expect(
      find.descendant(of: episodePanel, matching: find.byType(Card)),
      findsNothing,
    );
    expect(
      find.descendant(of: episodePanel, matching: find.byType(Chip)),
      findsNothing,
    );

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    for (final String key in <String>[
      'settings-group-picture-surface',
      'settings-group-playback-surface',
      'settings-group-kernel-surface',
      'settings-group-diagnostics-surface',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
      final DecoratedBox group = tester.widget<DecoratedBox>(
        find.byKey(ValueKey<String>(key)),
      );
      final BoxDecoration decoration = group.decoration as BoxDecoration;
      expect(decoration.color, expectedColor);
      expect(decoration.borderRadius, expectedRadius);
    }
    final Finder settingsPanel = find.byKey(
      const ValueKey<String>('settings-panel'),
    );
    expect(
      find.descendant(of: settingsPanel, matching: find.byType(Card)),
      findsNothing,
    );
    expect(
      find.descendant(of: settingsPanel, matching: find.byType(Chip)),
      findsNothing,
    );
  });

  testWidgets('手机画面轻点在播放时切换主控显隐', (WidgetTester tester) async {
    // Catches touch taps being reduced to show/reset-only behavior.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      autoHideControlsDelay: const Duration(minutes: 1),
      platform: UnifiedVideoPlatform.android,
      viewSize: const Size(393, 852),
    );
    await controller.play();
    await tester.pump();
    final Offset surfaceCenter = tester.getCenter(
      find.byKey(const ValueKey<String>('player-frame')),
    );

    await tester.tapAt(surfaceCenter);
    await tester.pump();
    expect(_controlsOverlay(tester).opacity, 0);

    await tester.tapAt(surfaceCenter);
    await tester.pump();
    expect(_controlsOverlay(tester).opacity, 1);
  });

  testWidgets('桌面画面按下只显示主控而不会反向隐藏', (WidgetTester tester) async {
    // Catches the desktop pointer-down show path racing the mobile tap toggle.
    final UnifiedVideoController controller = await pumpPlayer(
      tester,
      autoHideControlsDelay: const Duration(minutes: 1),
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    await controller.play();
    await tester.pump();

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey<String>('player-frame'))),
    );
    await tester.pump();

    expect(_controlsOverlay(tester).opacity, 1);
  });

  testWidgets('ready 状态不会因计时器自动隐藏主控', (WidgetTester tester) async {
    // Catches prepared-but-not-playing media being treated as active playback.
    await pumpPlayer(
      tester,
      autoHideControlsDelay: const Duration(milliseconds: 100),
    );

    await tester.pump(const Duration(milliseconds: 320));

    expect(_controlsOverlay(tester).opacity, 1);
  });

  testWidgets('降低效果时选集底部行赢得指针且不会触发下层主控', (WidgetTester tester) async {
    // Catches reduced-effects overlay composition retaining the old hit-test order.
    final List<VideoEpisode> episodes = List<VideoEpisode>.generate(
      8,
      (int index) => VideoEpisode(
        id: 'lower-${index + 1}',
        title: '第 ${index + 1} 集',
        source: VideoSource.network(
          'https://example.com/lower-${index + 1}.mp4',
        ),
      ),
    );
    final List<String> changed = <String>[];
    final UnifiedVideoController controller = createFakeController();
    await controller.open(episodes.first.source);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(852, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: true, highContrast: true),
            child: child!,
          );
        },
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: episodes,
            initialEpisodeId: episodes.first.id,
            onEpisodeChanged: (VideoEpisode episode) {
              changed.add(episode.id);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    final Finder target = find.byKey(
      const ValueKey<String>('episode-option-lower-8'),
    );
    await tester.scrollUntilVisible(
      target,
      100,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('episode-panel')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    final Rect frame = tester.getRect(
      find.byKey(const ValueKey<String>('player-frame')),
    );
    expect(tester.getCenter(target).dy, greaterThan(frame.bottom - 100));

    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(controller.value.source?.uri, episodes.last.source.uri);
    expect(changed, <String>[episodes.last.id]);
  });

  testWidgets('上下文面板阻断下层语义并保留明确关闭出口', (WidgetTester tester) async {
    // Catches hidden controls remaining reachable to assistive technologies.
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpPlayer(
      tester,
      episodes: testEpisodes(),
      initialEpisodeId: 'e1',
      platform: UnifiedVideoPlatform.windows,
      viewSize: const Size(1280, 720),
    );
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('播放'), findsNothing);
    expect(find.semantics.byLabel('上一集'), findsNothing);
    expect(find.semantics.byLabel('进入全屏'), findsNothing);
    expect(find.semantics.byLabel('第 1 集，启程，正在播放'), findsOne);
    expect(find.semantics.byLabel('关闭选集'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey<String>('context-overlay-close')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('episode-panel')), findsNothing);
    semantics.dispose();
  });

  testWidgets('选集延迟 open 隐藏主控时全屏出口仍可立即退出', (WidgetTester tester) async {
    // Catches opening state removing the only usable fullscreen escape.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'fullscreen-delayed-episode',
      displayName: '全屏延迟选集内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.unknown},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _EpisodeCancellationTracker tracker = _EpisodeCancellationTracker();
    final List<VideoEpisode> episodes = <VideoEpisode>[
      VideoEpisode(
        id: 'e1',
        title: '第 1 集',
        source: VideoSource.network('https://example.com/e1.mp4'),
      ),
      VideoEpisode(
        id: 'e2',
        title: '第 2 集',
        source: VideoSource.network('https://example.com/e2-old.mp4'),
      ),
    ];
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          RegisteredVideoKernel(
            descriptor: descriptor,
            create: () => tracker.createAdapter(descriptor),
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.unknown,
      stateRefreshInterval: null,
    );
    await controller.open(episodes.first.source);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(852, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: episodes,
            initialEpisodeId: 'e1',
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('episode-option-e2')));
    await tracker.staleStarted.future;
    await tester.pump();

    final Finder escape = find.byKey(
      const ValueKey<String>('context-overlay-escape'),
    );
    final bool escapeHitTestable = escape.hitTestable().evaluate().length == 1;
    if (escapeHitTestable) {
      await tester.tap(escape);
      await tester.pump();
    }
    final bool exitedBeforeOpen = !controller.value.fullscreen;
    tracker.releaseStale();
    await tester.pumpAndSettle();

    expect(escapeHitTestable, isTrue);
    expect(exitedBeforeOpen, isTrue);
    expect(
      find.byKey(const ValueKey<String>('video-surface-host')),
      findsOneWidget,
    );
  });

  testWidgets('选集面板延迟切核时全屏出口仍可立即退出', (WidgetTester tester) async {
    // Catches kernel switching relying on a control beneath the open panel.
    const VideoKernelDescriptor delayedDescriptor = VideoKernelDescriptor(
      id: 'fullscreen-delayed-kernel',
      displayName: '全屏延迟切核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.unknown},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _SignalledDelayedOpenVideoKernelAdapter delayedAdapter =
        _SignalledDelayedOpenVideoKernelAdapter(delayedDescriptor);
    final UnifiedVideoController controller = UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          createFakeVideoKernel(),
          RegisteredVideoKernel(
            descriptor: delayedDescriptor,
            create: () => delayedAdapter,
          ),
        ],
      ),
      platform: UnifiedVideoPlatform.unknown,
      stateRefreshInterval: null,
    );
    await controller.open(
      VideoSource.network(sampleMp4Url),
      preference: KernelPreference.exact('fake'),
    );
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(852, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UnifiedVideoPlayer(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('fullscreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('more-menu')));
    await tester.pumpAndSettle();
    final Finder delayedKernel = find.byKey(
      const ValueKey<String>('kernel-option-fullscreen-delayed-kernel'),
    );
    await tester.ensureVisible(delayedKernel);
    await tester.tap(delayedKernel);
    await delayedAdapter.openStarted.future;
    await tester.pump();

    final Finder escape = find.byKey(
      const ValueKey<String>('context-overlay-escape'),
    );
    final bool escapeHitTestable = escape.hitTestable().evaluate().length == 1;
    if (escapeHitTestable) {
      await tester.tap(escape);
      await tester.pump();
    }
    final bool exitedBeforeSwitch = !controller.value.fullscreen;
    delayedAdapter.completeOpen();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(escapeHitTestable, isTrue);
    expect(exitedBeforeSwitch, isTrue);
    expect(
      find.byKey(const ValueKey<String>('video-surface-host')),
      findsOneWidget,
    );
  });

  testWidgets('README 选集语义要求显式 open 且 initialEpisodeId 不自动播放', (
    WidgetTester tester,
  ) async {
    // Exercises the documented contract without asserting README source text.
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'readme-episode-contract',
      displayName: 'README 选集契约内核',
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
    final List<VideoEpisode> episodes = testEpisodes();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedVideoPlayer(
            controller: controller,
            episodes: episodes,
            initialEpisodeId: episodes.first.id,
          ),
        ),
      ),
    );
    expect(adapter.openCount, 0);
    expect(controller.value.source, isNull);

    await controller.open(episodes.first.source);
    await tester.pumpAndSettle();
    expect(adapter.openCount, 1);
    expect(controller.value.source?.uri, episodes.first.source.uri);
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

class _PortraitSurfaceVideoKernelAdapter extends FakeVideoKernelAdapter {
  _PortraitSurfaceVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  @override
  Widget buildSurface(BuildContext context, UnifiedVideoState state) {
    return const FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 9,
        height: 16,
        child: ColoredBox(
          key: ValueKey<String>('portrait-surface-content'),
          color: Colors.black,
        ),
      ),
    );
  }
}

class _FailingSpeedVideoKernelAdapter extends FakeVideoKernelAdapter {
  _FailingSpeedVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  @override
  Future<UnifiedVideoState> setSpeed(
    double speed,
    UnifiedVideoState state,
  ) async {
    if ((speed - 1.25).abs() < 0.001) {
      throw StateError('模拟倍速应用失败');
    }
    return super.setSpeed(speed, state);
  }
}

class _DelayedThenFailingSpeedVideoKernelAdapter
    extends FakeVideoKernelAdapter {
  _DelayedThenFailingSpeedVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  final Completer<UnifiedVideoState> _firstRequest =
      Completer<UnifiedVideoState>();
  UnifiedVideoState? _firstState;
  double? _firstSpeed;
  int _requestCount = 0;

  @override
  Future<UnifiedVideoState> setSpeed(double speed, UnifiedVideoState state) {
    _requestCount += 1;
    if (_requestCount == 1) {
      _firstState = state;
      _firstSpeed = speed;
      return _firstRequest.future;
    }
    throw StateError('模拟最新倍速请求失败');
  }

  void completeFirstRequest() {
    _firstRequest.complete(_firstState!.copyWith(speed: _firstSpeed));
  }
}

class _FailOnceOpenTracker {
  int attempts = 0;
}

class _FailOnceOpenVideoKernelAdapter extends FakeVideoKernelAdapter {
  _FailOnceOpenVideoKernelAdapter(
    VideoKernelDescriptor descriptor,
    this.tracker,
  ) : super(descriptor: descriptor);

  final _FailOnceOpenTracker tracker;

  @override
  Future<UnifiedVideoState> open(VideoSource source, UnifiedVideoState state) {
    tracker.attempts += 1;
    if (tracker.attempts == 1) {
      throw StateError('模拟首次打开失败');
    }
    return super.open(source, state);
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

class _SignalledDelayedOpenVideoKernelAdapter extends FakeVideoKernelAdapter {
  _SignalledDelayedOpenVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  final Completer<void> openStarted = Completer<void>();
  final Completer<void> _openCompleter = Completer<void>();

  void completeOpen() => _openCompleter.complete();

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    openStarted.complete();
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

class _SelectiveFailVideoKernelAdapter extends FakeVideoKernelAdapter {
  _SelectiveFailVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  @override
  Future<UnifiedVideoState> open(VideoSource source, UnifiedVideoState state) {
    if (source.uri.path.endsWith('e2.mp4')) {
      throw StateError('模拟选集打开失败');
    }
    return super.open(source, state);
  }
}

class _SelectiveDelayedEpisodeAdapter extends FakeVideoKernelAdapter {
  _SelectiveDelayedEpisodeAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  final Completer<void> _delayedOpen = Completer<void>();
  bool delayedOpenStarted = false;

  void completeDelayedOpen() => _delayedOpen.complete();

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    if (source.uri.path.endsWith('e2.mp4')) {
      delayedOpenStarted = true;
      await _delayedOpen.future;
    }
    return super.open(source, state);
  }
}

class _EpisodeCancellationTracker {
  final Completer<void> staleStarted = Completer<void>();
  final Completer<void> _staleRelease = Completer<void>();
  final List<_EpisodeCancellationAdapter> adapters =
      <_EpisodeCancellationAdapter>[];

  _EpisodeCancellationAdapter createAdapter(VideoKernelDescriptor descriptor) {
    final _EpisodeCancellationAdapter adapter = _EpisodeCancellationAdapter(
      descriptor,
      this,
    );
    adapters.add(adapter);
    return adapter;
  }

  void releaseStale() => _staleRelease.complete();
}

class _EpisodeCancellationAdapter extends FakeVideoKernelAdapter {
  _EpisodeCancellationAdapter(VideoKernelDescriptor descriptor, this.tracker)
    : super(descriptor: descriptor);

  final _EpisodeCancellationTracker tracker;
  bool disposed = false;

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    if (source.uri.path.endsWith('/e2-old.mp4')) {
      if (!tracker.staleStarted.isCompleted) {
        tracker.staleStarted.complete();
      }
      await tracker._staleRelease.future;
    }
    return super.open(source, state);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

class _FailOnceEpisodeTracker {
  int attempts = 0;
}

class _FailOnceEpisodeAdapter extends FakeVideoKernelAdapter {
  _FailOnceEpisodeAdapter(VideoKernelDescriptor descriptor, this.tracker)
    : super(descriptor: descriptor);

  final _FailOnceEpisodeTracker tracker;

  @override
  Future<UnifiedVideoState> open(VideoSource source, UnifiedVideoState state) {
    if (source.uri.path.endsWith('e2.mp4')) {
      tracker.attempts += 1;
      if (tracker.attempts == 1) {
        throw StateError('模拟选集首次打开失败');
      }
    }
    return super.open(source, state);
  }
}
