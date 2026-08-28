## 1.0.0 - 2026-08-28

- 升级至 `leelando_video` 1.0.0，并保持竖屏视频基于播放器尺寸等比适配。

## 0.3.0 - 2026-08-28

- 升级至 `leelando_video` 0.3.0。
- Android 改用 FFmpeg 与 dav1d 软件视频解码，规避部分设备在切换 Surface 后硬件解码黑屏的问题。

## 0.2.0 - 2026-08-25

- 首次发布独立可安装的 FVP 播放内核。
- 提供私有 `VideoPlayerController` wrapper 和统一播放状态映射。
- 支持与官方 `video_player` 适配器同注册、同 View 串行切换。
- 在最终运行时租约释放后恢复先前的 `VideoPlayerPlatform`。
- 补齐 asset/file 精确地址和实际平台 Surface 构建验证。
