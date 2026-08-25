# leelando_video_all

`leelando_video_all` 是 `leelando_video` 的全量便捷包：一次引入核心包，以及 Erika、Media Kit、FVP 和 Flutter 官方 `video_player` 四个可选播放内核。

本包刻意包含全部原生播放引擎，适合需要在运行时按平台或播放源选择、切换全部内核的应用。它会带来所有内核及其原生依赖；需要控制应用体积时，应直接选择所需的独立内核包，而不是依赖本包。

## 使用

```dart
import 'package:leelando_video_all/leelando_video_all.dart';

final registry = VideoKernelRegistry(
  kernels: createAllVideoKernels(),
);
```

工厂每次调用都会返回新的固定顺序列表：`erika`、`media-kit`、`fvp`、`video-player`。

## 许可证

MIT
