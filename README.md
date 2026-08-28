# Leelando Video

一个面向 Android、iOS、Windows、macOS 的统一聚合影视播放器库。当前实现已落地核心 API、内核抽象、默认播放器 UI、fake 测试内核、Media Kit/libmpv 适配器、FVP/libmdk 适配器和官方 Video Player 适配器。

## 安装与内核选择

`leelando_video` 只提供统一控制器、内核协议和播放器 UI，不携带具体播放引擎。应用在 `pubspec.yaml` 中选择的内核包，决定最终产物会内置哪些原生播放引擎；未依赖的包不会被注册，也不会被构建进应用。

### 路径一：核心包加按需内核包

适合控制包体和原生依赖范围的应用。下面示例只安装 Media Kit 与官方 Video Player；可按同样方式加入 `leelando_video_fvp`。

```yaml
dependencies:
  leelando_video: ^0.3.0
  leelando_video_media_kit: ^0.3.0
  leelando_video_video_player: ^0.3.0
```

```dart
import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_media_kit/leelando_video_media_kit.dart';
import 'package:leelando_video_video_player/leelando_video_video_player.dart';

final registry = VideoKernelRegistry(
  kernels: <RegisteredVideoKernel>[
    createMediaKitVideoKernel(),
    createOfficialVideoPlayerKernel(),
  ],
);
```

### 路径二：全量 `leelando_video_all` 包

适合需要一次启用全部官方适配器的示例或应用。`leelando_video_all` 的公共入口同时导出核心 API 和三个内核，并提供稳定顺序的全量工厂函数。

```yaml
dependencies:
  leelando_video_all: ^0.3.0
```

```dart
import 'package:leelando_video_all/leelando_video_all.dart';

final registry = VideoKernelRegistry(kernels: createAllVideoKernels());
```

`createAllVideoKernels()` 固定返回 `media-kit`、`fvp`、`video-player`，便于 Demo 和菜单展示一致的内核顺序。

### 路径三：自定义适配器

自定义原生播放器时，仅依赖核心包并注册自己的 `RegisteredVideoKernel`。下面是协议模板，不是现成播放器：应用需要让 `AppVideoEngine` 的每个方法对接实际 SDK，并将 SDK 回调转换为位置、时长、生命周期、倍速和音量。

```yaml
dependencies:
  leelando_video: ^0.3.0
```

```dart
import 'package:flutter/widgets.dart';
import 'package:leelando_video/leelando_video.dart';

abstract interface class AppVideoEngine {
  UnifiedVideoLifecycle get lifecycle;
  Duration get position;
  Duration get duration;
  double get speed;
  double get volume;

  Future<void> initialize();
  Future<void> open(Uri uri, {required Map<String, String> headers});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  Widget buildSurface(BuildContext context);
  Future<void> dispose();
}

typedef AppVideoEngineFactory = AppVideoEngine Function();

const appVideoKernelDescriptor = VideoKernelDescriptor(
  id: 'app-sdk',
  displayName: '应用 SDK 播放器',
  supportedPlatforms: <UnifiedVideoPlatform>{UnifiedVideoPlatform.android},
  supportedSourceTypes: <VideoSourceType>{VideoSourceType.network},
);

RegisteredVideoKernel createAppVideoKernel(
  AppVideoEngineFactory createEngine,
) {
  return RegisteredVideoKernel(
    descriptor: appVideoKernelDescriptor,
    create: () => AppVideoKernelAdapter(createEngine()),
  );
}

class AppVideoKernelAdapter extends VideoKernelAdapter {
  AppVideoKernelAdapter(this._engine);

  final AppVideoEngine _engine;

  @override
  VideoKernelDescriptor get descriptor => appVideoKernelDescriptor;

  // 若 SDK 占用全局运行时，覆写 runtimeGroup、runtimeIdentity、
  // activateRuntime 和 deactivateRuntime，并在后两者中调用 SDK 的交接 API。

  @override
  Future<void> initialize() => _engine.initialize();

  @override
  Future<UnifiedVideoState> open(
    VideoSource source,
    UnifiedVideoState state,
  ) async {
    await _engine.open(source.uri, headers: source.headers);
    return _stateFromEngine(
      state.copyWith(
        source: source,
        activeKernelId: descriptor.id,
        clearError: true,
      ),
    );
  }

  @override
  Future<UnifiedVideoState> snapshot(UnifiedVideoState state) async {
    return _stateFromEngine(state);
  }

  @override
  Future<UnifiedVideoState> play(UnifiedVideoState state) async {
    await _engine.play();
    return _stateFromEngine(state);
  }

  @override
  Future<UnifiedVideoState> pause(UnifiedVideoState state) async {
    await _engine.pause();
    return _stateFromEngine(state);
  }

  @override
  Future<UnifiedVideoState> seek(
    Duration position,
    UnifiedVideoState state,
  ) async {
    await _engine.seek(position);
    return _stateFromEngine(state);
  }

  @override
  Future<UnifiedVideoState> stop(UnifiedVideoState state) async {
    await _engine.stop();
    return _stateFromEngine(state);
  }

  @override
  Future<UnifiedVideoState> setSpeed(
    double speed,
    UnifiedVideoState state,
  ) async {
    await _engine.setSpeed(speed);
    return _stateFromEngine(state);
  }

  @override
  Future<UnifiedVideoState> setFit(
    UnifiedVideoFit fit,
    UnifiedVideoState state,
  ) async {
    return state.copyWith(fit: fit);
  }

  @override
  Future<UnifiedVideoState> setVolume(
    double volume,
    UnifiedVideoState state,
  ) async {
    await _engine.setVolume(volume);
    return _stateFromEngine(state);
  }

  @override
  Widget buildSurface(BuildContext context, UnifiedVideoState state) {
    return _engine.buildSurface(context);
  }

  @override
  Future<void> dispose() => _engine.dispose();

  UnifiedVideoState _stateFromEngine(UnifiedVideoState state) {
    return state.copyWith(
      lifecycle: _engine.lifecycle,
      position: _engine.position,
      duration: _engine.duration,
      speed: _engine.speed,
      volume: _engine.volume,
    );
  }
}
```

`open` 将 `VideoSource.uri` 和请求头交给 SDK，并将当前播放源和内核 ID 写回统一状态；`snapshot`、播放、暂停、跳转、停止、倍速和音量操作都在调用 SDK 后重新读取 engine 属性。`setFit` 只更新统一 UI 缩放状态；若 SDK 自身也有画面缩放接口，可在该方法中一并调用。`buildSurface` 返回 SDK 的真实渲染视图，`dispose` 必须释放 SDK 的控制器、订阅和原生资源。

将实际 SDK 的创建函数传给 `createAppVideoKernel`。factory 会在每次 controller 创建 adapter 时调用一次 `createEngine()`，避免不同播放器复用同一个可变 engine。控制器切换内核时会按统一状态调用新 adapter 的 `open`、`seek`、`setSpeed`、`setFit`、`setVolume` 和播放/暂停，因此 engine 的 getters 与 SDK 实际状态必须保持同步；目标内核失败时控制器会用同一流程恢复原 adapter。

最低环境要求：Flutter 3.44、Dart 3.12.2、Android API 26、iOS 13 和 macOS 10.15。Windows 需要 Flutter 支持的 Visual Studio C++ 桌面工具链。

运行完整场景 Demo：

```bash
cd example
flutter run
```

## 示例播放地址

示例应用内置了一组真实验证场景，不再使用 `example.com` 占位地址：

| 场景 | 地址 | 首选内核 | 验证重点 |
| --- | --- | --- | --- |
| 本地 MP4 自检 | `assets/videos/demo_tone.mp4` | Video Player -> FVP -> Media Kit | 不依赖外网，验证画面、声音、进度刷新 |
| MP4 点播 | `https://media.w3.org/2010/05/bunny/trailer.mp4` | Video Player -> FVP -> Media Kit | 普通点播、播放暂停、进度拖动、缩放、倍速 |
| 短 MP4 切集 | `https://media.w3.org/2010/05/video/movie_300.mp4` | Video Player -> FVP -> Media Kit | 上一集、下一集、切换内容 |
| HLS 点播 | `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8` | Video Player -> FVP -> Media Kit | m3u8 点播、缓冲、seek |
| HLS 直播测试流 | `https://cph-p2p-msl.akamaized.net/hls/live/2000341/test/master.m3u8` | Video Player -> FVP -> Media Kit | 直播式 m3u8、无固定总时长、缓冲边界 |
| DASH 点播 | `https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd` | Media Kit -> FVP | mpd 自适应流、非支持内核失败提示 |
| 错误地址 | `https://example.invalid/video-missing.mp4` | Media Kit -> FVP -> Video Player | failed 状态、错误提示、重试入口 |

## 核心用法

```dart
import 'package:leelando_video_all/leelando_video_all.dart';

final controller = UnifiedVideoController(
  registry: VideoKernelRegistry(kernels: createAllVideoKernels()),
  preference: KernelPreference.ordered(
    defaultNetworkKernelOrder,
    includeUnspecified: false,
  ),
);

await controller.open(
  VideoSource.network(
    sampleMp4Url,
    metadata: const VideoMetadata(title: '示例影片'),
  ),
);

await controller.play();
await controller.setFit(UnifiedVideoFit.cover);
await controller.setSpeed(1.25);
```

默认 UI：

```dart
UnifiedVideoPlayer(
  controller: controller,
  onPrevious: previousEpisode,
  onNext: nextEpisode,
  onSwitchContent: switchContent,
)
```

默认控件包含进度、当前时间、总时长、上一集、下一集、播放/暂停、全屏、切换内容、切换内核、缩放模式和倍速选择。

### 内置选集

将片源作为 `VideoEpisode` 传入后，播放器会在内部打开上一集、下一集和选集面板中的目标集；`onEpisodeChanged` 只用于同步宿主状态或更新业务展示，不需要再次调用 `controller.open`。`initialEpisodeId` 只设置初始选中/高亮项，不会自动打开片源；宿主必须显式调用 `controller.open` 建立初始播放。

```dart
final episodes = <VideoEpisode>[
  VideoEpisode(
    id: 'e01',
    title: '第 1 集',
    subtitle: '启程',
    source: VideoSource.network('https://example.com/e01.m3u8'),
  ),
];

await controller.open(episodes.first.source);

UnifiedVideoPlayer(
  controller: controller,
  episodes: episodes,
  initialEpisodeId: 'e01',
  onEpisodeChanged: (episode) {
    debugPrint('正在播放 ${episode.title}');
  },
)
```

### 宿主应用的屏幕适配

如需使用 `flutter_autosize_screen`，只能由宿主应用在应用根部初始化并完成 `MediaQuery` 的尺寸转换：移动端以短边 `393` 为设计基准，桌面端以短边 `720` 为设计基准。播放器核心包不会导入、初始化或声明 `flutter_autosize_screen` 依赖；传入播放器的是宿主已转换后的 `MediaQuery` 环境。

示例首页参考 GSYVideoPlayer 常见播放器验证思路，提供 MP4、HLS、DASH、错误地址、上一集/下一集、切换内容、切换内核、缩放模式、播放倍速和全屏入口。所有播放源场景定义在 `defaultPlaybackScenarios`，业务应用可以直接复用或替换成自己的片源清单。

## GSY 场景验证

demo 首页内置 “GSY 场景验证” 选择器，覆盖以下可操作场景：

| 场景 | demo 验证内容 |
| --- | --- |
| 打开一个播放 | 旋转 90°、水平镜像、填充、裁剪 |
| 列表/详情模式 | 列表切源、动画进入详情、详情旋转、小窗体 |
| 弹幕 | 播放器覆盖层滚动弹幕，不侵入播放器内核 |
| 滤镜和 GL 动画 | `ColorFiltered` 滤镜和 3D transform 动画，用于验证渲染链路外层效果 |
| 背景铺满模糊播放 | 背景封面铺满并模糊，前景播放器保持可交互 |
| 进度条小窗口预览 | WebVTT 缩略图轨道解析，拖动进度时显示对应图片和 `xywh` 裁剪信息 |

进度预览不对原视频做客户端批量抽帧，库层提供：

```dart
final provider = const GSYVideoPreviewVttParser().parse(
  webVttContent,
  baseUri: Uri.parse('https://cdn.example.test/previews/'),
);

final frame = provider.frameFor(const Duration(seconds: 12));
print(frame?.imageUri);
print(frame?.cropRect);
```

支持独立图片，也支持雪碧图坐标：

```text
WEBVTT

00:00:00.000 --> 00:00:01.000
160p-00001.jpg#xywh=0,0,284,160
```

## 内核选择规则

`VideoKernelRegistry` 保存所有已注册内核。控制器打开播放源时按以下顺序选择内核：

1. 调用方指定的精确内核。
2. 调用方指定的有序偏好列表。
3. 注册表中的可兼容内核。
4. 如果没有兼容内核，抛出 `UnsupportedKernelException`，并在状态中保留平台、播放源类型、候选内核和跳过内核诊断。

每个内核通过 `VideoKernelDescriptor` 声明平台、播放源类型、字幕、音轨、倍速、缩放和已知限制。控制器不会静默替换不支持的缩放模式或倍速，而是返回“不支持能力”错误。

## 引擎支持矩阵

| 内核 | Android | iOS | Windows | macOS | 当前状态 |
| --- | --- | --- | --- | --- | --- |
| Fake 测试内核 | 支持 | 支持 | 支持 | 支持 | 已实现，用于示例和测试 |
| Media Kit / libmpv | 支持 | 支持 | 支持 | 支持 | 已实现基础播放适配 |
| FVP / libmdk | 支持 | 支持 | 支持 | 支持 | 已实现基础播放适配，注册后会替换 `video_player` 平台实现 |
| Flutter 官方 Video Player | 支持 | 支持 | 不支持 | 支持 | 已实现基础播放适配 |

当前已完成的真实内核是 Media Kit/libmpv、FVP/libmdk 和 Flutter 官方 Video Player；Fake 只用于单元测试和 UI 验证。

切换播放器内核是事务操作：控制器会保留当前播放源、播放进度、倍速、缩放、音量、播放/暂停和全屏状态；切到打开后需要异步 ready 的后端时，会带起播点打开并重试 seek，避免从 0 秒重新播放。目标内核打开或恢复失败时，控制器会重新打开原内核并恢复同一份状态；只有原内核也恢复失败时才进入 `failed` 状态。

FVP 会替换 `video_player` 平台实现，因此 FVP 与 Flutter 官方 Video Player 共享同一运行时组。同一个播放器视图在两者之间只能串行切换，控制器会在激活目标内核前释放前一内核并完成运行时交接；不要让不同播放器视图并发占用 FVP 和官方 `video_player`。

## 平台网络权限

网络视频播放必须具备平台出站网络权限：

- Android：`android/app/src/main/AndroidManifest.xml` 需要声明 `android.permission.INTERNET`，否则 release 包无法拉取网络视频。
- macOS：`DebugProfile.entitlements` 和 `Release.entitlements` 需要声明 `com.apple.security.network.client`，否则沙盒 App 无法访问外网播放地址。
- iOS：当前示例地址均为 HTTPS，不需要额外 ATS 例外；如果业务使用 HTTP 明文流，需要按域名配置 App Transport Security。

demo 的自动降级只在真实播放内核 `video-player -> fvp -> media-kit` 内尝试，不会自动降级到 Fake 测试内核，避免占位画面掩盖真实播放失败。

demo 打开播放源后会自动调用 `play()`，并通过控制器定时读取后端 `snapshot` 刷新进度、总时长、缓冲和播放状态。首屏默认使用本地 MP4 自检，确认播放器链路正常后再切换远程 MP4/HLS/DASH。

## 缩放和倍速

缩放模式：

- `original`：原始
- `ratio16x9`：16:9
- `ratio4x3`：4:3
- `contain`：适应
- `fill`：填充
- `cover`：裁剪

倍速档位：

- `0.5`
- `0.75`
- `1.0`
- `1.25`
- `1.5`
- `1.75`
- `2.0`
- `3.0`

## 从 `lee_video` 0.1.x 迁移到 `leelando_video` 0.2.0

`leelando_video` 是 `lee_video` 的新包名。0.2.0 同时将具体播放引擎从核心包拆出；原来只从 `package:lee_video/lee_video.dart` 导入并注册具体工厂函数的写法，需要改为：核心包的 import 仅保留给 `UnifiedVideoController`、`VideoSource`、`VideoKernelRegistry` 和 UI，具体工厂函数改从对应 `leelando_video_*` 内核包或 `leelando_video_all` 导入。

```dart
// 0.2.0：一次启用全部内核时使用全量公共入口。
import 'package:leelando_video_all/leelando_video_all.dart';

final registry = VideoKernelRegistry(kernels: createAllVideoKernels());
```

若采用按需安装，请把旧注册列表替换为对应包的工厂函数，例如 `createMediaKitVideoKernel()` 来自 `leelando_video_media_kit`，`createFvpVideoKernel()` 来自 `leelando_video_fvp`，`createOfficialVideoPlayerKernel()` 来自 `leelando_video_video_player`。

已有业务应继续用 `VideoSource` 代替后端专属播放源参数，用 `UnifiedVideoController` 统一播放、暂停、跳转、音量、倍速、缩放和全屏，并用 `UnifiedVideoState` 替代后端专属状态流。切核失败时捕获 `KernelSwitchException`；状态中的 `lastKernelSwitchError` 会说明原内核是否已成功回滚。

## 验证

```bash
flutter analyze
flutter test

cd example
flutter build apk --debug
flutter build macos --debug
flutter build ios --debug --no-codesign
```
