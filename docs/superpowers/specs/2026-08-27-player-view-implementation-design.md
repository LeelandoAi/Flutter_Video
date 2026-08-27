# 播放器 View 一比一还原与选集 API 实现设计

日期：2026-08-27  
状态：API 方向已确认，等待规格复核后实施  
视觉基准：[Player View UI](../../design/player-view/liquid-glass-player-ui.html)  
视觉标注：[Player View Liquid Glass Design](2026-08-27-player-view-liquid-glass-design.md)

## 1. 目标

将当前 `UnifiedVideoPlayer` 的 View 按已确认的手机端和电脑端 UI 一比一还原，并增加由外部传入的选集列表。

选集列表中的每个条目必须至少包含：

- 稳定选集 ID。
- 选集名称。
- 可直接交给 `UnifiedVideoController.open` 的 `VideoSource`，其中包含播放地址、媒体类型、请求头和元数据。

用户点击选集后，播放器组件直接打开该选集的 `VideoSource`；打开成功后，再通过回调通知外部。

## 2. 公共数据模型

在 `lib/src/models.dart` 增加不可变模型：

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

约束：

- `id` 在同一个播放器实例的 `episodes` 中必须唯一且非空。
- `title` 必须非空，是选集面板的主标题。
- `source` 是真实播放输入；不重复创建 `url` 字段，避免网络、文件、Asset 和 Memory 四种来源被退化成网络 URL。
- `subtitle` 用于剧集副标题或说明，可空。
- `duration` 用于在尚未打开该选集时显示静态时长，可空。
- `extra` 只承载业务扩展，不参与播放器内部判断。

`VideoMetadata.episodeTitle` 继续保留，用于没有 `VideoEpisode` 列表时显示当前媒体标题；它不再承担选集列表必填名称的职责。

## 3. `UnifiedVideoPlayer` 公共参数

新增参数：

```dart
const UnifiedVideoPlayer({
  required UnifiedVideoController controller,
  List<VideoEpisode> episodes = const <VideoEpisode>[],
  String? initialEpisodeId,
  ValueChanged<VideoEpisode>? onEpisodeChanged,
  // 保留现有参数……
});
```

语义：

- `episodes`：外部传入的完整选集列表。空列表表示不启用内置选集能力。
- `initialEpisodeId`：首次建立 View 状态时优先标记的选集；值不存在时忽略并尝试按当前播放源匹配。
- `onEpisodeChanged`：内部成功打开新选集后调用。失败时不调用。

不增加单独的 `episodeUrl` 字段。`VideoEpisode.source.uri` 是播放地址，`source.type`、`source.headers` 和 `source.metadata` 保持完整。

## 4. 当前选集解析

播放器 View 内部维护 `_activeEpisodeId`，初始化顺序如下：

1. `initialEpisodeId` 存在且能在列表中找到。
2. 当前 `controller.value.source` 与某个选集的 `source` 匹配。
3. 都不满足时为 `null`，不在首次 Build 中自动播放第一集。

播放源匹配使用：

- `VideoSource.type` 相同。
- `VideoSource.uri` 相同。
- 不比较 `VideoMetadata`。

当外部直接调用 `controller.open` 切换媒体时，播放器监听状态并重新匹配选集，使面板高亮、上一集和下一集状态保持同步。

当 `episodes` 在 `didUpdateWidget` 中发生变化时：

- 当前 ID 仍存在：保持选择。
- 当前 ID 已移除：按控制器当前播放源重新匹配。
- 仍无法匹配：清空当前 ID，不自动播放。

## 5. 点击选集流程

```text
点击选集
  → 若为当前选集，仅关闭浮层
  → 设置切集中状态，阻止重复点击
  → controller.open(episode.source)
  → 成功：更新 _activeEpisodeId
  → 关闭浮层
  → onEpisodeChanged(episode)
  → 重新启动主控自动隐藏计时
```

失败处理：

- 保留原 `_activeEpisodeId`。
- 不调用 `onEpisodeChanged`。
- 不吞掉控制器状态；失败信息由现有 `UnifiedVideoState.error` 和错误层展示。
- 选集浮层保持可关闭，用户可选择其他选集或进入“更多”切换内核。

组件不得在选集切换过程中锁死返回、退出全屏或关闭浮层。

## 6. 上一集与下一集兼容规则

当 `episodes` 非空且能解析当前选集索引时：

- 上一集和下一集由播放器内部计算目标条目并调用同一个切集流程。
- 到达列表首尾时，相应按钮保留槽位但进入禁用态。
- 不调用旧的 `onPrevious` / `onNext`，避免业务方再次打开同一播放源。

当 `episodes` 为空，或列表中无法解析当前播放源时：

- 继续使用现有 `onPrevious` / `onNext`。
- 回调为空时按钮禁用。

当 `episodes` 非空时，“选集”入口打开内置选集浮层，不调用旧的 `onSwitchContent`。当 `episodes` 为空时，`onSwitchContent` 保留原有兼容行为。

旧参数不在本次删除或弃用，避免破坏现有接入方。

## 7. View 组件边界

现有 `unified_video_player.dart` 已同时承担全屏、状态、主控、菜单和设置，文件过大。实现时按职责拆分私有组件，但不扩大公共 API：

```text
lib/src/widgets/
  unified_video_player.dart
  player_view/
    player_view_tokens.dart
    player_controls.dart
    player_episode_panel.dart
    player_settings_panel.dart
    player_state_overlay.dart
```

职责：

- `unified_video_player.dart`：公开 Widget、全屏 Portal、选集状态与控制器协调。
- `player_view_tokens.dart`：颜色、尺寸、断点、底距和动画常量。
- `player_controls.dart`：顶部标题、进度条、贴底单行主控和响应式显隐。
- `player_episode_panel.dart`：手机横屏侧面板、桌面 Popover 与连续选集列表。
- `player_settings_panel.dart`：倍速、画面、镜像、旋转、夜间和内核设置。
- `player_state_overlay.dart`：打开、缓冲、暂停、失败和结束状态。

这些文件均为包内部实现，不从 `leelando_video.dart` 额外导出。

## 8. 响应式规则

沿用视觉规格：

```text
Compact  = 手机竖屏、非全屏，或局部宽度 < 480
Expanded = 手机横屏或全屏
Wide     = Windows / macOS 且局部宽度 >= 640
```

- Compact：隐藏选集和更多；保留上一集、播放暂停、下一集、弹幕、倍速、全屏。
- Expanded / Wide：显示完整一级控制。
- `showEpisodePicker = episodes.isNotEmpty && (fullscreen || mobileLandscape || desktopWide)`。
- 局部宽度来自 `LayoutBuilder`，方向和安全区来自 `MediaQuery`。
- 不在播放器内部初始化 `flutter_autosize_screen`；该全局责任属于宿主应用。

## 9. 一比一视觉实现要求

### 9.1 主控

- 整行无可见背景。
- 进度条独立位于主控行上方。
- 手机竖屏视觉底距 `1 pt`。
- 桌面嵌入视觉底距 `2 dp`。
- 横屏／全屏额外底距 `0`，仅叠加系统安全区。
- 点击热区至少 `44 × 44`，只向上和左右扩展。
- 激活态使用单一蓝色，不使用当前黄色。

### 9.2 选集、倍速与设置

- 仅浮层使用 Liquid Glass。
- 选集与设置使用一个连续面板和发丝分隔线，不使用 Chip 网格。
- 手机横屏选集为右侧面板；桌面为锚定 Popover。
- 倍速菜单覆盖全部 `unifiedVideoSpeedPresets`。
- 设置入口包含画面比例、镜像、旋转、夜间模式和内核选择。

### 9.3 状态与自动隐藏

- 播放中最后一次交互后 `3 秒`隐藏主控。
- 暂停、失败、结束时保持显示。
- 拖动进度期间不隐藏。
- 上一集、下一集、选集切换和内核切换均重置计时。

## 10. 测试设计

### 10.1 模型测试

- `VideoEpisode` 保留 ID、标题、播放源、可选说明、时长和扩展数据。
- Widget 构造时拒绝重复或空的选集 ID。

### 10.2 选集行为测试

- 传入列表后，横屏／桌面宽布局显示选集入口。
- 手机竖屏嵌入隐藏选集入口。
- 点击选集调用 `controller.open`，打开成功后回调一次正确条目。
- 打开失败不回调，当前高亮不变化。
- 当前选集重复点击不重新打开。
- 外部直接打开列表中的另一个 `VideoSource` 后，高亮同步。
- 列表更新移除当前 ID 后按当前播放源重新匹配。

### 10.3 上一集／下一集测试

- 列表中间条目可以向前和向后切换。
- 首集上一集禁用，末集下一集禁用。
- 有列表时不触发旧回调。
- 无列表时现有 `onPrevious` / `onNext` 测试继续通过。

### 10.4 响应式与视觉结构测试

- Compact / Expanded / Wide 的显隐符合规格。
- 主控根节点没有 Material、DecoratedBox 或 Container 背景。
- 主控热区不小于 `44 × 44`。
- 选集列表是连续面板并有相邻行分隔。
- 设置不再使用旧的三至五列 Chip 网格。
- 进度、时间、全屏、倍速和内核菜单的现有 Key 尽量保留，降低测试迁移成本。

### 10.5 回归验证

- `flutter test` 全部通过。
- `flutter analyze` 无新增问题。
- 示例应用至少保留单视频、列表详情、弹幕、滤镜、模糊背景和进度预览场景。
- Android / iOS / Windows / macOS 的全屏语义不因 View 拆分改变。

## 11. 迁移策略

- 现有只传 `controller` 的调用无需修改。
- 现有 `onPrevious`、`onNext`、`onSwitchContent` 调用继续工作。
- 新业务优先传 `episodes` 和 `onEpisodeChanged`。
- 示例应用增加一组 `VideoEpisode`，展示列表切集和当前集高亮。
- README 增加最小选集接入示例。

## 12. 非目标

- 本次不把选集持久化到控制器状态或本地存储。
- 本次不实现分页加载选集。
- 本次不实现 DRM、付费锁、下载状态或多清晰度线路模型。
- 本次不自动播放列表第一集；初始播放源仍由宿主通过控制器决定。
- 本次不替换 `flutter_autosize_screen` 或修改宿主应用入口。

## 13. 验收标准

- 外部能以 `List<VideoEpisode>` 传入最少包含名称和播放地址的选集。
- 点击选集由播放器直接打开对应播放源，成功后通知外部。
- 上一集、播放暂停、下一集和所有上下文操作按确认 UI 无背景贴底显示。
- 选集只在横屏、全屏或桌面宽布局出现。
- 主控底距、尺寸、安全区和 Liquid Glass 浮层与视觉标注一致。
- 旧版无选集列表的接入方式继续通过测试。
- Flutter 格式化、静态分析和测试全部通过后才可交付。

