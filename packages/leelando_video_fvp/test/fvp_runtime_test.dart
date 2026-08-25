import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_fvp/leelando_video_fvp.dart';
import 'package:leelando_video_video_player/leelando_video_video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  final VideoPlayerPlatform previous = _TestVideoPlayerPlatform();

  setUp(() {
    VideoPlayerPlatform.instance = previous;
  });

  test('FVP 释放运行时后恢复之前的 VideoPlayerPlatform', () {
    fakeAsync((FakeAsync async) {
      final adapter = createFvpVideoKernel().create();

      _complete(async, adapter.activateRuntime());
      expect(VideoPlayerPlatform.instance, isNot(same(previous)));

      _complete(async, adapter.deactivateRuntime());
      expect(VideoPlayerPlatform.instance, same(previous));
    });
  });

  test('FVP 与官方适配器可注册并按同一 View 串行交接', () {
    fakeAsync((FakeAsync async) {
      final registry = VideoKernelRegistry(
        kernels: <RegisteredVideoKernel>[
          createFvpVideoKernel(),
          createOfficialVideoPlayerKernel(),
        ],
      );
      final coordinator = VideoKernelRuntimeCoordinator();
      final fvpAdapter = registry.byId('fvp')!.create();
      final officialAdapter = registry.byId('video-player')!.create();

      final fvpLease = _completeWithValue(
        async,
        coordinator.acquire(fvpAdapter),
      );
      expect(VideoPlayerPlatform.instance, isNot(same(previous)));
      _complete(async, fvpLease.release());
      expect(VideoPlayerPlatform.instance, same(previous));

      final officialLease = _completeWithValue(
        async,
        coordinator.acquire(officialAdapter),
      );
      expect(VideoPlayerPlatform.instance, same(previous));
      _complete(async, officialLease.release());
      expect(VideoPlayerPlatform.instance, same(previous));
    });
  });

  test('同组冲突与引用计数不能绕过 FVP 最终恢复', () {
    fakeAsync((FakeAsync async) {
      final coordinator = VideoKernelRuntimeCoordinator();
      final firstFvp = createFvpVideoKernel().create();
      final secondFvp = createFvpVideoKernel().create();
      final official = createOfficialVideoPlayerKernel().create();

      expect(firstFvp.runtimeGroup, 'video-player-platform');
      expect(firstFvp.runtimeIdentity, 'video-player-fvp');
      expect(official.runtimeGroup, firstFvp.runtimeGroup);

      final firstLease = _completeWithValue(
        async,
        coordinator.acquire(firstFvp),
      );
      final secondLease = _completeWithValue(
        async,
        coordinator.acquire(secondFvp),
      );
      final VideoPlayerPlatform activeFvp = VideoPlayerPlatform.instance;

      _complete(async, firstLease.release());
      expect(VideoPlayerPlatform.instance, same(activeFvp));
      expect(
        _completeWithError(async, coordinator.acquire(official)),
        isA<KernelRuntimeConflictException>(),
      );

      _complete(async, secondLease.release());
      expect(VideoPlayerPlatform.instance, same(previous));
    });
  });
}

class _TestVideoPlayerPlatform extends VideoPlayerPlatform {}

void _complete(FakeAsync async, Future<void> future) {
  Object? failure;
  StackTrace? failureStack;
  var completed = false;
  future.then<void>(
    (_) {
      completed = true;
    },
    onError: (Object error, StackTrace stackTrace) {
      failure = error;
      failureStack = stackTrace;
    },
  );
  async.flushMicrotasks();
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack!);
  }
  expect(completed, isTrue, reason: 'Future 应在当前微任务队列内完成。');
}

T _completeWithValue<T>(FakeAsync async, Future<T> future) {
  Object? failure;
  StackTrace? failureStack;
  T? value;
  var completed = false;
  future.then<void>(
    (T result) {
      value = result;
      completed = true;
    },
    onError: (Object error, StackTrace stackTrace) {
      failure = error;
      failureStack = stackTrace;
    },
  );
  async.flushMicrotasks();
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack!);
  }
  expect(completed, isTrue, reason: 'Future 应在当前微任务队列内完成。');
  return value as T;
}

Object _completeWithError<T>(FakeAsync async, Future<T> future) {
  Object? failure;
  future.then<void>(
    (_) {},
    onError: (Object error, StackTrace _) {
      failure = error;
    },
  );
  async.flushMicrotasks();
  expect(failure, isNotNull, reason: 'Future 应以错误完成。');
  return failure!;
}
