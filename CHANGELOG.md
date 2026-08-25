# 更新日志

## 0.2.0 - 2026-08-25

- 建立 Pub workspace，并将核心包依赖收敛为 Flutter SDK。
- 将 Flutter 官方 `video_player` 内核拆分为独立可安装包 `lee_video_video_player`。
- 核心公共 API 不再导出具体播放引擎或兼容占位入口。

## 0.1.0

- 首次公开版本。
- 提供统一的播放器控制器、播放状态、播放源和播放器 View API。
- 支持 Media Kit/libmpv、FVP/libmdk、Flutter Video Player 和 Erika 内核。
- 支持 Android、iOS、macOS 和 Windows。
- 支持播放控制、进度拖动、倍速、画面缩放、内核切换和全屏播放。
- 提供弹幕、滤镜、背景模糊和 WebVTT 进度预览等场景验证。
