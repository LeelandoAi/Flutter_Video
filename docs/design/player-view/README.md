# Player View 设计交付

本目录是手机端与电脑端播放器 View 的设计交付，不包含 Flutter 实现修改。

- [高保真 UI 设计板](liquid-glass-player-ui.html)
- [完整 PNG 预览](assets/player-view-design-board.png)
- [尺寸、响应式、状态与交互规格](../../superpowers/specs/2026-08-27-player-view-liquid-glass-design.md)

已确认的核心方向：

- 主控制层全部无背景。
- 上一集、播放／暂停、下一集及上下文操作采用贴底单行。
- 手机竖屏嵌入底距 `1 pt`，桌面嵌入底距 `2 dp`，横屏／全屏额外底距为 `0`。
- 选集仅在横屏、全屏或桌面宽布局出现。
- Liquid Glass 只用于选集、倍速和设置浮层。

