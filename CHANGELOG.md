# 更新日志

## 0.2.0 - 2026-08-25

- 建立 Pub workspace，并将核心包依赖收敛为 Flutter SDK。
- 将 Erika、Media Kit、FVP 和 Flutter 官方 `video_player` 内核拆分为独立可安装包，并提供全量便捷包 `lee_video_all`。
- 核心公共 API 不再导出具体播放引擎或兼容占位入口；应用必须按需依赖内核包并从对应公共入口注册工厂函数。
- 内核切换改为事务恢复：保留播放源、进度、倍速、缩放、音量、播放状态和全屏；目标内核失败时自动回滚原内核。
- 补齐切核后的音量恢复，并将 FVP 与官方 `video_player` 的平台实现交接限制为同一播放器视图串行交接，禁止不同播放器视图并发占用。
- 这是破坏性迁移：从 0.1.x 升级时请替换核心包中的具体工厂函数 import，移除旧的 Erika 占位工厂函数，并按实际所需引擎调整依赖。

## 0.1.0

- 首次公开版本。
- 提供统一的播放器控制器、播放状态、播放源和播放器 View API。
- 支持 Media Kit/libmpv、FVP/libmdk、Flutter Video Player 和 Erika 内核。
- 支持 Android、iOS、macOS 和 Windows。
- 支持播放控制、进度拖动、倍速、画面缩放、内核切换和全屏播放。
- 提供弹幕、滤镜、背景模糊和 WebVTT 进度预览等场景验证。
