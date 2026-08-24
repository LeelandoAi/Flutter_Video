# Lee Video

一个面向 Android、iOS、Windows、macOS 的统一聚合影视播放器库。当前实现已落地核心 API、内核抽象、默认播放器 UI、fake 测试内核、Media Kit/libmpv 适配器、FVP/libmdk 适配器、官方 Video Player 适配器和 Erika/Rust Renderer 适配器。

## 安装

```bash
flutter pub add lee_video
```

```dart
import 'package:lee_video/lee_video.dart';
```

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
import 'package:lee_video/lee_video.dart';

final controller = UnifiedVideoController(
  registry: VideoKernelRegistry(
    kernels: [
      createFakeVideoKernel(),
      createMediaKitVideoKernel(),
      createFvpVideoKernel(),
      createOfficialVideoPlayerKernel(),
      createErikaKernelPlaceholder(),
    ],
  ),
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
| Erika / Rust Renderer | 支持 | 支持 | 支持 | 支持 | 已接入 `erika_flutter`，`erika` 内核由 Erika 官方 Rust/原生后端打开播放源 |

当前已完成的真实内核是 Media Kit/libmpv、FVP/libmdk、Flutter 官方 Video Player 和 Erika/Rust Renderer；Fake 只用于单元测试和 UI 验证。Erika 适配器直接封装 `erika_flutter` 的 `ErikaPlayer` 和 `ErikaVideoView`，播放、暂停、seek、倍速、画面承载和事件状态都来自 Erika 后端，不再委托 Media Kit。

切换播放器内核时，控制器会保留当前播放源、播放进度、倍速和播放/暂停状态；切到 Media Kit/Erika 这类打开后需要异步 ready 的后端时，会带起播点打开并重试 seek，避免从 0 秒重新播放。

Erika 构建依赖官方原生插件和 native library。首次构建会从 AimesSoft/Erika GitHub Releases 下载与 `erika_flutter` 版本匹配并经过 SHA-256 校验的预编译运行库，因此构建机必须能够访问 GitHub Release Assets；Flutter asset 播放会先复制到系统临时文件，再交给 Erika 以本地路径打开。

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

## 迁移建议

如果现有应用直接使用 `media_kit`、`fvp` 或 `video_player` 的后端控制器，建议先迁移到 `UnifiedVideoController`：

1. 用 `VideoSource` 替代后端专属播放源参数。
2. 通过 `VideoKernelRegistry` 注册需要的内核。
3. 用 `UnifiedVideoController` 统一处理播放、暂停、跳转、倍速、缩放和全屏。
4. 用 `UnifiedVideoState` 替代后端专属状态流。
5. 逐步把自定义 UI 改为依赖统一控制器，或者直接使用 `UnifiedVideoPlayer`。

## 验证

```bash
flutter analyze
flutter test
dart pub publish --dry-run

cd example
flutter build apk --debug
flutter build macos --debug
flutter build ios --debug --no-codesign
```
