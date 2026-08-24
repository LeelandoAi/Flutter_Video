import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';

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
  }) {
    return UnifiedVideoController(
      registry: VideoKernelRegistry(
        kernels: kernels ?? <RegisteredVideoKernel>[createFakeVideoKernel()],
      ),
      platform: platform,
      preference: preference,
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

  test('注册表按偏好降级选择兼容内核并记录跳过历史', () async {
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        createOfficialVideoPlayerKernelPlaceholder(),
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
        createOfficialVideoPlayerKernelPlaceholder(),
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

  test('Erika 兼容入口返回真实 Erika 适配器', () {
    final RegisteredVideoKernel kernel = createErikaKernelPlaceholder();

    expect(kernel.descriptor.id, 'erika');
    expect(kernel.create(), isA<ErikaVideoKernelAdapter>());
  });

  test('没有兼容内核时返回不支持内核诊断', () async {
    final UnifiedVideoController player = controller(
      kernels: <RegisteredVideoKernel>[
        createOfficialVideoPlayerKernelPlaceholder(),
      ],
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
