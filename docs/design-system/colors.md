# Colors

业务组件通过 `WorkFollowTheme` 和 `WorkFollowColorTokens` 读取语义颜色：

```text
canvas / sidebar / content / inspector / overlay
textPrimary / textSecondary / textTertiary / textDisabled
border / borderStrong / menuSelected / menuDivider
accent / accentHover / accentSoft
success / warning / danger
feedbackSurface / feedbackText / feedbackAction
```

原始 Hex 只允许留在主题 Token。用户清单颜色、习惯颜色、图表 Palette 和图片内容属于用户数据/内容色，不能冒充 UI Token。需要在有色表面放文字时使用 `WorkFollowThemeContrast.foregroundOn`。
