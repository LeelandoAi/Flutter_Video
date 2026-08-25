# lee_video_fvp

`lee_video_fvp` 是基于 FVP 和 libmdk 的 `lee_video` 可插拔播放内核，支持 Android、iOS、Windows 和 macOS。

## 安装

```bash
flutter pub add lee_video lee_video_fvp
```

## 注册

```dart
import 'package:lee_video/lee_video.dart';
import 'package:lee_video_fvp/lee_video_fvp.dart';

final VideoKernelRegistry registry = VideoKernelRegistry(
  kernels: <RegisteredVideoKernel>[
    createFvpVideoKernel(),
  ],
);
```

FVP 与 Flutter 官方 `video_player` 适配器可以同时注册到同一个 `VideoKernelRegistry`。二者共享 `video-player-platform` 运行时组，因此同一个播放器 View 可以先释放当前内核，再串行切换到另一个内核。

不同 View 不能同时占用 FVP 与官方平台实现。运行时协调器会拒绝这种并发请求，应用应等待当前 View 完成释放后再切换。

FVP 最终运行时租约释放前，`lee_video` 会先释放适配器及其内部 `VideoPlayerController`；随后本包调用空 `platforms` 的 `fvp.registerWith`，恢复激活 FVP 前的 `VideoPlayerPlatform` 实例。
