# 移动端全屏方向规格

## 目标

播放器在 Android 与 iOS 上同时支持横屏全屏和竖屏全屏，适配 9:16 短剧；业务方可以固定方向或按播放器画面比例自动选择，并可在全屏内手动切换方向。

## 公共接口

- 新增 `UnifiedVideoFullscreenOrientation.landscape`、`portrait`、`auto`。
- `UnifiedVideoPlayer.fullscreenOrientation` 默认 `landscape`，保持现有行为。
- `auto` 使用 `UnifiedVideoPlayer.aspectRatio`：小于 `1` 进入竖屏，否则进入横屏。

## 交互与布局

- Android/iOS 全屏时显示方向切换按钮；桌面端不显示。
- 方向按钮在竖屏与横屏之间切换，不退出全屏，不重建播放器 Surface。
- 竖屏全屏使用独立响应式布局：进度与时间保持可见，工具控件和上一集/播放暂停/下一集拆成两行，避免横向溢出。
- 9:16 播放器在横屏退出全屏后若嵌入宽度过窄，compact 控件自动拆成两行，且播放控件行保持最靠近底部。
- 竖屏全屏仍显示选集入口；嵌入式手机竖屏仍隐藏选集入口。
- 退出全屏后解除方向锁定并恢复系统 UI，使业务页面回到应用原有方向策略。

## 平台边界

- Android/iOS 使用 `SystemChrome.setPreferredOrientations`。
- 横屏允许 `landscapeLeft` 与 `landscapeRight`；竖屏锁定 `portraitUp`。
- macOS、Windows、Linux 沿用现有原生全屏通道，忽略方向参数。
- Web 与 unknown 平台不执行方向操作。
