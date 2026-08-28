## 0.3.0 - 2026-08-28

- 升级全部依赖至 0.3.0。
- 移除 Erika 内核，`createAllVideoKernels` 现在按 MediaKit、FVP、Flutter 官方 `video_player` 顺序注册三个内核。

## 0.2.0 - 2026-08-25

- 首次发布全量便捷包，重导出 `leelando_video` 核心和四个可选播放内核。
- 提供按 Erika、Media Kit、FVP、Flutter 官方 Video Player 稳定排序的 `createAllVideoKernels` 工厂。
