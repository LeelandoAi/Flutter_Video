# Leelando Video 可插拔播放器内核设计

## 背景

`leelando_video 0.1.0` 已经通过 `VideoKernelRegistry` 支持运行时选择 Erika、MediaKit、FVP 和 Flutter 官方 Video Player，但根包仍直接依赖全部播放器 SDK。业务即使只注册一个内核，其依赖图和最终平台产物仍会包含其他内核，因此当前实现只完成了运行时选择，没有完成构建期可插拔。

本次改造目标是让业务同时获得两层能力：

1. 通过依赖声明决定应用最终内置哪些播放器内核。
2. 在同一个 `UnifiedVideoPlayer` View 内注册多个已安装内核，并在播放过程中保留状态切换。

## 目标

- `leelando_video` 核心包不再依赖任何具体播放器 SDK。
- Erika、MediaKit、FVP 和 Flutter 官方 Video Player 分别由独立包提供。
- 业务只添加需要的内核包，未添加的内核不进入依赖图和平台构建产物。
- 四个内核可以同时添加依赖并注册到同一个 `VideoKernelRegistry`。
- 单个播放器 View 可以在四个内核之间切换，并恢复播放地址、进度、播放状态、倍速、缩放和音量。
- 切换过程中外层播放器 View 和控制 UI 保持不变，只替换内部视频 Surface。
- 保留自动选核、指定内核、打开失败回退和自定义第三方内核能力。

## 非目标

- 不保证多个播放器 View 同时分别运行 FVP 和 Flutter 官方内核。FVP 通过全局 `VideoPlayerPlatform` 接管后端，该场景需要改为直接调用 libmdk，不属于本次范围。
- 不提供运行时下载原生播放器二进制。Flutter 平台插件必须在应用构建时确定。
- 不通过反射或字符串动态加载 Dart 包。内核必须由业务显式导入并注册。
- 不在本次改造中扩展字幕、音轨、滤镜或弹幕能力。

## 包结构

仓库采用 Pub workspace 管理多包，所有包版本在首轮拆分时统一为 `0.2.0`。

| 包名 | 职责 | 主要依赖 |
| --- | --- | --- |
| `leelando_video` | 统一模型、控制器、播放器 UI、内核协议、注册表、全屏平台能力 | Flutter SDK |
| `leelando_video_erika` | Erika 适配器与工厂 | `leelando_video`、`erika_flutter` |
| `leelando_video_media_kit` | MediaKit 适配器与工厂 | `leelando_video`、`media_kit`、`media_kit_video`、`media_kit_libs_video` |
| `leelando_video_fvp` | FVP/libmdk 适配器、平台接管与恢复 | `leelando_video`、`fvp`、`video_player` |
| `leelando_video_video_player` | Flutter 官方 Video Player 适配器 | `leelando_video`、`video_player` |
| `leelando_video_all` | 全量依赖和四内核便捷工厂 | 上述四个内核包 |

根目录继续作为 `leelando_video` 核心包，独立内核包放在 `packages/` 下。`example/` 加入 workspace，并通过本地 workspace 解析全部包。

核心包保留 `FakeVideoKernelAdapter`，仅用于测试、自定义内核示例和无平台后端的 UI 验证。它不引入第三方播放器依赖。

## 公共 API

### 显式注册

每个内核包只导出自身描述符、适配器和注册工厂。业务通过依赖和导入决定可用内核：

```dart
import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_erika/leelando_video_erika.dart';
import 'package:leelando_video_media_kit/leelando_video_media_kit.dart';

final controller = UnifiedVideoController(
  registry: VideoKernelRegistry(
    kernels: <RegisteredVideoKernel>[
      createErikaVideoKernel(),
      createMediaKitVideoKernel(),
    ],
  ),
);
```

未添加 `leelando_video_fvp` 和 `leelando_video_video_player` 时，这两个内核及其原生依赖不会进入应用。

### 全量便捷注册

`leelando_video_all` 提供便捷工厂，但不隐藏注册结果：

```dart
final controller = UnifiedVideoController(
  registry: VideoKernelRegistry(
    kernels: createAllVideoKernels(),
  ),
);
```

默认顺序为 Erika、MediaKit、FVP、Flutter 官方 Video Player。业务仍可传入自己的顺序，或直接使用各内核包的工厂。

### 注册表约束

`VideoKernelRegistry` 增加以下行为：

- 重复内核 ID 默认抛出 `DuplicateVideoKernelException`，避免静默覆盖。
- 提供 `registerAll`、`unregister` 和 `contains`，便于业务构建内核集合。
- 保持注册顺序，用于自动选择和运行时回退。
- 注册表只保存工厂，不提前创建或初始化未使用内核。

第三方仍可直接实现 `VideoKernelAdapter` 并注册，不需要修改核心包。

## 内核生命周期

为支持 FVP 与官方 Video Player 在单 View 中切换，内核生命周期分为两个层次：

1. 适配器实例生命周期：创建、初始化、打开、播放、释放。
2. 进程级后端生命周期：激活当前内核需要的全局平台实现，并在离开时恢复。

`VideoKernelAdapter` 增加默认可空的运行时协调信息和切换钩子：

```dart
abstract class VideoKernelAdapter {
  String? get exclusiveRuntimeGroup => null;

  Future<void> activateRuntime() async {}

  Future<void> deactivateRuntime() async {}
}
```

FVP 与 Flutter 官方适配器都声明 `video-player-platform` 运行时组。单个控制器切换时严格按顺序释放和激活，避免旧控制器的纹理 ID 被发送给新平台实现。

FVP 激活时调用 `fvp.registerWith()`。FVP 释放完成后，通过传入不包含当前平台的 `platforms` 配置触发 FVP 自带的前实现恢复逻辑。Flutter 官方适配器随后使用恢复后的官方 `VideoPlayerPlatform` 创建控制器。

核心控制器使用进程级协调器串行化运行时组切换。如果另一个播放器仍占用同组且后端不同，则返回明确的 `KernelRuntimeConflictException`，而不是产生无画面、错纹理或错误释放。

## 单 View 切核事务

`UnifiedVideoController.switchKernel` 改为完整事务，流程如下：

1. 锁定当前控制器的切核操作，拒绝重入。
2. 从旧适配器获取最新快照。
3. 保存播放源、位置、播放/暂停状态、倍速、缩放、音量和全屏状态。
4. 将生命周期切换为 `switchingKernel`，播放器 UI 显示 Loading，控制栏继续复用。
5. 停止状态刷新定时器。
6. 释放旧适配器的视频控制器和 Surface。
7. 释放旧内核的进程级运行时占用。
8. 创建目标适配器并激活其运行时。
9. 初始化目标适配器，使用原播放源和保存位置打开。
10. 恢复倍速、缩放和音量。
11. 如果切换前正在播放，则恢复播放；否则保持暂停。
12. 恢复状态刷新并更新 `activeKernelId`。

外层 `UnifiedVideoPlayer`、全屏 Overlay 和控制 UI 不重新创建。内部 Surface 使用稳定宿主和短时交叉淡入，避免切核时出现页面级闪烁。

切换过程中所有命令进入同一个串行命令队列。进度拖动、播放、暂停或再次切核不会与释放/打开过程并发执行。

## 失败与回滚

目标内核初始化或打开失败时：

1. 释放失败的目标适配器和运行时占用。
2. 尝试重新激活原内核并打开原播放源。
3. 恢复保存的播放状态。
4. 回滚成功时继续使用原内核，并通过 `lastKernelSwitchError` 暴露目标内核失败信息。
5. 回滚也失败时进入 `failed`，保留源、位置和诊断信息供用户重试或选择其他内核。

`switchKernel` 返回的 Future 在目标切换失败时抛出 `KernelSwitchException`。异常包含来源内核、目标内核、目标错误、回滚结果和保存位置。

自动打开回退仍遵循 `KernelPreference`。手动切核只尝试用户指定的目标内核，不自动跳到第三个内核。

## 状态模型

`UnifiedVideoLifecycle` 增加 `switchingKernel`。`UnifiedVideoState` 增加：

- `targetKernelId`：切换期间显示目标内核。
- `lastKernelSwitchError`：回滚成功后保留失败诊断，不强制进入失败页。
- `volume`：统一保存并跨内核恢复音量。

切换成功后清空 `targetKernelId` 和旧切核错误。播放器设置菜单只展示注册表中存在且支持当前平台与源类型的内核。

## 向后兼容与迁移

该拆分会将原 `lee_video` 包迁移为 `leelando_video`，并移除核心入口中四个具体内核工厂的导出，因此发布为 `0.2.0`。原 `lee_video 0.1.x` 用户迁移方式：

1. 保留 `leelando_video` 依赖并升级到 `^0.2.0`。
2. 为实际使用的内核添加对应独立包。
3. 修改具体内核工厂的 import，注册代码结构保持不变。

核心控制器、播放器 View、模型和 `VideoKernelRegistry` 的主要调用形式保持不变。

## Demo

Demo 使用 `leelando_video_all` 验证四内核均已注册，并保留现有 GSY 场景页面。内核设置菜单从 `controller.availableKernels` 读取内容，不再硬编码名称。

重点验证：

- 播放中依次切换 Erika、MediaKit、FVP、官方内核，进度误差不超过 1 秒。
- 暂停状态切换后仍保持暂停。
- 倍速、缩放和音量在切换后保持。
- 全屏中切换内核不退出全屏，不重建外层播放器 View。
- FVP 切到官方后，实际平台实现已恢复为官方实现。
- 目标内核失败时回滚原内核并继续播放。
- 未添加某内核包的最小示例，其依赖图和平台插件列表不包含该内核。

## 测试策略

### 核心包

- 注册、批量注册、注销、重复 ID 和顺序测试。
- 自定义内核无需核心修改即可接入的契约测试。
- 切核状态保存、命令串行、成功切换、失败回滚和回滚失败测试。
- 运行时组占用和冲突诊断测试。
- 单 Surface 宿主、Loading、全屏保持和控制菜单过滤 Widget 测试。

### 内核包

- 每个工厂的描述符、平台和源类型测试。
- 适配器打开、播放、暂停、跳转、倍速、缩放、音量和释放契约测试。
- FVP 激活、释放、恢复官方平台实现的专项测试。
- MediaKit 和 Erika 的进度恢复测试。

### 集成构建

- 最小核心包示例构建。
- 每个独立内核包分别执行 Android、iOS、macOS、Windows 可用平台构建。
- `leelando_video_all` Demo 执行四内核切换场景。
- 每个包执行 `dart pub publish --dry-run`，要求零警告。

## 发布顺序

多包版本统一为 `0.2.0`，按依赖从底层到上层发布：

1. `leelando_video 0.2.0`
2. `leelando_video_erika 0.2.0`
3. `leelando_video_media_kit 0.2.0`
4. `leelando_video_fvp 0.2.0`
5. `leelando_video_video_player 0.2.0`
6. `leelando_video_all 0.2.0`

发布每个上层包前等待 pub.dev 完成下层包索引。仓库后续为每个包配置独立标签，例如 `leelando_video_fvp-v0.2.0`，以便启用 pub.dev 官方 GitHub Actions 自动发布。

## 验收标准

- 核心 `leelando_video` 的依赖图中不存在 Erika、MediaKit、FVP 或 `video_player`。
- 业务只依赖一个内核包时，其他内核不出现在 `flutter pub deps` 和平台插件清单中。
- 四个内核可同时注册，并在单个播放器 View 中逐个切换。
- 播放中切核后进度误差不超过 1 秒，播放/暂停、倍速、缩放、音量和全屏状态保持。
- FVP 与官方 Video Player 可以在单个 View 中双向切换，且底层实现与 UI 显示一致。
- 切换失败可回滚，所有失败都有结构化诊断，不产生未处理异常。
- 核心、各内核包、Demo 的分析、测试和目标平台构建通过。
- 六个包的 pub.dev dry-run 均为零警告。
