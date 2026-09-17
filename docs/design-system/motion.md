# Motion

动画时序和曲线来自 `WorkFollowMotionTokens` 与 `WorkFollowMotionPolicy`：

```text
hoverTransition / selectionTransition / controlPress
popoverEnter / popoverExit / panelTransition / collapseExpand
taskComplete / feedbackToastEnter / feedbackToastExit / dragReorder
```

Tooltip 等待和子菜单意图延迟也有命名 Token。反馈 HUD 的停留时间属于内容策略，不是进退场动画。`MediaQuery.disableAnimations` 开启时，策略自动切到短时长线性过渡并关闭 spring。
