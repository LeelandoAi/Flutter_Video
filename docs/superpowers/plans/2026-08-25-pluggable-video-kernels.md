# Lee Video 可插拔播放器内核实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `lee_video` 改造成不依赖具体播放引擎的核心包，并提供四个可独立安装、可在单个播放器 View 中保留状态切换的内核包。

**Architecture:** 根包保留统一 API、控制器、播放器 UI 和全屏平台插件，具体适配器迁移到 `packages/` 下的独立包。核心通过运行时租约协调 FVP 与官方 `VideoPlayerPlatform`，控制器使用串行事务完成快照、释放、激活、打开、恢复和失败回滚。

**Tech Stack:** Flutter 3.44、Dart 3.12、Pub workspace、`video_player`、FVP/libmdk、MediaKit/libmpv、Erika、Flutter Test。

**Spec:** `docs/superpowers/specs/2026-08-25-pluggable-video-kernels-design.md`

## Global Constraints

- 核心包名保持 `lee_video`，首个拆分版本为 `0.2.0`。
- 独立包名固定为 `lee_video_erika`、`lee_video_media_kit`、`lee_video_fvp`、`lee_video_video_player`、`lee_video_all`，首版均为 `0.2.0`。
- 核心 `lee_video` 的依赖中只能保留 Flutter SDK，不得依赖 Erika、MediaKit、FVP 或 `video_player`。
- 四个内核必须能同时注册到一个 `VideoKernelRegistry`，单个播放器 View 必须能逐个切换。
- FVP 与官方内核通过进程级 `video-player-platform` 运行时组串行切换；不支持两个 View 同时分别运行这两个后端。
- 切核必须保持播放源、进度、播放/暂停、倍速、缩放、音量和全屏状态。
- 所有用户文档、变更记录、错误消息和 Demo 文案使用中文。
- 手动切核失败必须回滚原内核，不得产生未处理异步异常。
- 所有包发布前执行 `dart pub publish --dry-run`，目标为零警告。

## File Map

### Core `lee_video`

- `lib/src/kernel.dart`: 内核协议、描述符、注册表和重复 ID 异常。
- `lib/src/kernel_runtime.dart`: 进程级运行时租约和冲突协调。
- `lib/src/models.dart`: 切核生命周期、音量和结构化错误状态。
- `lib/src/controller.dart`: 打开、命令串行、事务切核和失败回滚。
- `lib/src/adapters/fake_video_kernel.dart`: 无第三方依赖的测试内核。
- `lib/src/widgets/unified_video_player.dart`: 稳定 Surface 宿主、切核 Loading 和可用内核菜单。
- `lib/lee_video.dart`: 仅导出核心 API 和 Fake 适配器。
- `test/kernel_registry_test.dart`: 注册表和自定义内核契约测试。
- `test/kernel_runtime_test.dart`: 运行时租约测试。
- `test/controller_test.dart`: 切核事务和回滚测试。
- `test/widget_test.dart`: 单 View、Loading 和菜单过滤测试。

### Optional kernels

- `packages/lee_video_video_player/`: Flutter 官方 Video Player 适配器。
- `packages/lee_video_fvp/`: FVP 适配器及全局平台接管/恢复。
- `packages/lee_video_erika/`: Erika 适配器。
- `packages/lee_video_media_kit/`: MediaKit 适配器。
- `packages/lee_video_all/`: 四内核导出和便捷工厂。

### Workspace and demo

- `pubspec.yaml`: 核心版本、workspace 成员和最小依赖。
- `pubspec.lock`: workspace 唯一锁文件，纳入 Git，但由 `.pubignore` 排除发布包。
- `.gitignore`: 不再忽略 workspace 根锁文件。
- `.pubignore`: 排除 workspace 锁文件、子包和平台构建产物。
- `example/pubspec.yaml`: workspace Demo，依赖 `lee_video_all`。
- `example/lib/main.dart`: 使用全量工厂注册四个内核。
- `README.md`: 核心包、可选内核和迁移说明。
- `CHANGELOG.md`: `0.2.0` 破坏性变更。

---

### Task 1: 核心内核协议、注册表和运行时租约

**Files:**
- Create: `lib/src/kernel_runtime.dart`
- Create: `test/kernel_registry_test.dart`
- Create: `test/kernel_runtime_test.dart`
- Modify: `lib/src/kernel.dart`
- Modify: `lib/src/models.dart`
- Modify: `lib/src/adapters/fake_video_kernel.dart`
- Modify: `lib/lee_video.dart`

**Interfaces:**
- Consumes: Existing `VideoKernelAdapter`, `RegisteredVideoKernel`, `VideoKernelRegistry`, `UnifiedVideoState`.
- Produces: `VideoKernelRuntimeCoordinator.acquire(VideoKernelAdapter)`, `VideoKernelRuntimeLease.release()`, registry mutation APIs, volume and switching state fields.

- [ ] **Step 1: Write failing registry tests**

Create `test/kernel_registry_test.dart` with focused tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';

void main() {
  test('注册表保留顺序并支持批量注册、查询和注销', () {
    final registry = VideoKernelRegistry();
    registry.registerAll(<RegisteredVideoKernel>[
      createFakeVideoKernel(id: 'first', displayName: '第一内核'),
      createFakeVideoKernel(id: 'second', displayName: '第二内核'),
    ]);

    expect(registry.descriptors.map((item) => item.id), <String>['first', 'second']);
    expect(registry.contains('first'), isTrue);
    expect(registry.unregister('first')?.descriptor.id, 'first');
    expect(registry.contains('first'), isFalse);
  });

  test('重复内核 ID 抛出明确异常而不是静默覆盖', () {
    final registry = VideoKernelRegistry(
      kernels: <RegisteredVideoKernel>[createFakeVideoKernel(id: 'same')],
    );

    expect(
      () => registry.register(createFakeVideoKernel(id: 'same')),
      throwsA(isA<DuplicateVideoKernelException>()),
    );
  });
}
```

- [ ] **Step 2: Run registry tests and verify RED**

Run: `flutter test test/kernel_registry_test.dart`

Expected: compilation fails because `registerAll`, `contains`, `unregister`, `DuplicateVideoKernelException` and configurable Fake factory arguments do not exist.

- [ ] **Step 3: Implement registry behavior and configurable Fake factory**

In `lib/src/kernel.dart`, add:

```dart
class DuplicateVideoKernelException implements Exception {
  const DuplicateVideoKernelException(this.kernelId);
  final String kernelId;

  @override
  String toString() => 'DuplicateVideoKernelException(kernelId: $kernelId)';
}
```

Change `register` to reject duplicate IDs and add exact APIs:

```dart
bool contains(String id) => _kernels.containsKey(id);

void register(RegisteredVideoKernel kernel) {
  final String id = kernel.descriptor.id;
  if (_kernels.containsKey(id)) {
    throw DuplicateVideoKernelException(id);
  }
  _kernels[id] = kernel;
}

void registerAll(Iterable<RegisteredVideoKernel> kernels) {
  for (final RegisteredVideoKernel kernel in kernels) {
    register(kernel);
  }
}

RegisteredVideoKernel? unregister(String id) => _kernels.remove(id);
```

Change the Fake factory to this exact signature without importing another package:

```dart
RegisteredVideoKernel createFakeVideoKernel({
  String id = 'fake',
  String displayName = 'Fake 测试内核',
  Duration duration = const Duration(minutes: 42),
  Set<UnifiedVideoPlatform>? supportedPlatforms,
  Set<VideoSourceType>? supportedSourceTypes,
})
```

Build a descriptor from the supplied values and retain the current all-platform/all-source defaults when the optional sets are null.

- [ ] **Step 4: Run registry tests and verify GREEN**

Run: `flutter test test/kernel_registry_test.dart`

Expected: all registry tests pass.

- [ ] **Step 5: Write failing runtime lease tests**

Create `test/kernel_runtime_test.dart` with a `_RuntimeFakeAdapter` that counts activation/deactivation:

```dart
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

test('同组不同运行时身份并发占用时抛出冲突', () async {
  final coordinator = VideoKernelRuntimeCoordinator();
  final fvp = _RuntimeFakeAdapter(group: 'platform', identity: 'fvp');
  final official = _RuntimeFakeAdapter(group: 'platform', identity: 'official');
  final lease = await coordinator.acquire(fvp);
  addTearDown(lease.release);

  await expectLater(
    coordinator.acquire(official),
    throwsA(isA<KernelRuntimeConflictException>()),
  );
});
```

- [ ] **Step 6: Run runtime tests and verify RED**

Run: `flutter test test/kernel_runtime_test.dart`

Expected: compilation fails because runtime coordinator interfaces do not exist.

- [ ] **Step 7: Implement runtime hooks and coordinator**

Add concrete default hooks to `VideoKernelAdapter`:

```dart
String? get runtimeGroup => null;
String get runtimeIdentity => descriptor.id;
Future<void> activateRuntime() async {}
Future<void> deactivateRuntime() async {}

Future<UnifiedVideoState> setVolume(
  double volume,
  UnifiedVideoState state,
) async => state.copyWith(volume: volume);
```

Create `lib/src/kernel_runtime.dart` with:

```dart
class KernelRuntimeConflictException implements Exception {
  const KernelRuntimeConflictException({
    required this.group,
    required this.activeIdentity,
    required this.requestedIdentity,
  });

  final String group;
  final String activeIdentity;
  final String requestedIdentity;
}

class VideoKernelRuntimeCoordinator {
  VideoKernelRuntimeCoordinator();
  static final VideoKernelRuntimeCoordinator instance =
      VideoKernelRuntimeCoordinator();

  Future<VideoKernelRuntimeLease> acquire(VideoKernelAdapter adapter);
}

abstract interface class VideoKernelRuntimeLease {
  Future<void> release();
}
```

For adapters without a group, call `activateRuntime` immediately and `deactivateRuntime` on release. For grouped adapters, share a slot only when `runtimeIdentity` matches; keep a reference count and call the first adapter's `deactivateRuntime` exactly once when the final lease is released.

- [ ] **Step 8: Extend state model and Fake adapter volume support**

Add `switchingKernel` to `UnifiedVideoLifecycle`; add `kernelSwitchFailed` and `runtimeConflict` to `UnifiedVideoErrorCode`. Add these fields to `UnifiedVideoState` and `copyWith`:

```dart
final double volume; // default 1.0
final String? targetKernelId;
final UnifiedVideoError? lastKernelSwitchError;
```

Provide `clearTargetKernelId` and `clearLastKernelSwitchError` flags. Override `setVolume` in Fake adapter and clamp to `0.0 ... 1.0`.

- [ ] **Step 9: Run core tests and analyzer**

Run: `flutter test test/kernel_registry_test.dart test/kernel_runtime_test.dart test/controller_test.dart`

Run: `flutter analyze`

Expected: tests pass and analyzer reports no issues after existing test adapters inherit the concrete default volume/runtime methods.

- [ ] **Step 10: Commit core contracts**

```bash
git add lib/src/kernel.dart lib/src/kernel_runtime.dart lib/src/models.dart lib/src/adapters/fake_video_kernel.dart lib/lee_video.dart test/kernel_registry_test.dart test/kernel_runtime_test.dart
git commit -m "feat(core): add pluggable kernel runtime contracts"
```

### Task 2: 事务化切核、状态恢复和失败回滚

**Files:**
- Modify: `lib/src/controller.dart`
- Modify: `test/controller_test.dart`

**Interfaces:**
- Consumes: `VideoKernelRuntimeCoordinator`, `VideoKernelRuntimeLease`, `UnifiedVideoLifecycle.switchingKernel`, adapter runtime hooks and `setVolume`.
- Produces: serialized `switchKernel`, `setVolume`, `KernelSwitchException`, successful rollback diagnostics.

- [ ] **Step 1: Add failing state-preservation test**

Extend `test/controller_test.dart`:

```dart
test('切换内核保持进度、暂停状态、倍速、缩放、音量和全屏', () async {
  final player = controller(kernels: <RegisteredVideoKernel>[
    createFakeVideoKernel(id: 'first'),
    createFakeVideoKernel(id: 'second'),
  ], preference: KernelPreference.exact('first'));
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
```

- [ ] **Step 2: Add failing lifecycle-order test**

Use logging adapters and an injected coordinator to assert this exact order:

```dart
expect(log, <String>[
  'first.snapshot',
  'first.dispose',
  'first.runtime.release',
  'second.runtime.acquire',
  'second.initialize',
  'second.open',
  'second.seek',
  'second.speed',
  'second.fit',
  'second.volume',
]);
```

- [ ] **Step 3: Add failing rollback test**

```dart
test('目标内核失败后回滚原内核并继续播放', () async {
  final player = controller(kernels: <RegisteredVideoKernel>[
    createFakeVideoKernel(id: 'stable'),
    RegisteredVideoKernel(
      descriptor: failingDescriptor,
      create: () => _FailingOpenVideoKernelAdapter(failingDescriptor),
    ),
  ], preference: KernelPreference.exact('stable'));
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
```

- [ ] **Step 4: Run controller tests and verify RED**

Run: `flutter test test/controller_test.dart`

Expected: tests fail because volume, runtime ordering, switching lifecycle and rollback are not implemented.

- [ ] **Step 5: Implement serialized operation queue**

In `UnifiedVideoController`, add:

```dart
Future<void> _operationTail = Future<void>.value();
bool _operationRunning = false;

Future<T> _enqueue<T>(Future<T> Function() operation) {
  final Completer<T> completer = Completer<T>();
  _operationTail = _operationTail.then((_) async {
    _operationRunning = true;
    try {
      completer.complete(await operation());
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _operationRunning = false;
    }
  });
  return completer.future;
}
```

Route public `open`, `play`, `pause`, `seek`, `stop`, `setSpeed`, `setFit`, `setVolume`, `switchSource` and `switchKernel` through `_enqueue`. Private transaction helpers must call private non-queued command methods to avoid self-deadlock.

- [ ] **Step 6: Integrate runtime leases into adapter opening**

Add constructor injection and fields:

```dart
UnifiedVideoController({
  required this.registry,
  VideoKernelRuntimeCoordinator? runtimeCoordinator,
  // existing arguments
}) : _runtimeCoordinator =
       runtimeCoordinator ?? VideoKernelRuntimeCoordinator.instance;

final VideoKernelRuntimeCoordinator _runtimeCoordinator;
VideoKernelRuntimeLease? _runtimeLease;
```

Before `initialize`, acquire the adapter lease. On candidate failure, release the candidate lease. Before replacing an active adapter, snapshot first, dispose the adapter, then release its lease.

- [ ] **Step 7: Implement transactional switch and rollback**

Add a private immutable snapshot:

```dart
class _KernelSwitchSnapshot {
  const _KernelSwitchSnapshot({
    required this.source,
    required this.kernelId,
    required this.position,
    required this.wasPlaying,
    required this.speed,
    required this.fit,
    required this.volume,
    required this.fullscreen,
  });
  // exact final fields matching constructor
}
```

Implement `switchKernel` as one queued operation. Set `switchingKernel` and `targetKernelId`, release the old adapter/runtime, open only the requested kernel, restore state, and clear the target. On failure, dispose the target, reopen `snapshot.kernelId`, restore state, set `lastKernelSwitchError`, and throw:

```dart
class KernelSwitchException implements Exception {
  const KernelSwitchException({
    required this.fromKernelId,
    required this.toKernelId,
    required this.position,
    required this.targetError,
    required this.rollbackSucceeded,
    this.rollbackError,
  });
  // exact final fields matching constructor
}
```

Manual switch must not use runtime fallback. `preference` after rollback must remain the caller's prior preference rather than being permanently replaced by `KernelPreference.exact`.

- [ ] **Step 8: Implement volume command and refresh safety**

Add `Future<void> setVolume(double volume)` with `0.0 ... 1.0` validation. During queued operations, `_refreshAdapterState` returns without taking a snapshot. Keep fullscreen state from the saved controller state instead of reopening platform fullscreen.

- [ ] **Step 9: Run controller tests and verify GREEN**

Run: `flutter test test/controller_test.dart`

Expected: existing controller tests and new transaction tests pass, including rollback.

- [ ] **Step 10: Commit controller transaction**

```bash
git add lib/src/controller.dart test/controller_test.dart
git commit -m "feat(core): make kernel switching transactional"
```

### Task 3: 单 View Surface、切核 Loading 和内核菜单

**Files:**
- Modify: `lib/src/widgets/unified_video_player.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `switchingKernel`, `targetKernelId`, `lastKernelSwitchError`, `VideoKernelRegistry` descriptors.
- Produces: stable player host, target-specific Loading, compatible-kernel menu and handled rollback UI.

- [ ] **Step 1: Write failing switching UI test**

Add a delayed target adapter and test:

```dart
testWidgets('切换内核时保持播放器 View 并显示目标内核 Loading', (tester) async {
  final controller = await pumpSwitchablePlayer(tester);
  final Finder playerHost = find.byKey(const ValueKey<String>('video-surface-host'));
  expect(playerHost, findsOneWidget);

  final Future<void> switching = controller.switchKernel('delayed');
  await tester.pump();

  expect(playerHost, findsOneWidget);
  expect(find.byKey(const ValueKey<String>('video-loading-indicator')), findsOneWidget);
  expect(find.text('正在切换到 延迟测试内核'), findsOneWidget);

  completeDelayedOpen();
  await switching;
  await tester.pumpAndSettle();
  expect(playerHost, findsOneWidget);
});
```

- [ ] **Step 2: Write failing menu filtering and rollback UI tests**

Verify the kernel menu omits descriptors that do not support `controller.platform` or the current source type. Change the existing failed-switch Widget test to expect the original kernel surface to remain and a non-blocking switch error message, not the full failed page.

- [ ] **Step 3: Run widget tests and verify RED**

Run: `flutter test test/widget_test.dart`

Expected: switching label, stable host key and compatibility filtering assertions fail.

- [ ] **Step 4: Implement stable Surface host**

Wrap only the adapter surface in:

```dart
KeyedSubtree(
  key: const ValueKey<String>('video-surface-host'),
  child: AnimatedOpacity(
    duration: const Duration(milliseconds: 160),
    opacity: state.lifecycle == UnifiedVideoLifecycle.switchingKernel ? 0 : 1,
    child: controller.buildSurface(context),
  ),
)
```

Keep the outer `UnifiedVideoPlayer`, controls Overlay and fullscreen Overlay keys stable. The Loading layer covers the surface during the 160ms transition.

- [ ] **Step 5: Implement switching Loading and menu filtering**

Resolve the target display name from the registry and show `正在切换到 <displayName>`. Add a controller getter:

```dart
List<VideoKernelDescriptor> get compatibleKernels {
  final VideoSource? source = value.source;
  if (source == null) return availableKernels;
  return availableKernels
      .where((item) => item.supports(platform, source))
      .toList(growable: false);
}
```

Use `compatibleKernels` in desktop popup and mobile settings sheet. Continue wrapping `switchKernel` with `_ignorePlaybackError` so the returned `KernelSwitchException` is represented by controller state rather than an unhandled Flutter error.

- [ ] **Step 6: Run widget and full core tests**

Run: `flutter test test/widget_test.dart`

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 7: Commit player UI behavior**

```bash
git add lib/src/widgets/unified_video_player.dart lib/src/controller.dart test/widget_test.dart
git commit -m "feat(player): keep one view while switching kernels"
```

### Task 4: Pub workspace and Flutter 官方内核包

**Files:**
- Create: `packages/lee_video_video_player/pubspec.yaml`
- Create: `packages/lee_video_video_player/README.md`
- Create: `packages/lee_video_video_player/CHANGELOG.md`
- Create: `packages/lee_video_video_player/LICENSE`
- Create: `packages/lee_video_video_player/lib/lee_video_video_player.dart`
- Create: `packages/lee_video_video_player/lib/src/video_player_kernel_base.dart`
- Create: `packages/lee_video_video_player/lib/src/official_video_player_kernel.dart`
- Create: `packages/lee_video_video_player/test/official_video_player_kernel_test.dart`
- Modify: `pubspec.yaml`
- Modify: `.gitignore`
- Modify: `.pubignore`
- Modify: `lib/lee_video.dart`
- Delete: `lib/src/adapters/video_player_kernel_base.dart`
- Delete: `lib/src/adapters/official_video_player_kernel.dart`
- Delete: `lib/src/adapters/placeholder_kernels.dart`

**Interfaces:**
- Consumes: core `VideoKernelAdapter`, state and registry types.
- Produces: `createOfficialVideoPlayerKernel`, `OfficialVideoPlayerKernelAdapter`, `officialVideoPlayerKernelDescriptor` in an independently installable package.

- [ ] **Step 1: Write package test before moving implementation**

Create the package test importing only public package APIs:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video/lee_video.dart';
import 'package:lee_video_video_player/lee_video_video_player.dart';

void main() {
  test('官方内核工厂声明正确能力和运行时身份', () {
    final kernel = createOfficialVideoPlayerKernel();
    expect(kernel.descriptor.id, 'video-player');
    expect(kernel.descriptor.supportedPlatforms, contains(UnifiedVideoPlatform.ios));
    final adapter = kernel.create();
    expect(adapter.runtimeGroup, 'video-player-platform');
    expect(adapter.runtimeIdentity, 'video-player-official');
  });
}
```

- [ ] **Step 2: Configure Pub workspace and verify package test is RED**

Update root `pubspec.yaml` to `version: 0.2.0`, reduce root dependencies to Flutter SDK, and add:

```yaml
workspace:
  - packages/lee_video_erika
  - packages/lee_video_media_kit
  - packages/lee_video_fvp
  - packages/lee_video_video_player
  - packages/lee_video_all
  - example
```

Add `resolution: workspace` to each member as it is created. Remove `/pubspec.lock` from `.gitignore`. Add these exact root `.pubignore` entries so the core archive cannot absorb monorepo sources:

```text
/pubspec.lock
/packages/
/docs/
/tool/
```

Run: `dart pub get`

Run: `flutter test packages/lee_video_video_player/test/official_video_player_kernel_test.dart`

Expected: test fails because the package implementation has not moved yet.

- [ ] **Step 3: Move the official adapter and add volume support**

Move the base and official adapter into the new package. In the base adapter, implement:

```dart
@override
Future<UnifiedVideoState> setVolume(double volume, UnifiedVideoState state) async {
  final controller = requireController();
  await controller.setVolume(volume);
  return stateFromController(state).copyWith(volume: volume);
}
```

Official adapter runtime fields are:

```dart
@override
String get runtimeGroup => 'video-player-platform';

@override
String get runtimeIdentity => 'video-player-official';
```

Remove all concrete engine exports and placeholder exports from core `lib/lee_video.dart`.

- [ ] **Step 4: Complete package metadata**

Use hosted dependency constraints:

```yaml
name: lee_video_video_player
version: 0.2.0
resolution: workspace
environment:
  sdk: ^3.12.2
  flutter: '>=3.44.0'
dependencies:
  flutter:
    sdk: flutter
  lee_video: ^0.2.0
  video_player: ^2.14.0
```

Copy the root MIT license. README must show installation, import and registration in Chinese. Changelog must document the first `0.2.0` release.

- [ ] **Step 5: Verify official package and core dependency isolation**

Run: `dart pub get`

Run: `flutter test packages/lee_video_video_player/test`

Run: `flutter test`

Run: `dart pub deps | rg 'erika_flutter|media_kit|fvp|video_player'`

Expected: the workspace graph contains optional engines because member packages exist, but `dart pub publish --dry-run` from the root archive lists no concrete adapter files and root `pubspec.yaml` has none of those dependencies.

- [ ] **Step 6: Commit workspace and official package**

```bash
git add pubspec.yaml pubspec.lock .gitignore .pubignore lib packages/lee_video_video_player
git commit -m "feat(packages): extract official video player kernel"
```

### Task 5: FVP 可插拔包和官方平台恢复

**Files:**
- Create: `packages/lee_video_fvp/pubspec.yaml`
- Create: `packages/lee_video_fvp/README.md`
- Create: `packages/lee_video_fvp/CHANGELOG.md`
- Create: `packages/lee_video_fvp/LICENSE`
- Create: `packages/lee_video_fvp/lib/lee_video_fvp.dart`
- Create: `packages/lee_video_fvp/lib/src/fvp_video_kernel.dart`
- Create: `packages/lee_video_fvp/lib/src/fvp_video_player_adapter.dart`
- Create: `packages/lee_video_fvp/test/fvp_runtime_test.dart`
- Delete: `lib/src/adapters/fvp_video_kernel.dart`

**Interfaces:**
- Consumes: core adapter/runtime APIs and FVP `registerWith` restore behavior.
- Produces: FVP adapter that can share a registry with the official adapter and restores the previous platform when its final runtime lease is released.

- [ ] **Step 1: Write failing FVP runtime restoration test**

Use a token-verified test platform implementation from `video_player_platform_interface`:

```dart
test('FVP 释放运行时后恢复之前的 VideoPlayerPlatform', () async {
  final previous = _TestVideoPlayerPlatform();
  VideoPlayerPlatform.instance = previous;
  final adapter = createFvpVideoKernel().create();

  await adapter.activateRuntime();
  expect(VideoPlayerPlatform.instance, isNot(same(previous)));

  await adapter.deactivateRuntime();
  expect(VideoPlayerPlatform.instance, same(previous));
});
```

- [ ] **Step 2: Add package metadata and verify RED**

Use dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter
  lee_video: ^0.2.0
  fvp: ^0.38.1
  video_player: ^2.14.0
  video_player_platform_interface: ^6.9.0
```

Add `lee_video_video_player: ^0.2.0` under `dev_dependencies` only for the real FVP-to-official handoff test. It must not appear under production `dependencies`.

Run: `dart pub get`

Run: `flutter test packages/lee_video_fvp/test/fvp_runtime_test.dart`

Expected: test fails because FVP runtime hooks are not implemented.

- [ ] **Step 3: Implement independent FVP adapter**

Move the FVP descriptor and factory into the package. Implement its own `VideoPlayerController` wrapper rather than depending on `lee_video_video_player`, so `lee_video_fvp` does not pull the official adapter package into the dependency graph.

Declare:

```dart
@override
String get runtimeGroup => 'video-player-platform';

@override
String get runtimeIdentity => 'video-player-fvp';

@override
Future<void> activateRuntime() async {
  fvp.registerWith();
}

@override
Future<void> deactivateRuntime() async {
  fvp.registerWith(options: <String, Object>{
    'platforms': const <String>[],
  });
}
```

The adapter must dispose its `VideoPlayerController` before `deactivateRuntime` is called. Implement open, snapshot, play, pause, seek, stop, speed, fit, volume and surface using the same unified state mapping as the official adapter.

- [ ] **Step 4: Verify FVP/official sequential handoff**

Add a test using one coordinator:

```dart
final fvpLease = await coordinator.acquire(fvpAdapter);
await fvpLease.release();
final officialLease = await coordinator.acquire(officialAdapter);
expect(VideoPlayerPlatform.instance, same(previous));
await officialLease.release();
```

Run: `flutter test packages/lee_video_fvp/test`

Expected: activation changes the global implementation and release restores the previous implementation.

- [ ] **Step 5: Add Chinese metadata and commit**

Copy MIT license; README documents that FVP and official adapters can be registered together for one-View sequential switching, while different Views cannot concurrently occupy different implementations.

```bash
git add packages/lee_video_fvp lib/src/adapters/fvp_video_kernel.dart pubspec.lock
git commit -m "feat(packages): extract switchable FVP kernel"
```

### Task 6: Erika 与 MediaKit 可插拔包

**Files:**
- Create: `packages/lee_video_erika/pubspec.yaml`
- Create: `packages/lee_video_erika/README.md`
- Create: `packages/lee_video_erika/CHANGELOG.md`
- Create: `packages/lee_video_erika/LICENSE`
- Create: `packages/lee_video_erika/lib/lee_video_erika.dart`
- Create: `packages/lee_video_erika/lib/src/erika_video_kernel.dart`
- Create: `packages/lee_video_erika/test/erika_video_kernel_test.dart`
- Create: `packages/lee_video_media_kit/pubspec.yaml`
- Create: `packages/lee_video_media_kit/README.md`
- Create: `packages/lee_video_media_kit/CHANGELOG.md`
- Create: `packages/lee_video_media_kit/LICENSE`
- Create: `packages/lee_video_media_kit/lib/lee_video_media_kit.dart`
- Create: `packages/lee_video_media_kit/lib/src/media_kit_video_kernel.dart`
- Create: `packages/lee_video_media_kit/test/media_kit_video_kernel_test.dart`
- Delete: `lib/src/adapters/erika_video_kernel.dart`
- Delete: `lib/src/adapters/media_kit_video_kernel.dart`

**Interfaces:**
- Consumes: core adapter/state APIs.
- Produces: independent Erika and MediaKit packages with complete volume and progress restoration support.

- [ ] **Step 1: Write failing factory contract tests**

Each package test imports its public entrypoint and verifies exact descriptor ID, supported platforms/source types, adapter type and no runtime group:

```dart
expect(createErikaVideoKernel().descriptor.id, 'erika');
expect(createErikaVideoKernel().create().runtimeGroup, isNull);
expect(createMediaKitVideoKernel().descriptor.id, 'media-kit');
expect(createMediaKitVideoKernel().create().runtimeGroup, isNull);
```

- [ ] **Step 2: Configure package dependencies and verify RED**

Erika dependencies:

```yaml
lee_video: ^0.2.0
erika_flutter: ^0.1.7
```

MediaKit dependencies:

```yaml
lee_video: ^0.2.0
media_kit: ^1.2.6
media_kit_video: ^2.0.1
media_kit_libs_video: ^1.0.7
```

Run: `dart pub get`

Run: `flutter test packages/lee_video_erika/test packages/lee_video_media_kit/test`

Expected: tests fail before adapters are moved.

- [ ] **Step 3: Move Erika adapter and add volume mapping**

Move the existing Erika implementation without changing native API selection. Implement `setVolume` by calling Erika's volume API and returning `state.copyWith(volume: volume)`. Ensure `open` preserves a non-zero state position or the controller's restore transaction seeks after ready.

- [ ] **Step 4: Move MediaKit adapter and add volume mapping**

Move the existing MediaKit implementation. Implement:

```dart
@override
Future<UnifiedVideoState> setVolume(double volume, UnifiedVideoState state) async {
  await _requirePlayer().setVolume(volume * 100);
  return _stateFromPlayer(state).copyWith(volume: volume);
}
```

Keep `Media(... start: state.position)` and the post-open controller seek so progress restoration works for formats that ignore the start hint.

- [ ] **Step 5: Add Chinese metadata and run tests**

Copy MIT license and create Chinese README/CHANGELOG for both packages.

Run: `flutter test packages/lee_video_erika/test packages/lee_video_media_kit/test`

Run: `flutter analyze`

Expected: package tests pass and core no longer imports engine packages.

- [ ] **Step 6: Commit Erika and MediaKit packages**

```bash
git add packages/lee_video_erika packages/lee_video_media_kit lib pubspec.lock
git commit -m "feat(packages): extract Erika and MediaKit kernels"
```

### Task 7: 全量便捷包和四内核组合契约

**Files:**
- Create: `packages/lee_video_all/pubspec.yaml`
- Create: `packages/lee_video_all/README.md`
- Create: `packages/lee_video_all/CHANGELOG.md`
- Create: `packages/lee_video_all/LICENSE`
- Create: `packages/lee_video_all/lib/lee_video_all.dart`
- Create: `packages/lee_video_all/test/all_kernels_test.dart`

**Interfaces:**
- Consumes: all four optional package factories.
- Produces: `List<RegisteredVideoKernel> createAllVideoKernels()` and re-exports for one-import usage.

- [ ] **Step 1: Write failing all-kernel order test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lee_video_all/lee_video_all.dart';

void main() {
  test('全量工厂按稳定顺序返回四个真实内核', () {
    expect(
      createAllVideoKernels().map((kernel) => kernel.descriptor.id),
      <String>['erika', 'media-kit', 'fvp', 'video-player'],
    );
  });
}
```

- [ ] **Step 2: Add package dependencies and verify RED**

Use `^0.2.0` hosted constraints for core and all four packages. Run:

`flutter test packages/lee_video_all/test/all_kernels_test.dart`

Expected: test fails because entrypoint and factory do not exist.

- [ ] **Step 3: Implement exports and factory**

`lib/lee_video_all.dart` must export core and all optional public entrypoints, then define:

```dart
List<RegisteredVideoKernel> createAllVideoKernels() {
  return <RegisteredVideoKernel>[
    createErikaVideoKernel(),
    createMediaKitVideoKernel(),
    createFvpVideoKernel(),
    createOfficialVideoPlayerKernel(),
  ];
}
```

Return a new fixed-order list per call so registries cannot share mutable list state.

- [ ] **Step 4: Verify package and metadata**

Copy MIT license. README must explain that this package intentionally includes all native engines and direct users should choose independent packages for smaller builds.

Run: `flutter test packages/lee_video_all/test`

Expected: test passes with four unique descriptors.

- [ ] **Step 5: Commit all-kernel package**

```bash
git add packages/lee_video_all pubspec.lock
git commit -m "feat(packages): add all-kernel convenience package"
```

### Task 8: Demo、中文文档和 0.2.0 迁移

**Files:**
- Modify: `example/pubspec.yaml`
- Modify: `example/lib/main.dart`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Create: `example/test/kernel_switch_smoke_test.dart`

**Interfaces:**
- Consumes: `lee_video_all`, transactional controller and compatible menu.
- Produces: four-kernel Demo and public migration documentation.

- [ ] **Step 1: Write failing Demo registry smoke test**

Extract a top-level Demo factory:

```dart
VideoKernelRegistry createDemoKernelRegistry() {
  return VideoKernelRegistry(kernels: createAllVideoKernels());
}
```

Test:

```dart
test('Demo 同时注册四个可切换内核', () {
  expect(
    createDemoKernelRegistry().descriptors.map((item) => item.id),
    <String>['erika', 'media-kit', 'fvp', 'video-player'],
  );
});
```

- [ ] **Step 2: Run Demo test and verify RED**

Run: `flutter test example/test/kernel_switch_smoke_test.dart`

Expected: test fails because Demo still imports concrete factories from core.

- [ ] **Step 3: Migrate Demo to `lee_video_all`**

Update `example/pubspec.yaml`:

```yaml
resolution: workspace
dependencies:
  flutter:
    sdk: flutter
  lee_video: ^0.2.0
  lee_video_all: ^0.2.0
```

Import `package:lee_video_all/lee_video_all.dart`, remove placeholder factories, and use `createAllVideoKernels()`. Keep existing GSY scenario UI and all real playback sources.

- [ ] **Step 4: Update README installation matrix**

Document three paths with complete snippets:

1. Core plus selected kernel packages.
2. Full `lee_video_all` package.
3. Custom adapter implementation.

Include `0.1.x -> 0.2.0` import migration and state that package dependency selection controls final built-in native engines.

- [ ] **Step 5: Update changelog and run docs checks**

Add a `0.2.0` section describing package split, transactional switching, volume restoration, FVP/official sequential handoff and migration. Run:

`rg -n "createErikaKernelPlaceholder|createMediaKitKernelPlaceholder|package:lee_video/.*(erika|fvp|media_kit|official)" README.md example lib test`

Expected: no obsolete placeholder or concrete-core imports remain.

- [ ] **Step 6: Run Demo and full tests**

Run: `flutter test example/test`

Run: `flutter test`

Run: `flutter analyze`

Expected: all tests and analysis pass.

- [ ] **Step 7: Commit Demo and docs**

```bash
git add example README.md CHANGELOG.md pubspec.lock
git commit -m "docs: migrate demo to pluggable kernels"
```

### Task 9: Dependency isolation、平台构建和发布校验

**Files:**
- Create: `tool/verify_kernel_packages.sh`
- Modify: `.pubignore`
- Modify: package `.pubignore` files only when dry-run lists workspace/build artifacts.

**Interfaces:**
- Consumes: completed workspace and all packages.
- Produces: repeatable release gate proving package isolation and platform build health.

- [ ] **Step 1: Create verification script with explicit package list**

Create `tool/verify_kernel_packages.sh`:

```bash
#!/bin/sh
set -eu

PACKAGES=". packages/lee_video_erika packages/lee_video_media_kit packages/lee_video_fvp packages/lee_video_video_player packages/lee_video_all"

flutter analyze
flutter test

for package in $PACKAGES; do
  echo "==> dry-run $package"
  (cd "$package" && PUB_HOSTED_URL=https://pub.dev dart pub publish --dry-run)
done
```

Do not add `--force` or `--skip-validation`. Make the file executable.

- [ ] **Step 2: Verify workspace and package dependency boundaries**

Run: `dart pub workspace list`

Expected: root core, five optional packages and example are listed once.

Run: `sed -n '/^dependencies:/,/^dev_dependencies:/p' pubspec.yaml`

Expected: only Flutter SDK appears in root dependencies.

Run: `rg -n "package:(erika_flutter|media_kit|fvp|video_player)" lib`

Expected: no matches in root `lib/`.

- [ ] **Step 3: Run all package tests separately**

```bash
flutter test
flutter test packages/lee_video_erika/test
flutter test packages/lee_video_media_kit/test
flutter test packages/lee_video_fvp/test
flutter test packages/lee_video_video_player/test
flutter test packages/lee_video_all/test
flutter test example/test
```

Expected: every command exits 0.

- [ ] **Step 4: Build Android and macOS full Demo**

Run from `example/`:

```bash
flutter build apk --debug
flutter build macos --debug
```

Expected: both builds succeed with Erika, MediaKit, FVP and official plugins in the generated registrant.

- [ ] **Step 5: Build iOS device and simulator without signing**

Run from `example/`:

```bash
flutter build ios --debug --no-codesign
flutter build ios --simulator --debug
```

Expected: both builds succeed using the verified local Erika cache; device and simulator slices link successfully.

- [ ] **Step 6: Validate Windows configuration on available tooling**

Run: `flutter build windows --debug` on a Windows host or CI runner.

Expected: generated plugin registrant includes `lee_video`, Erika, FVP and MediaKit dependencies and the build exits 0. If the current macOS host cannot run this command, record it as a Windows CI requirement rather than claiming local verification.

- [ ] **Step 7: Run zero-warning publication dry-runs**

Run: `sh tool/verify_kernel_packages.sh`

Expected: each package reports `Package has 0 warnings.` and archives contain only that package's source, metadata and required platform files.

- [ ] **Step 8: Inspect Git state and final diff**

Run: `git status --short`

Run: `git diff --check 6879ce9..HEAD`

Expected: no uncommitted generated output and no whitespace errors.

- [ ] **Step 9: Commit verification tooling**

```bash
git add tool/verify_kernel_packages.sh .pubignore packages/*/.pubignore
git commit -m "chore: add pluggable kernel release verification"
```

- [ ] **Step 10: Request final code review**

Use `superpowers:requesting-code-review` against the complete branch. Review must specifically inspect runtime lease release, FVP restoration, rollback error paths, package dependency isolation and publication archives. Resolve findings, then rerun Task 9 Steps 2 through 8 before declaring implementation complete.
