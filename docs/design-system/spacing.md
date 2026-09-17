# Spacing

基础间距为 `0 / 4 / 8 / 12 / 16 / 20 / 24 / 28 / 32`，定义在 `WorkFollowSpacing.space1…space8`。页面和组件优先使用语义别名，例如 `pageHorizontalPadding`、`menuItemPadding`、`taskRowHorizontalPadding`、`popoverPadding` 和 `toolbarItemGap`。

`EdgeInsets`、`SizedBox` 和 `Wrap` 的留白表达结构关系；不要为了局部截图重新引入未命名的 7、9、11、13。确有必要的校准值必须进入模块 Metrics 或 [Exceptions](exceptions.md)。
