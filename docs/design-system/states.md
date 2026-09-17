# States

`WorkFollowInteractionStyles` 统一 default、hover、pressed、selected、focused、disabled、destructive 的优先级。

```text
disabled > pressed > selected > focused > hover > default
```

Hover 和 Selected 使用中性 Surface；Focus 单独使用 ring；Destructive 默认保持中性，仅在 hover/pressed 时使用低强度 danger tint。TaskRow、Menu、Picker、Toolbar、Sidebar、Calendar、Board 和 Matrix 的差异只应来自模块尺寸和内容语义。
