import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';

void main() {
  test('相同运行时身份共享租约并在最后释放时停用', () async {
    final coordinator = VideoKernelRuntimeCoordinator();
    final first = _RuntimeFakeAdapter(group: 'platform', identity: 'fvp');
    final second = _RuntimeFakeAdapter(group: 'platform', identity: 'fvp');

    final firstLease = await coordinator.acquire(first);
    final secondLease = await coordinator.acquire(second);
    expect(first.activationCount, 1);
    expect(second.activationCount, 0);

    await firstLease.release();
    expect(first.deactivationCount, 0);
    await secondLease.release();
    expect(first.deactivationCount, 1);
  });

  test('无运行时组的租约按实例激活和停用', () async {
    final coordinator = VideoKernelRuntimeCoordinator();
    final adapter = _RuntimeFakeAdapter(group: null, identity: 'isolated');

    final lease = await coordinator.acquire(adapter);
    expect(adapter.activationCount, 1);

    await lease.release();
    expect(adapter.deactivationCount, 1);
  });

  test('同组不同运行时身份并发占用时抛出冲突', () async {
    final coordinator = VideoKernelRuntimeCoordinator();
    final fvp = _RuntimeFakeAdapter(group: 'platform', identity: 'fvp');
    final official = _RuntimeFakeAdapter(
      group: 'platform',
      identity: 'official',
    );
    final lease = await coordinator.acquire(fvp);
    addTearDown(lease.release);

    await expectLater(
      coordinator.acquire(official),
      throwsA(isA<KernelRuntimeConflictException>()),
    );
  });

  test('运行时冲突异常提供中文诊断消息', () {
    expect(
      const KernelRuntimeConflictException(
        group: 'platform',
        activeIdentity: 'fvp',
        requestedIdentity: 'official',
      ).toString(),
      'KernelRuntimeConflictException(运行时组 platform 已被身份 fvp 占用，无法请求身份 official)',
    );
  });

  test('Fake 内核将音量限制在零到一之间', () async {
    final adapter = FakeVideoKernelAdapter();
    addTearDown(adapter.dispose);
    await adapter.initialize();

    final UnifiedVideoState muted = await adapter.setVolume(
      -0.5,
      const UnifiedVideoState(),
    );
    final UnifiedVideoState fullVolume = await adapter.setVolume(1.5, muted);

    expect(muted.volume, 0.0);
    expect(fullVolume.volume, 1.0);
  });

  test('切换状态保留并可以清除目标内核和失败诊断', () {
    const UnifiedVideoError error = UnifiedVideoError(
      code: UnifiedVideoErrorCode.kernelSwitchFailed,
      message: '目标内核打开失败',
    );
    const UnifiedVideoState switching = UnifiedVideoState(
      lifecycle: UnifiedVideoLifecycle.switchingKernel,
      volume: 0.4,
      targetKernelId: 'target',
      lastKernelSwitchError: error,
    );

    final UnifiedVideoState cleared = switching.copyWith(
      clearTargetKernelId: true,
      clearLastKernelSwitchError: true,
    );

    expect(switching.volume, 0.4);
    expect(cleared.targetKernelId, isNull);
    expect(cleared.lastKernelSwitchError, isNull);
  });
}

class _RuntimeFakeAdapter extends FakeVideoKernelAdapter {
  _RuntimeFakeAdapter({required this.group, required this.identity})
    : super(
        descriptor: VideoKernelDescriptor(
          id: identity,
          displayName: identity,
          supportedPlatforms: UnifiedVideoPlatform.values.toSet(),
          supportedSourceTypes: VideoSourceType.values.toSet(),
        ),
      );

  final String? group;
  final String identity;
  int activationCount = 0;
  int deactivationCount = 0;

  @override
  String? get runtimeGroup => group;

  @override
  String get runtimeIdentity => identity;

  @override
  Future<void> activateRuntime() async {
    activationCount += 1;
  }

  @override
  Future<void> deactivateRuntime() async {
    deactivationCount += 1;
  }
}
