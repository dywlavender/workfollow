# Surfaces

`WorkFollowSurfaceTokens` 将材质分成：

```text
surface → input → card → popover → dialog → toast
```

每个角色同时决定 radius、border 和 shadow level。普通页面不自行拼 `BoxShadow`；Popover、Dialog、Toast 使用对应 Surface role。焦点 ring 属于交互状态，不用粗边框冒充 selected。
