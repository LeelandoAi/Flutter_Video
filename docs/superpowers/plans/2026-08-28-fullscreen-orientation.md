# Mobile Fullscreen Orientation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add portrait, landscape, and aspect-ratio-driven fullscreen orientation with an in-fullscreen direction toggle for mobile playback.

**Architecture:** The public widget owns the requested and currently active fullscreen orientation, resolves `auto` from its `aspectRatio`, and passes a concrete direction to the controller/platform boundary. The platform layer converts the direction into `SystemChrome` orientation lists. The player view receives the active direction and uses a dedicated portrait-fullscreen metrics mode and two-row controls without creating another video Surface.

**Tech Stack:** Flutter, Dart, `SystemChrome`, widget tests, `flutter_test` method-channel fakes.

**Spec:** `docs/superpowers/specs/2026-08-28-fullscreen-orientation.md`

## Global Constraints

- Preserve the current landscape behavior by default.
- Android and iOS support both portrait and landscape fullscreen.
- `auto` resolves from `UnifiedVideoPlayer.aspectRatio`, with values below `1` treated as portrait.
- Exiting fullscreen releases the orientation lock and restores system UI.
- Desktop fullscreen behavior and the single-Surface invariant must remain unchanged.

---

### Task 1: Public orientation contract and platform mapping

**Files:**
- Modify: `lib/src/models.dart`
- Modify: `lib/src/fullscreen_platform.dart`
- Modify: `lib/src/controller.dart`
- Test: `test/controller_test.dart`

**Interfaces:**
- Produces: `enum UnifiedVideoFullscreenOrientation { landscape, portrait, auto }`
- Produces: `UnifiedVideoController.enterFullscreen({bool syncPlatform, UnifiedVideoFullscreenOrientation orientation})`
- Produces: `UnifiedVideoController.syncFullscreenPlatform({UnifiedVideoFullscreenOrientation orientation})`

- [x] **Step 1: Write the failing platform-channel tests**

Add tests that record `SystemChrome.setPreferredOrientations` calls and assert the literal platform values for portrait, landscape, and exit restoration.

- [x] **Step 2: Run the controller tests to verify the missing API fails**

Run: `flutter test test/controller_test.dart --plain-name '移动端全屏方向映射到系统方向并在退出时解除锁定'`

Expected: compilation failure because `UnifiedVideoFullscreenOrientation` and orientation arguments do not exist.

- [x] **Step 3: Implement the enum and platform mapping**

Map landscape to `DeviceOrientation.landscapeLeft/right`, portrait to `DeviceOrientation.portraitUp`, and auto to an unlocked list as a defensive fallback. Keep desktop channel behavior unchanged.

- [x] **Step 4: Run the focused controller test**

Run: `flutter test test/controller_test.dart --plain-name '移动端全屏方向映射到系统方向并在退出时解除锁定'`

Expected: PASS.

### Task 2: Widget auto resolution and fullscreen direction toggle

**Files:**
- Modify: `lib/src/widgets/unified_video_player.dart`
- Modify: `lib/src/widgets/player_view/player_controls.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `UnifiedVideoFullscreenOrientation`
- Produces: `UnifiedVideoPlayer.fullscreenOrientation`
- Produces widget key: `fullscreen-orientation-toggle`

- [x] **Step 1: Write failing widget behavior tests**

Add one test proving a 9:16 player with `auto` sends portrait orientation on entry, and one proving the fullscreen direction button sends landscape orientation while fullscreen remains active and the same Surface element is retained.

- [x] **Step 2: Run the focused widget tests to verify failure**

Run: `flutter test test/widget_test.dart --plain-name '短剧 auto 全屏进入竖屏且可切换横屏而不重建 Surface'`

Expected: compilation failure because the widget parameter and direction button do not exist.

- [x] **Step 3: Implement widget state, auto resolution, and direction toggle**

Resolve auto before entering fullscreen, pass the concrete direction to platform sync, expose a mobile-only direction control, and roll back the button state when platform sync fails.

- [x] **Step 4: Run the focused widget tests**

Run: `flutter test test/widget_test.dart --plain-name '短剧 auto 全屏进入竖屏且可切换横屏而不重建 Surface'`

Expected: PASS.

### Task 3: Portrait-fullscreen responsive controls

**Files:**
- Modify: `lib/src/widgets/player_view/player_view_tokens.dart`
- Modify: `lib/src/widgets/player_view/player_controls.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Produces: `PlayerViewMode.portraitFullscreen`
- Consumes: active fullscreen orientation and existing control callbacks.

- [x] **Step 1: Write the failing layout test**

Assert that portrait fullscreen selects `portraitFullscreen`, keeps the episode picker visible, renders playback and utility rows, and produces no overflow exception at 393x852.

- [x] **Step 2: Run the focused layout test to verify failure**

Run: `flutter test test/widget_test.dart --plain-name '竖屏全屏使用双行主控并保留选集入口'`

Expected: failure because the dedicated mode and row keys are absent.

- [x] **Step 3: Implement portrait metrics and two-row controls**

Add portrait fullscreen metrics with mobile padding and split playback/utilities into keyed rows. Preserve normal compact, expanded, and wide output; split only ultra-narrow compact controls when the one-row minimum width is unavailable.

- [x] **Step 4: Run the focused layout test**

Run: `flutter test test/widget_test.dart --plain-name '竖屏全屏使用双行主控并保留选集入口'`

Expected: PASS with no layout exception.

### Task 4: Documentation and release verification

**Files:**
- Modify: `README.md`
- Test: all workspace test targets.

**Interfaces:**
- Documents: fixed portrait, fixed landscape, auto, and the in-fullscreen toggle.

- [x] **Step 1: Add the public usage example**

Document a 9:16 short-drama player using `fullscreenOrientation: UnifiedVideoFullscreenOrientation.auto`.

- [x] **Step 2: Format and run all verification commands**

Run: `dart format lib test`

Run: `flutter test`

Run: `flutter analyze`

Expected: all tests pass and analysis reports no issues.

- [x] **Step 3: Verify mobile builds or runtime behavior**

Run the Example on an available Android or iOS target and confirm portrait entry, in-fullscreen landscape switch, exit restoration, and visible video Surface.
