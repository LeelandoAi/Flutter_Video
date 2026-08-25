import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';
import 'package:lee_video/src/fullscreen_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  VideoSource source() {
    return VideoSource.network(
      sampleMp4Url,
      metadata: const VideoMetadata(title: '测试影片'),
    );
  }

  UnifiedVideoController controller({
    List<RegisteredVideoKernel>? kernels,
    KernelPreference preference = const KernelPreference.automatic(),
    UnifiedVideoPlatform platform = UnifiedVideoPlatform.android,
    VideoKernelRuntimeCoordinator? runtimeCoordinator,
    Duration? stateRefreshInterval = const Duration(milliseconds: 300),
  }) {
    return UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: kernels ?? <RegisteredVideoKernel>[createFakeVideoKernel()],
      ),
      platform: platform,
      preference: preference,
      runtimeCoordinator: runtimeCoordinator,
      stateRefreshInterval: stateRefreshInterval,
    );
  }

  test('统一控制器执行播放、暂停、跳转、缩放、倍速和全屏命令', () async {
    final UnifiedVideoController player = controller();
    addTearDown(player.dispose);

    await player.open(source());
    expect(player.value.lifecycle, UnifiedVideoLifecycle.ready);
    expect(player.value.activeKernelId, 'fake');

    await player.play();
    expect(player.value.lifecycle, UnifiedVideoLifecycle.playing);

    await player.pause();
    expect(player.value.lifecycle, UnifiedVideoLifecycle.paused);

    await player.seek(const Duration(minutes: 2));
    expect(player.value.position, const Duration(minutes: 2));

    await player.setFit(UnifiedVideoFit.cover);
    expect(player.value.fit, UnifiedVideoFit.cover);

    await player.setSpeed(1.25);
    expect(player.value.speed, 1.25);

    await player.enterFullscreen();
    expect(player.value.fullscreen, isTrue);

    await player.exitFullscreen();
    expect(player.value.fullscreen, isFalse);
  });

  test('控制器打开后持续刷新后端位置快照', () async {
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'advancing',
      displayName: '进度刷新测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: descriptor,
          create: () => _AdvancingSnapshotVideoKernelAdapter(descriptor),
        ),
      ],
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 750));

    expect(player.value.position, greaterThan(Duration.zero));
  });

  test('在途定时快照不会覆盖随后排队命令的状态', () async {
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'blocked-snapshot',
      displayName: '阻塞快照测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _BlockedSnapshotVideoKernelAdapter adapter =
        _BlockedSnapshotVideoKernelAdapter(descriptor);
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
      ],
      stateRefreshInterval: const Duration(milliseconds: 10),
    );
    addTearDown(player.dispose);

    await player.open(source());
    await adapter.snapshotStarted.future;

    await player.seek(const Duration(minutes: 2));
    expect(player.value.position, const Duration(minutes: 2));

    adapter.releaseSnapshot();
    await adapter.snapshotFinished.future;
    await Future<void>.delayed(Duration.zero);

    expect(player.value.position, const Duration(minutes: 2));
  });

  test('释放控制器后延迟命令不会写入 notifier 或产生异步错误', () async {
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'delayed-play',
      displayName: '延迟播放测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _DelayedPlayVideoKernelAdapter adapter =
        _DelayedPlayVideoKernelAdapter(descriptor);
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
      ],
      stateRefreshInterval: null,
    );
    int notifications = 0;
    player.addListener(() => notifications++);

    await player.open(source());
    final Future<void> playFuture = player.play();
    await adapter.playStarted.future;

    player.dispose();
    final int notificationsAfterDispose = notifications;
    adapter.releasePlay();

    await expectLater(playFuture, completes);
    expect(player.value.lifecycle, UnifiedVideoLifecycle.disposed);
    expect(notifications, notificationsAfterDispose);
  });

  test('切核期间释放控制器会取消状态提交并完成资源清理', () async {
    const VideoKernelDescriptor firstDescriptor = VideoKernelDescriptor(
      id: 'blocked-switch',
      displayName: '阻塞切核测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _BlockedSwitchVideoKernelAdapter adapter =
        _BlockedSwitchVideoKernelAdapter(firstDescriptor);
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: firstDescriptor,
          create: () => adapter,
        ),
        createFakeVideoKernel(id: 'second'),
      ],
      preference: KernelPreference.exact('blocked-switch'),
      stateRefreshInterval: null,
    );
    int notifications = 0;
    player.addListener(() => notifications++);

    await player.open(source());
    final Future<void> switchFuture = player.switchKernel('second');
    await adapter.snapshotStarted.future;

    player.dispose();
    final int notificationsAfterDispose = notifications;
    adapter.releaseSnapshot();

    await expectLater(switchFuture, completes);
    await adapter.disposeCompleted.future;
    await adapter.runtimeReleased.future;

    expect(player.value.lifecycle, UnifiedVideoLifecycle.disposed);
    expect(notifications, notificationsAfterDispose);
    expect(adapter.disposeCount, 1);
    expect(adapter.runtimeReleaseCount, 1);
  });

  test('切换播放器内核后保留当前播放进度和播放状态', () async {
    const VideoKernelDescriptor firstDescriptor = VideoKernelDescriptor(
      id: 'first',
      displayName: '第一测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    const VideoKernelDescriptor secondDescriptor = VideoKernelDescriptor(
      id: 'second',
      displayName: '第二测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: firstDescriptor,
          create: () => FakeVideoKernelAdapter(descriptor: firstDescriptor),
        ),
        RegisteredVideoKernel(
          descriptor: secondDescriptor,
          create: () => FakeVideoKernelAdapter(descriptor: secondDescriptor),
        ),
      ],
      preference: KernelPreference.exact('first'),
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.seek(const Duration(minutes: 2));
    await player.play();

    await player.switchKernel('second');

    expect(player.value.activeKernelId, 'second');
    expect(player.value.position, const Duration(minutes: 2));
    expect(player.value.lifecycle, UnifiedVideoLifecycle.playing);
  });

  test('切换内核保持进度、暂停状态、倍速、缩放、音量和全屏', () async {
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        createFakeVideoKernel(id: 'first'),
        createFakeVideoKernel(id: 'second'),
      ],
      preference: KernelPreference.exact('first'),
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.seek(const Duration(minutes: 2));
    await player.setSpeed(1.5);
    await player.setFit(UnifiedVideoFit.cover);
    await player.setVolume(0.4);
    await player.pause();
    await player.enterFullscreen(syncPlatform: false);

    await player.switchKernel('second');

    expect(player.value.activeKernelId, 'second');
    expect(player.value.position, const Duration(minutes: 2));
    expect(player.value.lifecycle, UnifiedVideoLifecycle.paused);
    expect(player.value.speed, 1.5);
    expect(player.value.fit, UnifiedVideoFit.cover);
    expect(player.value.volume, 0.4);
    expect(player.value.fullscreen, isTrue);
  });

  test('切换内核按事务顺序释放并恢复适配器状态', () async {
    const VideoKernelDescriptor firstDescriptor = VideoKernelDescriptor(
      id: 'first',
      displayName: '第一日志测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    const VideoKernelDescriptor secondDescriptor = VideoKernelDescriptor(
      id: 'second',
      displayName: '第二日志测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final List<String> log = <String>[];
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: firstDescriptor,
          create: () => _LoggingVideoKernelAdapter(firstDescriptor, log),
        ),
        RegisteredVideoKernel(
          descriptor: secondDescriptor,
          create: () => _LoggingVideoKernelAdapter(secondDescriptor, log),
        ),
      ],
      preference: KernelPreference.exact('first'),
      runtimeCoordinator: VideoKernelRuntimeCoordinator(),
      stateRefreshInterval: null,
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.seek(const Duration(seconds: 30));
    log.clear();

    await player.switchKernel('second');

    expect(log, <String>[
      'first.snapshot',
      'first.dispose',
      'first.runtime.release',
      'second.runtime.acquire',
      'second.initialize',
      'second.open',
      'second.seek',
      'second.snapshot',
      'second.speed',
      'second.fit',
      'second.volume',
    ]);
  });

  test('目标内核失败后回滚原内核并继续播放', () async {
    const VideoKernelDescriptor failingDescriptor = VideoKernelDescriptor(
      id: 'failing',
      displayName: '失败测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        createFakeVideoKernel(id: 'stable'),
        RegisteredVideoKernel(
          descriptor: failingDescriptor,
          create: () => _FailingOpenVideoKernelAdapter(failingDescriptor),
        ),
      ],
      preference: KernelPreference.exact('stable'),
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.seek(const Duration(seconds: 30));
    await player.play();

    await expectLater(
      player.switchKernel('failing'),
      throwsA(isA<KernelSwitchException>()),
    );
    expect(player.value.activeKernelId, 'stable');
    expect(player.value.lifecycle, UnifiedVideoLifecycle.playing);
    expect(player.value.position, const Duration(seconds: 30));
    expect(player.value.lastKernelSwitchError, isNotNull);
  });

  test('切换内核时会重试恢复播放进度', () async {
    const VideoKernelDescriptor firstDescriptor = VideoKernelDescriptor(
      id: 'first',
      displayName: '第一测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    const VideoKernelDescriptor delayedSeekDescriptor = VideoKernelDescriptor(
      id: 'delayed-seek',
      displayName: '延迟 seek 测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: firstDescriptor,
          create: () => FakeVideoKernelAdapter(descriptor: firstDescriptor),
        ),
        RegisteredVideoKernel(
          descriptor: delayedSeekDescriptor,
          create: () => _DelayedSeekVideoKernelAdapter(delayedSeekDescriptor),
        ),
      ],
      preference: KernelPreference.exact('first'),
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.seek(const Duration(minutes: 3));

    await player.switchKernel('delayed-seek');

    expect(player.value.activeKernelId, 'delayed-seek');
    expect(player.value.position, const Duration(minutes: 3));
  });

  test('切换内核六次 seek 后进度仍未收敛会回滚', () async {
    await _expectInaccurateSeekRollsBack(
      controller: controller,
      source: source,
      offset: const Duration(seconds: -5),
    );
  });

  test('切换内核 seek 向前超调超过一秒也会回滚', () async {
    await _expectInaccurateSeekRollsBack(
      controller: controller,
      source: source,
      offset: const Duration(seconds: 5),
    );
  });

  test('全屏命令与切核事务串行且不会被旧快照覆盖', () async {
    const VideoKernelDescriptor firstDescriptor = VideoKernelDescriptor(
      id: 'blocked-fullscreen-switch',
      displayName: '阻塞全屏切换测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _BlockedSwitchVideoKernelAdapter adapter =
        _BlockedSwitchVideoKernelAdapter(firstDescriptor);
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: firstDescriptor,
          create: () => adapter,
        ),
        createFakeVideoKernel(id: 'second'),
      ],
      preference: KernelPreference.exact(firstDescriptor.id),
      stateRefreshInterval: null,
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.enterFullscreen(syncPlatform: false);
    final Future<void> switchFuture = player.switchKernel('second');
    await adapter.snapshotStarted.future;

    var exitCompleted = false;
    final Future<void> exitFuture = player
        .exitFullscreen(syncPlatform: false)
        .whenComplete(() => exitCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(exitCompleted, isFalse);

    adapter.releaseSnapshot();
    await switchFuture;
    await exitFuture;

    expect(player.value.activeKernelId, 'second');
    expect(player.value.fullscreen, isFalse);
  });

  test('原生全屏事件排队时保留最后一次平台状态', () async {
    UnifiedVideoFullscreenPlatform.changes.value = null;
    const VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'blocked-native-fullscreen',
      displayName: '阻塞原生全屏测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.macos},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final _DelayedPlayVideoKernelAdapter adapter =
        _DelayedPlayVideoKernelAdapter(descriptor);
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(descriptor: descriptor, create: () => adapter),
      ],
      platform: UnifiedVideoPlatform.macos,
      stateRefreshInterval: null,
    );
    addTearDown(() {
      player.dispose();
      UnifiedVideoFullscreenPlatform.changes.value = null;
    });

    await player.open(source());
    player.claimFullscreenOwnership();
    final Future<void> playFuture = player.play();
    await adapter.playStarted.future;

    UnifiedVideoFullscreenPlatform.changes.value = true;
    UnifiedVideoFullscreenPlatform.changes.value = false;
    adapter.releasePlay();

    await playFuture;
    await player.pause();
    expect(player.value.fullscreen, isFalse);
  });

  test('普通 open 不会让旧内核 snapshot 异常阻断候选回退', () async {
    const VideoKernelDescriptor oldDescriptor = VideoKernelDescriptor(
      id: 'old',
      displayName: '旧内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    const VideoKernelDescriptor failingDescriptor = VideoKernelDescriptor(
      id: 'failing',
      displayName: '打开失败内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: oldDescriptor,
          create: () => _ThrowingSnapshotVideoKernelAdapter(oldDescriptor),
        ),
        RegisteredVideoKernel(
          descriptor: failingDescriptor,
          create: () => _FailingOpenVideoKernelAdapter(failingDescriptor),
        ),
        createFakeVideoKernel(id: 'fallback'),
      ],
      preference: KernelPreference.exact(oldDescriptor.id),
      stateRefreshInterval: null,
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.open(
      VideoSource.network('https://example.com/next.mp4'),
      preference: const KernelPreference.ordered(<String>[
        'failing',
        'fallback',
      ], includeUnspecified: false),
    );

    expect(player.value.activeKernelId, 'fallback');
    expect(player.value.fallbackHistory, contains('failing'));
  });

  test('精确内核运行时冲突保留异常类型和 runtimeConflict 错误码', () async {
    final VideoKernelRuntimeCoordinator runtimeCoordinator =
        VideoKernelRuntimeCoordinator();
    final RegisteredVideoKernel occupied = _createRuntimeTestKernel(
      id: 'occupied',
      identity: 'fvp',
    );
    final RegisteredVideoKernel requested = _createRuntimeTestKernel(
      id: 'requested',
      identity: 'official',
    );
    final UnifiedVideoController first = controller(
      kernels: <RegisteredVideoKernel>[occupied],
      preference: KernelPreference.exact('occupied'),
      runtimeCoordinator: runtimeCoordinator,
      stateRefreshInterval: null,
    );
    final UnifiedVideoController second = controller(
      kernels: <RegisteredVideoKernel>[requested],
      preference: KernelPreference.exact('requested'),
      runtimeCoordinator: runtimeCoordinator,
      stateRefreshInterval: null,
    );
    final UnifiedVideoController fallback = controller(
      kernels: <RegisteredVideoKernel>[
        requested,
        createFakeVideoKernel(id: 'fallback'),
      ],
      preference: const KernelPreference.ordered(<String>[
        'requested',
        'fallback',
      ], includeUnspecified: false),
      runtimeCoordinator: runtimeCoordinator,
      stateRefreshInterval: null,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(fallback.dispose);

    await first.open(source());
    await expectLater(
      second.open(source()),
      throwsA(isA<KernelRuntimeConflictException>()),
    );

    expect(second.value.lifecycle, UnifiedVideoLifecycle.failed);
    expect(second.value.error?.code, UnifiedVideoErrorCode.runtimeConflict);
    expect(second.value.error?.diagnostics['runtimeGroup'], 'shared-platform');
    expect(second.value.error?.diagnostics['activeIdentity'], 'fvp');
    expect(second.value.error?.diagnostics['requestedIdentity'], 'official');

    await fallback.open(source());
    expect(fallback.value.activeKernelId, 'fallback');
    expect(fallback.value.fallbackHistory, contains('requested'));
  });

  test('精确运行时冲突与 adapter 清理同时失败时仍保留冲突诊断', () async {
    final VideoKernelRuntimeCoordinator runtimeCoordinator =
        VideoKernelRuntimeCoordinator();
    final RegisteredVideoKernel occupied = _createRuntimeTestKernel(
      id: 'occupied-double-failure',
      identity: 'fvp',
    );
    const VideoKernelDescriptor requestedDescriptor = VideoKernelDescriptor(
      id: 'requested-double-failure',
      displayName: '冲突且清理失败内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final RegisteredVideoKernel requested = RegisteredVideoKernel(
      descriptor: requestedDescriptor,
      create: () => _ConflictAndDisposeFailingAdapter(requestedDescriptor),
    );
    final UnifiedVideoController first = controller(
      kernels: <RegisteredVideoKernel>[occupied],
      preference: KernelPreference.exact(occupied.descriptor.id),
      runtimeCoordinator: runtimeCoordinator,
      stateRefreshInterval: null,
    );
    final UnifiedVideoController second = controller(
      kernels: <RegisteredVideoKernel>[requested],
      preference: KernelPreference.exact(requested.descriptor.id),
      runtimeCoordinator: runtimeCoordinator,
      stateRefreshInterval: null,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await first.open(source());

    late KernelRuntimeConflictException exception;
    try {
      await second.open(source());
      fail('精确运行时冲突应失败');
    } on KernelRuntimeConflictException catch (error) {
      exception = error;
    }

    expect(exception.cleanupError, isA<StateError>());
    expect(exception.cleanupError.toString(), contains('模拟冲突 adapter 清理失败'));
    expect(second.value.error?.code, UnifiedVideoErrorCode.runtimeConflict);
    expect(
      second.value.error?.diagnostics['cleanupError'],
      contains('模拟冲突 adapter 清理失败'),
    );
  });

  test('原内核运行时停用失败归类为 cleanupError 并重新激活后回滚', () async {
    const VideoKernelDescriptor stableDescriptor = VideoKernelDescriptor(
      id: 'stable-runtime-cleanup',
      displayName: '原内核清理失败测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final RegisteredVideoKernel target = createFakeVideoKernel(
      id: 'unopened-target',
    );
    var stableCreateCount = 0;
    var targetCreateCount = 0;
    late _FailOnceDeactivateRuntimeAdapter recoveredAdapter;
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: stableDescriptor,
          create: () {
            final bool failDeactivation = stableCreateCount++ == 0;
            final adapter = _FailOnceDeactivateRuntimeAdapter(
              stableDescriptor,
              failDeactivation: failDeactivation,
            );
            if (!failDeactivation) {
              recoveredAdapter = adapter;
            }
            return adapter;
          },
        ),
        RegisteredVideoKernel(
          descriptor: target.descriptor,
          create: () {
            targetCreateCount += 1;
            return target.create();
          },
        ),
      ],
      preference: KernelPreference.exact(stableDescriptor.id),
      runtimeCoordinator: VideoKernelRuntimeCoordinator(),
      stateRefreshInterval: null,
    );
    addTearDown(player.dispose);

    await player.open(source());

    late KernelSwitchException exception;
    try {
      await player.switchKernel(target.descriptor.id);
      fail('原内核停用失败时切换应回滚');
    } on KernelSwitchException catch (error) {
      exception = error;
    }

    expect(exception.rollbackSucceeded, isTrue);
    expect(exception.targetError.toString(), contains('释放原内核'));
    expect(exception.cleanupError, isA<StateError>());
    expect(exception.cleanupError.toString(), contains('模拟原内核运行时停用失败'));
    expect(targetCreateCount, 0);
    expect(recoveredAdapter.activationCount, 1);
    expect(player.value.activeKernelId, stableDescriptor.id);
  });

  test('目标内核清理失败会进入 KernelSwitchException 诊断并完成回滚', () async {
    const VideoKernelDescriptor failingDescriptor = VideoKernelDescriptor(
      id: 'failing-cleanup',
      displayName: '清理失败内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        createFakeVideoKernel(id: 'stable'),
        RegisteredVideoKernel(
          descriptor: failingDescriptor,
          create: () =>
              _FailingOpenAndCleanupVideoKernelAdapter(failingDescriptor),
        ),
      ],
      preference: KernelPreference.exact('stable'),
      runtimeCoordinator: VideoKernelRuntimeCoordinator(),
      stateRefreshInterval: null,
    );
    addTearDown(player.dispose);

    await player.open(source());
    await player.seek(const Duration(seconds: 30));

    late KernelSwitchException exception;
    try {
      await player.switchKernel(failingDescriptor.id);
      fail('切换应失败');
    } on KernelSwitchException catch (error) {
      exception = error;
    }

    expect(exception.rollbackSucceeded, isTrue);
    expect(exception.targetError, isA<StateError>());
    expect(exception.cleanupError, isA<StateError>());
    expect(exception.cleanupError.toString(), contains('模拟目标内核清理失败'));
    expect(player.value.activeKernelId, 'stable');
    expect(
      player.value.lastKernelSwitchError?.diagnostics['cleanupError'],
      contains('模拟目标内核清理失败'),
    );
  });

  test('注册表按偏好降级选择兼容内核并记录跳过历史', () async {
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        _createPlatformTestKernel(),
        createFakeVideoKernel(),
      ],
      preference: const KernelPreference.ordered(<String>[
        'video-player',
        'fake',
      ]),
      platform: UnifiedVideoPlatform.windows,
    );
    addTearDown(player.dispose);

    await player.open(source());

    expect(player.value.activeKernelId, 'fake');
    expect(player.value.fallbackHistory, contains('video-player'));
  });

  test('首选内核运行时打开失败后继续降级到下一个兼容内核', () async {
    const VideoKernelDescriptor failingDescriptor = VideoKernelDescriptor(
      id: 'failing',
      displayName: '失败测试内核',
      supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
      supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
    );
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: failingDescriptor,
          create: () => _FailingOpenVideoKernelAdapter(failingDescriptor),
        ),
        createFakeVideoKernel(),
      ],
      preference: const KernelPreference.ordered(<String>['failing', 'fake']),
    );
    addTearDown(player.dispose);

    await player.open(source());

    expect(player.value.lifecycle, UnifiedVideoLifecycle.ready);
    expect(player.value.activeKernelId, 'fake');
    expect(player.value.fallbackHistory, contains('failing'));
  });

  test('有序偏好可以限制只尝试显式列出的内核', () {
    final VideoKernelRegistry registry = VideoKernelRegistry(
      kernels: <RegisteredVideoKernel>[
        _createPlatformTestKernel(),
        createFakeVideoKernel(),
      ],
    );

    final List<RegisteredVideoKernel> candidates = registry.orderedCandidates(
      const KernelPreference.ordered(<String>[
        'video-player',
      ], includeUnspecified: false),
    );

    expect(
      candidates.map((RegisteredVideoKernel kernel) => kernel.descriptor.id),
      <String>['video-player'],
    );
  });

  test('没有兼容内核时返回不支持内核诊断', () async {
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[_createPlatformTestKernel()],
      platform: UnifiedVideoPlatform.windows,
    );
    addTearDown(player.dispose);

    await expectLater(
      player.open(source()),
      throwsA(isA<UnsupportedKernelException>()),
    );
    expect(player.value.lifecycle, UnifiedVideoLifecycle.failed);
    expect(player.value.error?.code, UnifiedVideoErrorCode.unsupportedKernel);
  });

  test('当前内核不支持倍速时返回不支持能力错误', () async {
    final VideoKernelDescriptor descriptor = VideoKernelDescriptor(
      id: 'limited',
      displayName: '受限测试内核',
      supportedPlatforms: const <UnifiedVideoPlatform>{
        UnifiedVideoPlatform.android,
      },
      supportedSourceTypes: const <VideoSourceType>{VideoSourceType.network},
      supportedSpeeds: const <double>[1.0],
    );
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        RegisteredVideoKernel(
          descriptor: descriptor,
          create: () => FakeVideoKernelAdapter(descriptor: descriptor),
        ),
      ],
    );
    addTearDown(player.dispose);

    await player.open(source());

    await expectLater(player.setSpeed(2.0), throwsUnsupportedError);
    expect(
      player.value.error?.code,
      UnifiedVideoErrorCode.unsupportedCapability,
    );
  });

  test('释放控制器后状态进入 disposed，后续命令失败', () async {
    final UnifiedVideoController player = controller();
    await player.open(source());

    player.dispose();

    expect(player.value.lifecycle, UnifiedVideoLifecycle.disposed);
    expect(player.play(), throwsStateError);
  });
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

class _FailingOpenAndCleanupVideoKernelAdapter
    extends _FailingOpenVideoKernelAdapter {
  _FailingOpenAndCleanupVideoKernelAdapter(super.descriptor);

  @override
  String get runtimeGroup => 'failing-cleanup-runtime';

  @override
  Future<void> deactivateRuntime() async {
    throw StateError('模拟目标内核清理失败');
  }
}

class _ConflictAndDisposeFailingAdapter extends FakeVideoKernelAdapter {
  _ConflictAndDisposeFailingAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  @override
  String get runtimeGroup => 'shared-platform';

  @override
  String get runtimeIdentity => 'official';

  @override
  Future<void> dispose() async {
    throw StateError('模拟冲突 adapter 清理失败');
  }
}

class _FailOnceDeactivateRuntimeAdapter extends FakeVideoKernelAdapter {
  _FailOnceDeactivateRuntimeAdapter(
    VideoKernelDescriptor descriptor, {
    required this.failDeactivation,
  }) : super(descriptor: descriptor);

  final bool failDeactivation;
  int activationCount = 0;

  @override
  String get runtimeGroup => 'stable-runtime-cleanup-group';

  @override
  String get runtimeIdentity => 'stable-runtime-cleanup-identity';

  @override
  Future<void> activateRuntime() async {
    activationCount += 1;
  }

  @override
  Future<void> deactivateRuntime() async {
    if (failDeactivation) {
      throw StateError('模拟原内核运行时停用失败');
    }
  }
}

class _ThrowingSnapshotVideoKernelAdapter extends FakeVideoKernelAdapter {
  _ThrowingSnapshotVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    throw StateError('模拟旧内核 snapshot 失败');
  }
}

class _AdvancingSnapshotVideoKernelAdapter extends FakeVideoKernelAdapter {
  _AdvancingSnapshotVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  Duration _position = Duration.zero;

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    if (state.isPlaying) {
      _position += const Duration(milliseconds: 300);
    }
    return state.copyWith(position: _position);
  }
}

class _BlockedSnapshotVideoKernelAdapter extends FakeVideoKernelAdapter {
  _BlockedSnapshotVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  final Completer<void> snapshotStarted = Completer<void>();
  final Completer<void> snapshotFinished = Completer<void>();
  final Completer<void> _snapshotRelease = Completer<void>();
  bool _blockedSnapshot = false;

  void releaseSnapshot() {
    _snapshotRelease.complete();
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    if (_blockedSnapshot) {
      return super.snapshot(state);
    }
    _blockedSnapshot = true;
    snapshotStarted.complete();
    await _snapshotRelease.future;
    snapshotFinished.complete();
    return state;
  }
}

class _DelayedPlayVideoKernelAdapter extends FakeVideoKernelAdapter {
  _DelayedPlayVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  final Completer<void> playStarted = Completer<void>();
  final Completer<void> _playRelease = Completer<void>();

  void releasePlay() {
    _playRelease.complete();
  }

  @override
  Future<UnifiedVideoState> play(UnifiedVideoState state) async {
    playStarted.complete();
    await _playRelease.future;
    return state.copyWith(lifecycle: UnifiedVideoLifecycle.playing);
  }
}

class _BlockedSwitchVideoKernelAdapter extends FakeVideoKernelAdapter {
  _BlockedSwitchVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  final Completer<void> snapshotStarted = Completer<void>();
  final Completer<void> disposeCompleted = Completer<void>();
  final Completer<void> runtimeReleased = Completer<void>();
  final Completer<void> _snapshotRelease = Completer<void>();
  int disposeCount = 0;
  int runtimeReleaseCount = 0;

  void releaseSnapshot() {
    _snapshotRelease.complete();
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    snapshotStarted.complete();
    await _snapshotRelease.future;
    return state;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await super.dispose();
    disposeCompleted.complete();
  }

  @override
  Future<void> deactivateRuntime() async {
    runtimeReleaseCount += 1;
    runtimeReleased.complete();
  }
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

class _DelayedSeekVideoKernelAdapter extends FakeVideoKernelAdapter {
  _DelayedSeekVideoKernelAdapter(VideoKernelDescriptor descriptor)
    : super(descriptor: descriptor);

  Duration _position = Duration.zero;
  int _seekAttempts = 0;

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    return (await super.open(source, state)).copyWith(position: _position);
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    _seekAttempts++;
    if (_seekAttempts >= 3) {
      _position = position;
    }
    return state.copyWith(position: _position);
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    return state.copyWith(position: _position);
  }
}

class _InaccurateSeekVideoKernelAdapter extends FakeVideoKernelAdapter {
  _InaccurateSeekVideoKernelAdapter(
    VideoKernelDescriptor descriptor,
    this.offset,
  ) : super(descriptor: descriptor);

  final Duration offset;
  Duration _position = Duration.zero;
  int seekAttempts = 0;

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    return (await super.open(source, state)).copyWith(position: _position);
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    seekAttempts += 1;
    _position = position + offset;
    return state.copyWith(position: _position);
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    return state.copyWith(position: _position);
  }
}

class _RuntimeTestVideoKernelAdapter extends FakeVideoKernelAdapter {
  _RuntimeTestVideoKernelAdapter({
    required VideoKernelDescriptor descriptor,
    required this.identity,
  }) : super(descriptor: descriptor);

  final String identity;

  @override
  String get runtimeGroup => 'shared-platform';

  @override
  String get runtimeIdentity => identity;
}

RegisteredVideoKernel _createRuntimeTestKernel({
  required String id,
  required String identity,
}) {
  final VideoKernelDescriptor descriptor = VideoKernelDescriptor(
    id: id,
    displayName: id,
    supportedPlatforms: const <UnifiedVideoPlatform>{
      UnifiedVideoPlatform.android,
    },
    supportedSourceTypes: const <VideoSourceType>{VideoSourceType.network},
  );
  return RegisteredVideoKernel(
    descriptor: descriptor,
    create: () => _RuntimeTestVideoKernelAdapter(
      descriptor: descriptor,
      identity: identity,
    ),
  );
}

Future<void> _expectInaccurateSeekRollsBack({
  required UnifiedVideoController Function({
    List<RegisteredVideoKernel>? kernels,
    KernelPreference preference,
    UnifiedVideoPlatform platform,
    VideoKernelRuntimeCoordinator? runtimeCoordinator,
    Duration? stateRefreshInterval,
  })
  controller,
  required VideoSource Function() source,
  required Duration offset,
}) async {
  const VideoKernelDescriptor inaccurateDescriptor = VideoKernelDescriptor(
    id: 'inaccurate-seek',
    displayName: '不准确 seek 测试内核',
    supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
    supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
  );
  late _InaccurateSeekVideoKernelAdapter inaccurateAdapter;
  final UnifiedVideoController player = controller(
    kernels: <RegisteredVideoKernel>[
      createFakeVideoKernel(id: 'stable'),
      RegisteredVideoKernel(
        descriptor: inaccurateDescriptor,
        create: () => inaccurateAdapter = _InaccurateSeekVideoKernelAdapter(
          inaccurateDescriptor,
          offset,
        ),
      ),
    ],
    preference: KernelPreference.exact('stable'),
    stateRefreshInterval: null,
  );
  addTearDown(player.dispose);

  await player.open(source());
  await player.seek(const Duration(minutes: 3));

  await expectLater(
    player.switchKernel(inaccurateDescriptor.id),
    throwsA(isA<KernelSwitchException>()),
  );

  expect(inaccurateAdapter.seekAttempts, 6);
  expect(player.value.activeKernelId, 'stable');
  expect(player.value.position, const Duration(minutes: 3));
}

class _LoggingVideoKernelAdapter extends FakeVideoKernelAdapter {
  _LoggingVideoKernelAdapter(VideoKernelDescriptor descriptor, this._log)
    : super(descriptor: descriptor);

  final List<String> _log;

  @override
  Future<void> activateRuntime() async {
    _log.add('${descriptor.id}.runtime.acquire');
  }

  @override
  Future<void> deactivateRuntime() async {
    _log.add('${descriptor.id}.runtime.release');
  }

  @override
  Future<void> initialize() async {
    _log.add('${descriptor.id}.initialize');
    await super.initialize();
  }

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    _log.add('${descriptor.id}.open');
    return super.open(source, state);
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    _log.add('${descriptor.id}.snapshot');
    return super.snapshot(state);
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    _log.add('${descriptor.id}.seek');
    return super.seek(position, state);
  }

  @override
  Future<UnifiedVideoState> setSpeed(
    double speed,
    UnifiedVideoState state,
  ) async {
    _log.add('${descriptor.id}.speed');
    return super.setSpeed(speed, state);
  }

  @override
  Future<UnifiedVideoState> setFit(
    UnifiedVideoFit fit,
    UnifiedVideoState state,
  ) async {
    _log.add('${descriptor.id}.fit');
    return super.setFit(fit, state);
  }

  @override
  Future<UnifiedVideoState> setVolume(
    double volume,
    UnifiedVideoState state,
  ) async {
    _log.add('${descriptor.id}.volume');
    return super.setVolume(volume, state);
  }

  @override
  Future<void> dispose() async {
    _log.add('${descriptor.id}.dispose');
    await super.dispose();
  }
}
