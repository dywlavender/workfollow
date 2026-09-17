# Icons

业务 Widget 只从 `WorkFollowIcons` 取 `IconData`，普通代码不得直接使用 `Icons.*` 或 `CupertinoIcons.*`。

语义映射区分：

```text
complete / incomplete
undo / restore
delete / deleteForever
calendar / schedule / deadline
checklist / task completion
```

默认使用 Outline / Rounded；Filled 只保留给明确的完成或激活状态。Slash 的 H1/H2/H3、ordered numeral 和自定义 checkbox 是绘制层例外。
