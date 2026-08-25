# lee_video_video_player

`lee_video_video_player` 是 `lee_video` 的 Flutter 官方 `video_player` 可插拔内核，适用于 Android、iOS 和 macOS。

## 安装

```bash
flutter pub add lee_video lee_video_video_player
```

## 导入

```dart
import 'package:lee_video/lee_video.dart';
import 'package:lee_video_video_player/lee_video_video_player.dart';
```

## 注册内核

```dart
final VideoKernelRegistry registry = VideoKernelRegistry(
  kernels: <RegisteredVideoKernel>[
    createOfficialVideoPlayerKernel(),
  ],
);

final UnifiedVideoController controller = UnifiedVideoController(
  registry: registry,
  platform: UnifiedVideoPlatform.android,
);
```

该内核使用运行时组 `video-player-platform` 和身份 `video-player-official`。同一进程中若存在会替换 `video_player` 平台实现的其他内核，应通过 `lee_video` 的运行时协调器管理切换。
