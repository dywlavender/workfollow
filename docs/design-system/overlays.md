# Overlays

菜单、Picker、Slash、More、Context、Command Palette、日期/标签选择器和持久 Toolbar 共享 `DesktopOverlayPolicy`、定位计算和 Surface role。

普通菜单可以恢复编辑器 focus；Slash 和 A Toolbar 必须保留 editor selection。Esc 只关闭最高层，外部点击关闭当前浮层，切任务或切页面清理 overlay。Toolbar 的持久生命周期由 `PersistentAnchoredPopoverController` 管理。
