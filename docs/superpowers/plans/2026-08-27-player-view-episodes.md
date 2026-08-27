# Player View Episodes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `UnifiedVideoPlayer` to match the approved phone and desktop UI exactly, and add an externally supplied episode list that the player opens directly.

**Architecture:** Keep fullscreen ownership and playback orchestration in `unified_video_player.dart`, add `VideoEpisode` to the public model layer, and split the current oversized View into focused internal widgets for metrics, controls, episode panels, settings, and state feedback. Episode selection remains View-owned: it opens `VideoEpisode.source`, updates local selection only after success, and notifies the host.

**Tech Stack:** Flutter 3.44+, Dart 3.12.2, Material widgets, `LayoutBuilder`, `MediaQuery`, `flutter_test`, existing fake video kernel.

**Spec:** `docs/superpowers/specs/2026-08-27-player-view-implementation-design.md`

## Global Constraints

- The approved visual source is `docs/design/player-view/liquid-glass-player-ui.html`; do not improvise a different layout.
- The primary control row has no visible background, card, pill, blur, or glass.
- Bottom visual gaps are `1` for compact mobile embed, `2` for desktop embed, and `MediaQuery.viewPadding.bottom + 0` for fullscreen.
- Every action has at least a `44 × 44` logical-pixel hit target; expand hit targets upward rather than increasing the visible bottom gap.
- Episode picker is visible only when `episodes.isNotEmpty && (fullscreen || mobileLandscape || desktopWide)`.
- Liquid Glass is limited to episode, speed, and settings overlays.
- Existing callers that omit `episodes` retain `onPrevious`, `onNext`, and `onSwitchContent` behavior.
- Do not initialize or import `flutter_autosize_screen` inside this package; use logical design values, local `LayoutBuilder` constraints, and host-provided `MediaQuery`.
- Preserve Android, iOS, Windows, and macOS fullscreen semantics and reuse the same player surface across fullscreen transitions.
- Use TDD: every behavior change starts with a failing focused test.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/src/models.dart` | Public `VideoEpisode` immutable model. |
| `lib/src/widgets/unified_video_player.dart` | Public widget API, fullscreen portal, active episode state, controller coordination. |
| `lib/src/widgets/player_view/player_view_tokens.dart` | View modes, responsive metrics, colors, spacing, radii, motion durations. |
| `lib/src/widgets/player_view/player_controls.dart` | Title, progress, transparent bottom control row, transport and context actions. |
| `lib/src/widgets/player_view/player_episode_panel.dart` | Responsive episode side panel / popover and continuous episode list. |
| `lib/src/widgets/player_view/player_settings_panel.dart` | Speed popover and grouped settings overlay. |
| `lib/src/widgets/player_view/player_state_overlay.dart` | Opening, buffering, paused, failed, ended feedback. |
| `test/video_episode_test.dart` | `VideoEpisode` model contract. |
| `test/widget_test.dart` | Episode behavior, responsive visibility, control structure, overlays, fullscreen regression. |
| `example/lib/main.dart` | Real episode-list integration. |
| `README.md` | Public API and autosize host integration documentation. |

---

### Task 1: Add the public `VideoEpisode` model

**Files:**
- Create: `test/video_episode_test.dart`
- Modify: `lib/src/models.dart`

**Interfaces:**
- Consumes: existing `VideoSource`, `VideoMetadata`.
- Produces: `const VideoEpisode({required String id, required String title, required VideoSource source, String? subtitle, Duration? duration, Map<String,Object?> extra})`.

- [ ] **Step 1: Write the failing model test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:leelando_video/leelando_video.dart';

void main() {
  test('VideoEpisode 保留选集身份、名称和完整播放源', () {
    final VideoSource source = VideoSource.network(
      'https://example.com/e08.m3u8',
      headers: const <String, String>{'Authorization': 'Bearer token'},
      metadata: const VideoMetadata(episodeTitle: '雾港'),
    );
    final VideoEpisode episode = VideoEpisode(
      id: 'episode-8',
      title: '第 8 集',
      subtitle: '雾港',
      duration: const Duration(minutes: 48, seconds: 6),
      source: source,
      extra: const <String, Object?>{'season': 1},
    );

    expect(episode.id, 'episode-8');
    expect(episode.title, '第 8 集');
    expect(episode.subtitle, '雾港');
    expect(episode.duration, const Duration(minutes: 48, seconds: 6));
    expect(episode.source, same(source));
    expect(episode.source.headers['Authorization'], 'Bearer token');
    expect(episode.extra['season'], 1);
  });
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/video_episode_test.dart`

Expected: compilation fails because `VideoEpisode` is undefined.

- [ ] **Step 3: Add the minimal immutable model**

Append after `VideoMetadata` in `lib/src/models.dart`:

```dart
class VideoEpisode {
  const VideoEpisode({
    required this.id,
    required this.title,
    required this.source,
    this.subtitle,
    this.duration,
    this.extra = const <String, Object?>{},
  });

  final String id;
  final String title;
  final VideoSource source;
  final String? subtitle;
  final Duration? duration;
  final Map<String, Object?> extra;
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `flutter test test/video_episode_test.dart`

Expected: one passing test.

- [ ] **Step 5: Format and commit**

Run: `dart format lib/src/models.dart test/video_episode_test.dart`

```bash
git add lib/src/models.dart test/video_episode_test.dart
git commit -m "feat: add video episode model"
```

---

### Task 2: Add episode state and internal previous/next navigation

**Files:**
- Modify: `lib/src/widgets/unified_video_player.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `VideoEpisode` from Task 1 and `UnifiedVideoController.open(VideoSource)`.
- Produces: `UnifiedVideoPlayer.episodes`, `initialEpisodeId`, `onEpisodeChanged`; private `_openEpisode(VideoEpisode)` and `_syncActiveEpisodeFromSource()`.

- [ ] **Step 1: Extend the test pump helper**

Add parameters to `pumpPlayer`:

```dart
List<VideoEpisode> episodes = const <VideoEpisode>[],
String? initialEpisodeId,
ValueChanged<VideoEpisode>? onEpisodeChanged,
Size viewSize = const Size(800, 600),
```

Before pumping the widget, set `tester.view.physicalSize = viewSize` and `devicePixelRatio = 1`, with teardown resets. Pass the three episode parameters into `UnifiedVideoPlayer`.

Add one shared fixture below the pump helpers and use it in later tasks:

```dart
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
```

- [ ] **Step 2: Write failing navigation and compatibility tests**

```dart
testWidgets('传入选集后上一集和下一集由播放器直接打开', (tester) async {
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
    onEpisodeChanged: (episode) => changed.add(episode.id),
    onNext: () => legacyNextCalls += 1,
  );

  await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
  await tester.pumpAndSettle();

  expect(controller.value.source?.uri, episodes[2].source.uri);
  expect(changed, <String>['e3']);
  expect(legacyNextCalls, 0);
});

testWidgets('首集上一集和末集下一集禁用且不回退旧回调', (tester) async {
  int previousCalls = 0;
  await pumpPlayer(
    tester,
    episodes: _testEpisodes(),
    initialEpisodeId: 'e1',
    onPrevious: () => previousCalls += 1,
  );
  await tester.tap(find.byKey(const ValueKey<String>('previous-episode')));
  await tester.pump();
  expect(previousCalls, 0);

  int nextCalls = 0;
  await pumpPlayer(
    tester,
    episodes: _testEpisodes(),
    initialEpisodeId: 'e3',
    onNext: () => nextCalls += 1,
  );
  await tester.tap(find.byKey(const ValueKey<String>('next-episode')));
  await tester.pump();
  expect(nextCalls, 0);
});

testWidgets('未传选集时上一集仍调用旧回调', (tester) async {
  int calls = 0;
  await pumpPlayer(tester, onPrevious: () => calls++);

  await tester.tap(find.byKey(const ValueKey<String>('previous-episode')));
  await tester.pump();

  expect(calls, 1);
});

testWidgets('重复选集 ID 在建立播放器时失败', (tester) async {
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

  await expectLater(
    pumpPlayer(tester, episodes: episodes),
    throwsA(isA<FlutterError>()),
  );
});

testWidgets('initialEpisodeId 只建立高亮且不会自动打开播放源', (tester) async {
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
      home: UnifiedVideoPlayer(
        controller: controller,
        episodes: _testEpisodes(),
        initialEpisodeId: 'e2',
      ),
    ),
  );

  expect(adapter.openCount, 0);
  expect(controller.value.source, isNull);
});
```

Add this reusable adapter at the end of `test/widget_test.dart`:

```dart
class _CountingOpenVideoKernelAdapter extends FakeVideoKernelAdapter {
  _CountingOpenVideoKernelAdapter(VideoKernelDescriptor descriptor)
      : super(descriptor: descriptor);

  int openCount = 0;

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) {
    openCount += 1;
    return super.open(source, state);
  }
}
```

- [ ] **Step 3: Run focused tests and verify RED**

Run: `flutter test test/widget_test.dart --plain-name "传入选集后上一集和下一集由播放器直接打开"`

Expected: compilation fails because the widget has no episode parameters.

- [ ] **Step 4: Add public parameters and validation**

Add to `UnifiedVideoPlayer`:

```dart
this.episodes = const <VideoEpisode>[],
this.initialEpisodeId,
this.onEpisodeChanged,

final List<VideoEpisode> episodes;
final String? initialEpisodeId;
final ValueChanged<VideoEpisode>? onEpisodeChanged;
```

Add `_validateEpisodes` in state initialization and `didUpdateWidget`. Throw `FlutterError` when an ID is empty or repeated:

```dart
void _validateEpisodes(List<VideoEpisode> episodes) {
  final Set<String> ids = <String>{};
  for (final VideoEpisode episode in episodes) {
    if (episode.id.trim().isEmpty || !ids.add(episode.id)) {
      throw FlutterError('VideoEpisode.id 必须非空且在同一列表中唯一。');
    }
  }
}
```

- [ ] **Step 5: Implement active episode resolution**

Add state fields:

```dart
String? _activeEpisodeId;
bool _openingEpisode = false;
```

Resolve initial ID from `initialEpisodeId`, then match `controller.value.source` by `type` and `uri`. Re-run matching when controller source or `episodes` changes.

- [ ] **Step 6: Implement one episode-opening path**

```dart
Future<void> _openEpisode(VideoEpisode episode) async {
  if (_openingEpisode || episode.id == _activeEpisodeId) return;
  _openingEpisode = true;
  try {
    await widget.controller.open(episode.source);
    if (!mounted) return;
    setState(() => _activeEpisodeId = episode.id);
    widget.onEpisodeChanged?.call(episode);
    _scheduleAutoHideIfNeeded();
  } finally {
    _openingEpisode = false;
  }
}
```

Use `_openEpisode` for internal previous and next. When there is no resolvable list index, invoke the existing callbacks.

- [ ] **Step 7: Run focused tests and existing transport tests**

Run: `flutter test test/widget_test.dart --plain-name "传入选集后上一集和下一集由播放器直接打开"`

Run: `flutter test test/widget_test.dart --plain-name "未传选集时上一集仍调用旧回调"`

Run: `flutter test test/widget_test.dart --plain-name "首集上一集和末集下一集禁用且不回退旧回调"`

Run: `flutter test test/widget_test.dart --plain-name "initialEpisodeId 只建立高亮且不会自动打开播放源"`

Run: `flutter test test/widget_test.dart --plain-name "未提供上一集和下一集回调时按钮不可点击"`

Expected: all pass.

- [ ] **Step 8: Format and commit**

Run: `dart format lib/src/widgets/unified_video_player.dart test/widget_test.dart`

```bash
git add lib/src/widgets/unified_video_player.dart test/widget_test.dart
git commit -m "feat: add player episode navigation"
```

---

### Task 3: Build responsive metrics and the transparent control row

**Files:**
- Create: `lib/src/widgets/player_view/player_view_tokens.dart`
- Create: `lib/src/widgets/player_view/player_controls.dart`
- Modify: `lib/src/widgets/unified_video_player.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Produces: `PlayerViewMode`, `PlayerViewMetrics.resolve(...)`, `PlayerControls`.
- Consumes: controller state, transport callbacks, episode availability, fullscreen callback.

- [ ] **Step 1: Write failing responsive and structure tests**

```dart
testWidgets('竖屏嵌入隐藏选集且主控没有可见背景', (tester) async {
  await pumpPlayer(
    tester,
    episodes: _testEpisodes(),
    initialEpisodeId: 'e1',
    viewSize: const Size(393, 852),
  );

  expect(find.byKey(const ValueKey<String>('episode-picker')), findsNothing);
  final Finder controls = find.byKey(const ValueKey<String>('primary-controls-row'));
  expect(controls, findsOneWidget);
  expect(
    find.descendant(of: controls, matching: find.byType(DecoratedBox)),
    findsNothing,
  );
});

testWidgets('桌面宽布局显示选集并保持 44 像素热区', (tester) async {
  await pumpPlayer(
    tester,
    episodes: _testEpisodes(),
    initialEpisodeId: 'e1',
    platform: UnifiedVideoPlatform.windows,
    viewSize: const Size(1280, 720),
  );

  expect(find.byKey(const ValueKey<String>('episode-picker')), findsOneWidget);
  expect(tester.getSize(find.byKey(const ValueKey<String>('play-pause'))).height,
      greaterThanOrEqualTo(44));
});

testWidgets('嵌入主控行严格使用移动 1 和桌面 2 的底距', (tester) async {
  await pumpPlayer(tester, viewSize: const Size(393, 852));
  final double mobileBottom = tester
      .getBottomRight(find.byKey(const ValueKey<String>('player-frame')))
      .dy;
  final double mobileControlsBottom = tester
      .getBottomRight(find.byKey(const ValueKey<String>('primary-controls-row')))
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
      .getBottomRight(find.byKey(const ValueKey<String>('primary-controls-row')))
      .dy;
  expect(desktopBottom - desktopControlsBottom, 2);
});
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `flutter test test/widget_test.dart --plain-name "竖屏嵌入隐藏选集且主控没有可见背景"`

Expected: missing `primary-controls-row` and incorrect episode visibility.

- [ ] **Step 3: Implement responsive metrics**

In `player_view_tokens.dart` define:

```dart
enum PlayerViewMode { compact, expanded, wide }

class PlayerViewMetrics {
  const PlayerViewMetrics({
    required this.mode,
    required this.horizontalPadding,
    required this.bottomPadding,
    required this.progressHeight,
    required this.iconSize,
    required this.primaryIconSize,
  });

  final PlayerViewMode mode;
  final double horizontalPadding;
  final double bottomPadding;
  final double progressHeight;
  final double iconSize;
  final double primaryIconSize;

  bool get showEpisodePicker => mode != PlayerViewMode.compact;
  bool get showMore => mode != PlayerViewMode.compact;
}
```

`resolve` uses platform, fullscreen, orientation, local width, and `viewPadding.bottom` with exact values from the visual spec.

- [ ] **Step 4: Implement `PlayerControls` without a row background**

Constructor contract:

```dart
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.state,
    required this.metrics,
    required this.hasEpisodes,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onOpenEpisodes,
    required this.onToggleDanmaku,
    required this.onOpenSpeed,
    required this.onOpenMore,
    required this.onToggleFullscreen,
    required this.onSeekStart,
    required this.onSeek,
    required this.onSeekEnd,
  });
}
```

Build the bottom area as `Padding → Column(time row, Slider, Row)`; the keyed `Row` itself must not be wrapped by `Material`, `DecoratedBox`, or a colored `Container`. Use transparent `SizedBox.square(dimension: 44)` hit areas.

- [ ] **Step 5: Replace old duplicated top, center, and bottom controls**

Remove `_CenterTransportLayer`, the horizontal `_ControlTextButton` strip, and the yellow menu selection treatment. Wire `PlayerControls` into the existing controls `AnimatedOpacity` while preserving keys:

- `previous-episode`
- `play-pause`
- `next-episode`
- `video-progress`
- `speed-menu`
- `fullscreen`
- `player-controls-overlay`

- [ ] **Step 6: Run responsive, overflow, auto-hide, and fullscreen tests**

Run: `flutter test test/widget_test.dart --plain-name "竖屏嵌入隐藏选集且主控没有可见背景"`

Run: `flutter test test/widget_test.dart --plain-name "桌面宽布局显示选集并保持 44 像素热区"`

Run: `flutter test test/widget_test.dart --plain-name "窄屏播放器控制栏不会横向溢出"`

Run: `flutter test test/widget_test.dart --plain-name "3 秒无触摸操作时控件自动隐藏，轻点播放器后重新显示"`

Run: `flutter test test/widget_test.dart --plain-name "全屏切换复用同一个播放器 Surface，不创建第二套播放器 View"`

Expected: all pass with no overflow exceptions.

- [ ] **Step 7: Format and commit**

Run: `dart format lib/src/widgets/player_view lib/src/widgets/unified_video_player.dart test/widget_test.dart`

```bash
git add lib/src/widgets/player_view/player_view_tokens.dart lib/src/widgets/player_view/player_controls.dart lib/src/widgets/unified_video_player.dart test/widget_test.dart
git commit -m "feat: rebuild responsive player controls"
```

---

### Task 4: Implement the Liquid Glass episode panel

**Files:**
- Create: `lib/src/widgets/player_view/player_episode_panel.dart`
- Modify: `lib/src/widgets/unified_video_player.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `List<VideoEpisode>`, active episode ID, `PlayerViewMetrics`, `_openEpisode`.
- Produces: `PlayerEpisodePanel` and stable keys `episode-panel`, `episode-option-<id>`, `episode-option-<id>-selected`.

- [ ] **Step 1: Write failing episode-panel tests**

```dart
testWidgets('选集面板显示外部名称并点击后直接播放', (tester) async {
  final List<VideoEpisode> episodes = _testEpisodes();
  final List<String> changed = <String>[];
  final UnifiedVideoController controller = await pumpPlayer(
    tester,
    episodes: episodes,
    initialEpisodeId: 'e1',
    onEpisodeChanged: (episode) => changed.add(episode.id),
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
});

testWidgets('选集打开失败不改变高亮且不通知外部', (tester) async {
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
  final List<VideoEpisode> episodes = _testEpisodes();
  final List<String> changed = <String>[];
  await controller.open(episodes.first.source);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UnifiedVideoPlayer(
          controller: controller,
          episodes: episodes,
          initialEpisodeId: 'e1',
          onEpisodeChanged: (episode) => changed.add(episode.id),
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
});

testWidgets('外部直接换源后选集高亮同步到匹配条目', (tester) async {
  final List<VideoEpisode> episodes = _testEpisodes();
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

testWidgets('选集列表替换 ID 后按当前播放源重新匹配', (tester) async {
  final List<VideoEpisode> episodes = _testEpisodes();
  final UnifiedVideoController controller = await pumpPlayer(
    tester,
    episodes: episodes,
    initialEpisodeId: 'e2',
    platform: UnifiedVideoPlatform.windows,
    viewSize: const Size(1280, 720),
  );
  await controller.open(episodes[1].source);

  final List<VideoEpisode> updated = <VideoEpisode>[
    episodes.first,
    VideoEpisode(
      id: 'e2-renamed',
      title: '第 2 集（新 ID）',
      source: episodes[1].source,
    ),
    episodes.last,
  ];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UnifiedVideoPlayer(
          controller: controller,
          episodes: updated,
          initialEpisodeId: 'e2',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('episode-picker')));
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey<String>('episode-option-e2-renamed-selected')),
    findsOneWidget,
  );
});
```

Add this test adapter at the end of `test/widget_test.dart`:

```dart
class _SelectiveFailVideoKernelAdapter extends FakeVideoKernelAdapter {
  _SelectiveFailVideoKernelAdapter(VideoKernelDescriptor descriptor)
      : super(descriptor: descriptor);

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) {
    if (source.uri.path.endsWith('e2.mp4')) {
      throw StateError('模拟选集打开失败');
    }
    return super.open(source, state);
  }
}
```

- [ ] **Step 2: Run the success test and verify RED**

Run: `flutter test test/widget_test.dart --plain-name "选集面板显示外部名称并点击后直接播放"`

Expected: `episode-picker` has no implemented panel.

- [ ] **Step 3: Build `PlayerEpisodePanel`**

Constructor:

```dart
class PlayerEpisodePanel extends StatelessWidget {
  const PlayerEpisodePanel({
    super.key,
    required this.episodes,
    required this.activeEpisodeId,
    required this.mode,
    required this.openingEpisodeId,
    required this.onSelected,
    required this.onClose,
  });
}
```

Use one rounded translucent panel and adjacent rows separated by `Divider(height: 1, color: Colors.white.withValues(alpha: 0.10))`. Do not use per-row Cards or Chips. Current row uses blue text plus a check icon.

- [ ] **Step 4: Add interruptible panel transitions**

Keep `_episodePanelVisible` in the player View. Render the panel in the same player `Stack`:

- Expanded: right edge, width `min(360, maxWidth * 0.58)`, full height.
- Wide: right `14`, bottom `52`, width `320`, max height `420`.
- Enter `400 ms` with `Curves.easeOutQuart`; exit the same path in `260 ms`.
- Do not block tapping close or exiting fullscreen during the transition.

- [ ] **Step 5: Wire selection to `_openEpisode`**

Track `String? _openingEpisodeId`. Close the panel only after a successful open. On error, leave the panel available and preserve the previous active ID.

- [ ] **Step 6: Run episode tests**

Run: `flutter test test/widget_test.dart --plain-name "选集面板显示外部名称并点击后直接播放"`

Run: `flutter test test/widget_test.dart --plain-name "选集打开失败不改变高亮且不通知外部"`

Run: `flutter test test/widget_test.dart --plain-name "传入选集后上一集和下一集由播放器直接打开"`

Run: `flutter test test/widget_test.dart --plain-name "外部直接换源后选集高亮同步到匹配条目"`

Run: `flutter test test/widget_test.dart --plain-name "选集列表替换 ID 后按当前播放源重新匹配"`

Expected: all pass.

- [ ] **Step 7: Format and commit**

Run: `dart format lib/src/widgets/player_view/player_episode_panel.dart lib/src/widgets/unified_video_player.dart test/widget_test.dart`

```bash
git add lib/src/widgets/player_view/player_episode_panel.dart lib/src/widgets/unified_video_player.dart test/widget_test.dart
git commit -m "feat: add responsive episode picker"
```

---

### Task 5: Rebuild speed, settings, and state overlays

**Files:**
- Create: `lib/src/widgets/player_view/player_settings_panel.dart`
- Create: `lib/src/widgets/player_view/player_state_overlay.dart`
- Modify: `lib/src/widgets/unified_video_player.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: controller, `UnifiedVideoState`, compatible kernels, fit/speed presets, local mirror/rotation/night/danmaku state.
- Produces: `PlayerSpeedPanel`, `PlayerSettingsPanel`, `PlayerStateOverlay`.

- [ ] **Step 1: Write failing grouped-settings and state tests**

```dart
testWidgets('更多设置使用连续分组行而不是 Chip 网格', (tester) async {
  await pumpPlayer(
    tester,
    platform: UnifiedVideoPlatform.windows,
    viewSize: const Size(1280, 720),
  );

  await tester.tap(find.byKey(const ValueKey<String>('settings-menu')));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey<String>('settings-group-playback')), findsOneWidget);
  expect(find.byKey(const ValueKey<String>('settings-chip-grid')), findsNothing);
  expect(find.byKey(const ValueKey<String>('fit-option-cover')), findsOneWidget);
  expect(find.byKey(const ValueKey<String>('kernel-option-fake')), findsOneWidget);
});

testWidgets('暂停状态显示中心反馈且贴底主控保持可用', (tester) async {
  final UnifiedVideoController controller = await pumpPlayer(tester);
  await controller.pause();
  await tester.pump();

  expect(find.byKey(const ValueKey<String>('paused-state-indicator')), findsOneWidget);
  expect(find.byKey(const ValueKey<String>('play-pause')), findsOneWidget);
});

testWidgets('无内置选集时更多设置保留旧换源回调', (tester) async {
  int calls = 0;
  await pumpPlayer(
    tester,
    onSwitchContent: () => calls += 1,
    platform: UnifiedVideoPlatform.windows,
    viewSize: const Size(1280, 720),
  );

  await tester.tap(find.byKey(const ValueKey<String>('settings-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('change-source')));
  await tester.pumpAndSettle();

  expect(calls, 1);
});
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `flutter test test/widget_test.dart --plain-name "更多设置使用连续分组行而不是 Chip 网格"`

Expected: grouped settings key is missing.

- [ ] **Step 3: Implement speed and settings overlays**

Use one continuous dark glass surface with hairline dividers. Preserve these option keys:

- `speed-option-<speed>`
- `fit-option-<fit.name>`
- `kernel-option-<kernel.id>`
- `danmaku-toggle`
- `mirror-toggle`
- `rotation-left`
- `rotation-right`

Use blue selected text/checks instead of `0xFFFFD700`. Close the speed panel after applying speed; keep settings open for toggles and close only through explicit close or scrim.

When `episodes` is empty and legacy `onSwitchContent` is non-null, expose a `change-source` row in the More panel and invoke that callback. When `episodes` is non-empty, do not invoke `onSwitchContent`; the episode entry opens `PlayerEpisodePanel`.

- [ ] **Step 4: Implement state overlay component**

Move lifecycle rendering to `PlayerStateOverlay` and add stable keys:

- `video-loading-indicator`
- `paused-state-indicator`
- `video-error-message`
- `ended-state-indicator`

Opening and buffering use a white `CircularProgressIndicator(strokeWidth: 2.5)`. Failure exposes “重试”. Ended exposes replay and next episode when available.

- [ ] **Step 5: Preserve compatible-kernel and rollback behavior**

Feed `controller.compatibleKernels` into settings. Do not catch and erase kernel-switch diagnostics; keep the existing non-fatal message for `lastKernelSwitchError`.

- [ ] **Step 6: Run settings and state regression tests**

Run: `flutter test test/widget_test.dart --plain-name "更多设置使用连续分组行而不是 Chip 网格"`

Run: `flutter test test/widget_test.dart --plain-name "暂停状态显示中心反馈且贴底主控保持可用"`

Run: `flutter test test/widget_test.dart --plain-name "无内置选集时更多设置保留旧换源回调"`

Run: `flutter test test/widget_test.dart --plain-name "桌面菜单和移动设置仅显示兼容当前播放源的内核"`

Run: `flutter test test/widget_test.dart --plain-name "失败状态显示错误和重试按钮"`

Run: `flutter test test/widget_test.dart --plain-name "切换到失败内核后保留原播放画面和生命周期并提示错误"`

Expected: all pass.

- [ ] **Step 7: Format and commit**

Run: `dart format lib/src/widgets/player_view lib/src/widgets/unified_video_player.dart test/widget_test.dart`

```bash
git add lib/src/widgets/player_view/player_settings_panel.dart lib/src/widgets/player_view/player_state_overlay.dart lib/src/widgets/unified_video_player.dart test/widget_test.dart
git commit -m "feat: restyle player overlays and states"
```

---

### Task 6: Integrate the example, document autosize usage, and verify the package

**Files:**
- Modify: `example/lib/main.dart`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: completed `VideoEpisode` and `UnifiedVideoPlayer` APIs.
- Produces: runnable episode-list example and public migration documentation.

- [ ] **Step 1: Add a complete example episode list**

Map existing playback scenarios into episodes:

```dart
List<VideoEpisode> get _episodes => _sources.indexed.map((entry) {
  final PlaybackScenario scenario = entry.$2;
  return VideoEpisode(
    id: 'scenario-${entry.$1}',
    title: scenario.source.metadata.episodeTitle ?? scenario.title,
    subtitle: scenario.title,
    source: scenario.source,
  );
}).toList(growable: false);
```

Pass `episodes`, `initialEpisodeId`, and `onEpisodeChanged` to the main player. In the callback, update `_sourceIndex` only; do not call `_openSource` a second time.

- [ ] **Step 2: Add a widget test for the example contract**

```dart
testWidgets('选集成功回调不会造成第二次打开', (tester) async {
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
  final List<VideoEpisode> episodes = _testEpisodes();
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
```

- [ ] **Step 3: Document public episode usage**

Add to `README.md`:

```dart
final episodes = <VideoEpisode>[
  VideoEpisode(
    id: 'e01',
    title: '第 1 集',
    subtitle: '启程',
    source: VideoSource.network('https://example.com/e01.m3u8'),
  ),
];

UnifiedVideoPlayer(
  controller: controller,
  episodes: episodes,
  initialEpisodeId: 'e01',
  onEpisodeChanged: (episode) {
    debugPrint('正在播放 ${episode.title}');
  },
)
```

Document that `flutter_autosize_screen` is initialized by the host application with mobile short-edge standard `393` or desktop short-edge standard `720`; the player itself does not import or initialize the package.

- [ ] **Step 4: Update the changelog**

Under the current version, record the new `VideoEpisode` API, internal episode navigation, responsive Liquid Glass View, and backward compatibility for legacy callbacks.

- [ ] **Step 5: Run formatting**

Run: `dart format lib test example/lib/main.dart`

Expected: exit code `0` and no formatting diff after a second run.

- [ ] **Step 6: Run focused and full verification**

Run: `flutter test test/video_episode_test.dart test/widget_test.dart`

Run: `flutter test`

Run: `flutter analyze`

Expected: all tests pass and analyzer exits with no issues.

- [ ] **Step 7: Verify no accidental production dependency was added**

Run: `git diff -- pubspec.yaml pubspec.lock`

Expected: no `flutter_autosize_screen` dependency diff in the core package; host integration remains documentation-only.

- [ ] **Step 8: Commit documentation and example**

```bash
git add example/lib/main.dart README.md CHANGELOG.md test/widget_test.dart
git commit -m "docs: demonstrate episode player view"
```

- [ ] **Step 9: Produce the final verification report**

Record:

- exact test count and failures (`0` required),
- analyzer result,
- files changed,
- visual requirements checked against `docs/design/player-view/assets/player-view-design-board.png`,
- any consciously waived platform-only behavior.
