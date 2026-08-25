# leelando_video_media_kit

`leelando_video_media_kit` 是 `leelando_video` 的 MediaKit / libmpv 可插拔播放内核。应用按需安装本包，并将工厂注册到 `VideoKernelRegistry`；核心包不会隐式引入 MediaKit 原生依赖。

## 安装

```yaml
dependencies:
  leelando_video: ^0.2.0
  leelando_video_media_kit: ^0.2.0
```

## 注册

```dart
import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_media_kit/leelando_video_media_kit.dart';

final registry = VideoKernelRegistry(
  kernels: <RegisteredVideoKernel>[
    createMediaKitVideoKernel(),
  ],
);
```

内核 ID 为 `media-kit`，支持 Android、iOS、Windows、macOS，以及 asset、file、network 播放源。统一音量 `0.0..1.0` 会乘以 100 后传给 MediaKit；非零播放进度会作为 `Media.start` 起播提示保留，切换事务在 ready 后继续执行 seek 校准。

本包依赖 `media_kit_libs_video` 提供对应平台的 libmpv 原生运行库。

## 许可证

MIT
