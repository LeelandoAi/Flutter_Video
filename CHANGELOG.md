# 更新日志

## 0.2.0 - 2026-08-25

- 新增 `VideoEpisode`、`episodes`、`initialEpisodeId` 和 `onEpisodeChanged` 公共 API；播放器可在内部完成上一集、下一集和选集导航。
- View 升级为响应式 Liquid Glass 播放器界面，并保留不同屏幕尺寸下的选集交互。
- 保持 `onPrevious`、`onNext` 和 `onSwitchContent` 等旧回调兼容；未传入内置选集时沿用旧行为。
- 包名由 `lee_video` 迁移为 `leelando_video`，可选内核包同步使用 `leelando_video_*` 前缀。
- 建立 Pub workspace，并将核心包依赖收敛为 Flutter SDK。
- 将 Erika、Media Kit、FVP 和 Flutter 官方 `video_player` 内核拆分为独立可安装包，并提供全量便捷包 `leelando_video_all`。
- 核心公共 API 不再导出具体播放引擎或兼容占位入口；应用必须按需依赖内核包并从对应公共入口注册工厂函数。
- 内核切换改为事务恢复：保留播放源、进度、倍速、缩放、音量、播放状态和全屏；目标内核失败时自动回滚原内核。
- 补齐切核后的音量恢复，并将 FVP 与官方 `video_player` 的平台实现交接限制为同一播放器视图串行交接，禁止不同播放器视图并发占用。
- 修复运行时停用失败后错误复用失效租约的问题；相同内核回滚时会显式重新激活运行时，恢复失败会同时保留停用和恢复诊断。
- 修复原生全屏事件在切核事务排队期间丢失最新状态的问题，并补齐运行时冲突与 adapter 清理同时失败时的结构化诊断。
- 新增 Windows 冷缓存 CI，在 Windows runner 上执行 workspace 分析、全部包测试和 Demo 构建。
- 这是破坏性迁移：从 0.1.x 升级时请替换核心包中的具体工厂函数 import，移除旧的 Erika 占位工厂函数，并按实际所需引擎调整依赖。

## 0.1.0（原 `lee_video` 包）

- 首次公开版本。
- 提供统一的播放器控制器、播放状态、播放源和播放器 View API。
- 支持 Media Kit/libmpv、FVP/libmdk、Flutter Video Player 和 Erika 内核。
- 支持 Android、iOS、macOS 和 Windows。
- 支持播放控制、进度拖动、倍速、画面缩放、内核切换和全屏播放。
- 提供弹幕、滤镜、背景模糊和 WebVTT 进度预览等场景验证。
