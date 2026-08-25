# leelando_video_erika

`leelando_video_erika` 是 `leelando_video` 的 Erika / Rust Renderer 可插拔播放内核。应用按需安装本包，并将工厂注册到 `VideoKernelRegistry`；核心包不会隐式引入 Erika 原生依赖。

## 安装

```yaml
dependencies:
  leelando_video: ^0.2.0
  leelando_video_erika: ^0.2.0
```

## 注册

```dart
import 'package:leelando_video/leelando_video.dart';
import 'package:leelando_video_erika/leelando_video_erika.dart';

final registry = VideoKernelRegistry(
  kernels: <RegisteredVideoKernel>[
    createErikaVideoKernel(),
  ],
);
```

内核 ID 为 `erika`，支持 Android、iOS、Windows、macOS，以及 asset、file、network 播放源。统一音量 `0.0..1.0` 会直接传给 Erika 原生音量接口；打开播放源时会恢复非零播放进度。

Erika 依赖对应平台的原生运行库与构建工具链。Flutter asset 会复制到系统临时文件；当前网络播放源会缓存到临时文件后交给 Erika 打开。

## 许可证

MIT
