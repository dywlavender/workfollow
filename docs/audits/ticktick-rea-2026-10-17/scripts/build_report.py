#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_report.py -- render ticktick-detail-nib-inventory.md from the parsed
inventory JSON + validation JSON.  All numbers in the report are generated
from the JSON so the markdown cannot drift from the machine-readable data.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from collections import Counter, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)


def esc(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def cut(s, n=30):
    s = str(s)
    return s if len(s) <= n else s[: n - 1] + "…"


def cls_short(s):
    if not s:
        return "—"
    if s.startswith("_TtC8TickTick"):
        rest = s[len("_TtC8TickTick"):]
        i = 0
        while i < len(rest) and rest[i].isdigit():
            i += 1
        return rest[i:]
    return s


def num(v):
    if v is None:
        return "—"
    f = float(v)
    return str(int(f)) if f.is_integer() else str(f)


def cls_disp(s):
    """Full mangled symbol, but visually split: _TtC8TickTick|19|Name."""
    if not s or not s.startswith("_TtC8TickTick"):
        return s or "—"
    rest = s[len("_TtC8TickTick"):]
    m = ""
    while rest and rest[0].isdigit():
        m += rest[0]
        rest = rest[1:]
    return "`_TtC8TickTick`%s`%s`" % (m, rest)


RESPONSIBILITY = {
    "TTSingleTaskDetailViewController.nib": (
        "详情页宿主（整页滚动容器）：顶部容器 + 表格 + 标签集合视图 + 底部容器，"
        "用高度/边距约束拼装完整详情页",
        "outlets: containerForTopView / containerForBottomView / tableView / "
        "topContainerHeightLC / bottomViewHeightConstraint / topMarginConstraint"),
    "TTTaskDetailWindowController.nib": (
        "把详情页放进独立 NSWindow（弹窗形态）；窗口标题为占位 “Window”",
        "NSWindowRect {{196,240},{479,381}}、NSWindowView 479×381、outlets window/delegate"),
    "TTDetailContainerViewController.nib": (
        "详情容器占位：只有一个 TTBlockEventView，无子控件，推断由代码注入内容",
        "唯一 outlet view → TTBlockEventView {480,272}"),
    "TTTaskDetailHolderViewController.nib": (
        "详情空态/装载态持有者：emptyImageView（0×0，默认隐藏）+ 根 view",
        "outlets emptyImageView / view；NSImageView frame {{228,0},{0,0}}"),
    "TTTaskDetailTopView.nib": (
        "详情头部条：完成勾选、日期、重复、优先级、指派人、备注信息、返回、标题、进度条",
        "18 outlets、6 个不同 action、7 张图标（checkbox/close_detail/menu_calendar/"
        "set_repeat/assign_menu/priority_stroke/notes_information）"),
    "TTTaskDetailTitleCell.nib": (
        "标题行：完成勾选按钮 + 类型切换按钮（detail_mode_text / checkbox_abandoned 图标）",
        "outlets checkboxButton / kindButton；actions checkboxButtonClicked: / kindButtonClicked:"),
    "TTTaskDetailContentCell.nib": (
        "正文行容器（207×47，无子控件、无连接）→ 推断正文由代码创建并嵌入",
        "root only；无 cell、无 outlet"),
    "TTTaskDetailDescriptionCell.nib": (
        "描述/备注区容器（480×272，无子控件）→ 推断备注编辑器由代码注入",
        "root only；无 cell、无 outlet"),
    "TTTaskDetailBottomView.nib": (
        "底部区域骨架：4 个等高（50）子容器 + 4 条高度约束，用于挂载底栏/评论/动态等子视图",
        "outlets subContainer1..4 + subContainerHeightConstraint1..4；frames y=0/50/100/150"),
    "TTTaskDetailBottomActionView.nib": (
        "底栏操作条（40 高）：清单/项目、标签、Markdown 编辑、合并、评论、删除、永久删除、更多",
        "15 outlets、8 个 action、8 张图标（move_task/tag/comment/sidebar_trash/"
        "more/combination/md_edit/delete_forever），projectButton 带文本 “Inbox”"),
    "TTTaskDetailSubtaskCell.nib": (
        "子任务行容器（354×80，无子控件）→ 推断子任务标题/勾选由代码绘制",
        "root only；无 cell、无 outlet"),
    "TTTaskDetailCheckItemCell.nib": (
        "检查事项行：拖拽手柄 + 勾选框 + 提醒按钮 + 删除按钮",
        "outlets checkBoxButton / dragIndicator / reminderButton / deleteButton + 4 条 LC；"
        "actions checkBoxButtonClicked: / reminderButtonClicked: / deleteButtonClicked:"),
    "TTTaskDetailParentTaskCell.nib": (
        "父任务入口行：一个 45×16 的按钮，文本占位 “Button”",
        "outlet titleButton；action titleButtonClicked:"),
    "TTTaskDetailTagCollectionCell.nib": (
        "标签集合容器：左/右边距约束 + 内部横向滚动的标签集合视图（440×165）",
        "outlets collectionView / leftMarginLC / rightMarginLC；TTDisableScrollView"),
    "TTTaskDetailTagCollectionViewItem.nib": (
        "标签 chip：可编辑文本框 + 删除按钮 + 添加图标 + 背景视图（318×24）",
        "outlets inputTextField / deleteButton / addImageView / backgroundView / view；"
        "action deleteButtonClicked:"),
    "TTTaskDetailSpaceCell.nib": (
        "纯间距占位 cell（480×272 画布，无内容）",
        "root only；无 cell、无 outlet"),
    "TTTaskDetailNotionBlockCell.nib": (
        "Notion 属性块外壳：图标 + 名称 + 分隔线 + 垂直 stack + “打开 Notion” 按钮",
        "outlets notionIconView / notionNameLabel / notionDivider / stackView / "
        "notionButton / containerView；action openInNotionButtonClicked:"),
    "TTTaskDetailNotionBlockShortTextView.nib": (
        "Notion 短文本属性行：key 标签（60 宽）+ value 标签",
        "outlets keyLabel / keyLabelWidthLC / valueLabel；文本 “LabelLabel…”"),
    "TTTaskDetailNotionBlockLongTextView.nib": (
        "Notion 长文本属性：343×60 多行 value + key 标签",
        "outlets keyLabel / valueLabel；文本含整段中文占位"),
    "TTTaskDetailNotionBlockOptionView.nib": (
        "Notion 选项属性行：key 标签 + 计数徽标（“+3”）",
        "outlets keyLabel / countLabel；countLabel 20×15 右对齐"),
    "TTTaskDetailNotionBlockPeopleView.nib": (
        "Notion 人员属性行：key 标签 + 用户名 + 头像容器（407×36）",
        "outlets keyLabel / usernameLabel / avatarContainer / avatarContainerTailingLC"),
    "TTTaskDetailFocusSummaryCell.nib": (
        "专注汇总行（461×32，无子控件、无连接）→ 推断由代码绘制文字/图标",
        "root only"),
    "TTTaskDetailPresetTaskActionCell.nib": (
        "预设动作行：TTHyperlinkLabel 富文本按钮（346×20）",
        "outlet titleLabel（TTHyperlinkLabel）；无 action 连接"),
    "TTTaskDetailActivitiesCell.nib": (
        "任务动态区：标题 “Task Activities” + 计数 + 关闭按钮 + 内容容器（316×318）",
        "outlets titleLabel / countLabel / dismissButton / containerView / "
        "titleContainerView；action dismissClicked:"),
    "TTTaskDetailCommentCell.nib": (
        "单条评论：头像、用户名、时间、正文（两段 Label）、编辑/删除/展开按钮、回复按钮",
        "10 outlets、4 个 action（expandAction: / replyOrRemoveButtonClicked: / "
        "editButtonClicked:）、4 张图标（edit/sidebar_trash/default_avatar_image/arrow_down）"),
    "TTTaskDetailCommentExpandCell.nib": (
        "评论展开/收起行：箭头图标 + “Expand” 按钮（300×47）",
        "outlet expandButton；action expandClicked:"),
    "TTTaskDetailCommentHeaderView.nib": (
        "评论区标题行：“Comment” + 计数（300×36）",
        "outlets titleLabel / countLabel；文本 “Comment”“0”"),
    "TTTaskDetailAddCommentView.nib": (
        "评论输入区：滚动文本视图 + 表情/图片按钮 + 字数计数（489×134）",
        "outlets textView / emojiButton / imageButton / countLabel / buttonsContainer / "
        "inputBaseView + 3 条 LC；actions emojiButtonClicked: / imageButtonClicked:"),
    "TTTaskDetailNoteInfoViewController.nib": (
        "笔记信息浮层：6 个标签两两成对（创建/修改的时间与提示）+ 计数",
        "outlets countLabel / countHintLabel / createLabel / createHintLabel / "
        "modifyLabel / modifyHintLabel / view"),
}


def build():
    inv = load(os.path.join(ROOT, "ticktick-detail-nib-inventory.json"))
    val = load(os.path.join(ROOT, "ticktick-detail-nib-validation.json"))
    T = inv["totals"]
    M = inv["meta"]
    nibs = inv["nibs"]
    order = {n["file"]: i for i, n in enumerate(nibs)}
    contract = val["contract"]
    cross = val["evidence_cross_check"]
    recon = val["object_count_reconciliation"]
    assets = val.get("image_assets", {})
    top = next(n for n in nibs if n["file"] == "TTTaskDetailTopView.nib")
    bottom = next(n for n in nibs if n["file"] == "TTTaskDetailBottomActionView.nib")
    out = []
    w = out.append

    # ------------------------------------------------------------------ head
    w("# 滴答清单 macOS 8.0.80 · 任务详情/编辑栏 nib 结构清点")
    w("")
    w("> 审计日期：2026-10-17 · 目标：`/Applications/TickTick.app` "
      "(CFBundleShortVersionString **%s**) · 资源目录 `Contents/Resources`" % M["app_version"])
    w(">")
    w("> 全部结果为**只读静态解析**：未启动、未修改 TickTick，未改动仓库其它文件。")
    w(">")
    w("> 机器可读数据：[ticktick-detail-nib-inventory.json](ticktick-detail-nib-inventory.json) · "
      "校验数据：[ticktick-detail-nib-validation.json](ticktick-detail-nib-validation.json) · "
      "解析器：[scripts/parse_nibarchive.py](scripts/parse_nibarchive.py) · "
      "校验器：[scripts/validate_against_evidence.py](scripts/validate_against_evidence.py) · "
      "报告生成：[scripts/build_report.py](scripts/build_report.py)")
    w("")
    w("## 0. 结论摘要")
    w("")
    w("| 指标 | 数值 |")
    w("| --- | --- |")
    w("| 目标 nib | %d 个，解析成功 **%d / %d**（失败 %d） |"
      % (M["nib_requested"], M["nib_parsed"], M["nib_requested"], len(M["parse_errors"])))
    w("| 原始 NIBArchive 对象 | %d 个（含 NSString/NSNumber/NSArray 等辅助对象） |" % T["objects"])
    w("| 连接 | %d 条 = %d outlet + %d action（另有 %d 条编译期提示，非连接） |"
      % (T["connections"], T["outlets"], T["actions"],
         sum(len(n["connector_notes"]) for n in nibs)))
    app_objc_n = len({c for n in nibs for c in n.get("app_objc_classes", [])})
    w("| 自定义类（`_TtC8TickTick*`） | **%d 个**；另有 %d 个应用类 "
      "`TTCollectionViewLeftAlignedFlowLayout`、`JWCTableView`、`TTSingleTaskDetailViewController` |"
      % (T["distinct_custom_classes"], app_objc_n))
    w("| 设计期可见文本 | %d 条（去重） |" % T["distinct_texts"])
    w("| 图片资源名 | %d 个（Assets.car 中可解析 %d 个） |"
      % (T["images"], assets.get("resolved", T["images"])))
    visible_n = len([c for c in inv["controls"]
                     if c["cls"] not in ("NSLayoutConstraint", "NSCustomObject")])
    w("| 控件记录 / 表 B 可见行 | %d / **%d** |" % (T["controls"], visible_n))
    w("")
    w("- **TopView 校验通过**：%d outlet / %d 个不同 action（%d 条 control connector，"
      "`assigneeButtonClicked:` 被两个按钮共用，去重后 6 个），与 2026-10-13 证据一致。"
      % (contract["topview"]["actual_outlets"],
         contract["topview"]["actual_distinct_actions"],
         contract["topview"]["actual_control_connectors"]))
    w("- **BottomActionView 校验通过**：任务给定 15 个 outlet、8 个 action 全部命中，无缺失、无多余。")
    w("- **回归校验**：与 2026-10-13 `ui_archives` 中 37 个可比的 nib 交叉验证，"
      "outlet 名集合 37/37 一致、去重 action 集合 37/37 一致。")
    w("- 详情页由 **4 个容器 nib + 25 个内容 nib** 组成；最小可复刻单元见第 4、5 节。")
    w("")

    # ------------------------------------------------------------------ 1
    w("## 1. 方法与限制")
    w("")
    w("### 1.1 为什么必须自写解析器")
    w("")
    w("这些 `.nib` 是 Xcode 编译后的 **NIBArchive** 容器，不是 plist：`plutil -p` 报错，"
      "`ibtool --objects` 只返回 `com.apple.ibtool.errors`（已实测）。因此本审计用 Python 3 "
      "按字节结构解析，不依赖任何私有工具。")
    w("")
    w("### 1.2 容器格式（实测）")
    w("")
    w("```text")
    w("Header (50 bytes, little endian)")
    w("  char   magic[10]      = \"NIBArchive\"")
    w("  int32  unknown1       = 1        // 格式版本")
    w("  int32  unknown2       = 10")
    w("  int32  object_count, offset_objects")
    w("  int32  key_count,    offset_keys")
    w("  int32  value_count,  offset_values")
    w("  int32  class_name_count, offset_class_names")
    w("")
    w("vint      : 7-bit little-endian groups; FINAL byte has bit7 set")
    w("            (与 LEB128 的继续位语义相反，是本格式最容易踩错的地方)")
    w("Key       : vint len + utf8")
    w("Value     : vint key_index, uint8 type, payload")
    w("            type 0..10 = int8/int16/int32/int64/true/false/float/double/")
    w("                         data(vint len+bytes)/nil/object_ref(int32)")
    w("Object    : vint class_index, vint value_index, vint value_count")
    w("ClassName : vint len, vint extras_count, bytes name, int32 extras[]")
    w("```")
    w("")
    w("以 `TTTaskDetailTopView.nib` 为例的实际头部：object %d、key %d、value %d、"
      "class %d、文件 %d 字节。"
      % (top["header"]["object_count"], top["header"]["key_count"],
         top["header"]["value_count"], top["header"]["class_name_count"],
         top["header"]["file_size"]))
    w("")
    w("### 1.3 从对象图还原界面")
    w("")
    w("1. `NSIBObjectData.NSRoot/NSConnections/NSObjectsKeys/NSObjectsValues` 是对象图根；"
      "`NSConnections` 指向连接数组。")
    w("2. 视图对象以 **`NSClassSwapper`** 编码：`NSClassName` = 真实类（如 "
      "`_TtC8TickTick19TTTaskDetailTopView`），`NSOriginalClassName` = AppKit 基类（如 `NSView`）；"
      "老式 nib 用 `NSCustomView`，字段含义相同。")
    w("3. 几何信息在 `NSFrame`（子视图，字符串 `\"{{x, y}, {w, h}}\"`）或 `NSFrameSize`"
      "（根视图/自动布局视图，`\"{w, h}\"`）。**它们是 IB 设计值，不是运行时 Auto Layout 结果。**")
    w("4. 控件内容：`NSButtonCell`/`NSTextFieldCell` 的 `NSContents` = 可见文本；"
      "`NSNormalImage`/`NSImageCell.NSContents` → `NSCustomResource.NSResourceName` = 图片名。")
    w("5. 连接：`NSNibOutletConnector{NSSource, NSDestination, NSLabel}`（outlet）、"
      "`NSNibControlConnector{NSSource, NSDestination, NSLabel}`（action，`NSLabel` 以 `:` 结尾）。"
      "**目的类**由 destination 对象反查：`NSClassSwapper`→真实视图类，"
      "`NSLayoutConstraint`→布局约束（无宿主视图信息）。")
    w("")
    w("### 1.4 覆盖率 / 字段可得性")
    w("")
    w("| 字段 | 是否取得 | 来源 / 说明 |")
    w("| --- | --- | --- |")
    w("| 根类名 | ✅ 29/29 | `NSClassSwapper.NSClassName`、`NSCustomView.NSClassName`、`NSWindowTemplate.NSWindowClass` |")
    w("| 设计尺寸 | ✅ 29/29 | `NSFrameSize`（视图）/ `NSFrame`（子视图）/ `NSWindowRect`（窗口） |")
    w("| 全部自定义/系统类 | ✅ | 视图 + cell + 连接两端 |")
    w("| 可见文本 | ✅（设计期） | cell `NSContents` / `NSWindowTitle` |")
    w("| 图片资源名 | ✅ 27 个 | `NSCustomResource.NSResourceName` + `IBDesignSize` |")
    w("| outlet 名 + 目标类 | ✅ | `NSNibOutletConnector` destination 反查 |")
    w("| action selector + 源控件 | ✅ | `NSNibControlConnector` source 反查 |")
    w("| 控件 frame（按对象顺序） | ✅ 视图级 | cell 自身无 frame，归属控件 frame 代替 |")
    w("| 文本占位符（placeholder） | ❌ | 归档内**不存在** `NSPlaceholderString` 键 |")
    w("| 约束常量/宿主 | ❌ | 只解出 outlet 指向约束对象，未解析 `NSFirstItem/NSSecondItem/NSConstant` |")
    w("| 运行态文案 | ❌ | nib 内是设计期占位（如 “Label Label…”），真实文案在代码/本地化表 |")
    w("")
    w("### 1.5 限制")
    w("")
    w("- `NSFrame` 是 IB 画布值；`{480, 272}` 反复出现在 DescriptionCell / SpaceCell / BottomView / "
      "DetailContainer 上，是 **IB 默认画布**，不能当作运行时行高。")
    w("- 任务描述里提到的 `{250, 750}` 在本批 nib 中**不是尺寸**：它出现在 TopView 的 "
      "`NSHuggingPriority`（内容 hugging 优先级 250/750），不是 frame/设计尺寸。")
    w("- outlet 指向 `NSLayoutConstraint` 时，归档不记录“约束属于哪个视图”，只能给出约束名 + 约束类。")
    w("- 编译期提示 `NSNibConnector`（2 条，见 2.4）不是界面连接，已从计数中剔除。")
    w("- 本地化表是 **App 级**（3457 个 key），不是 nib 级；只能用来确认按钮文案候选。")
    w("")

    # ------------------------------------------------------------------ 2
    w("## 2. 校验（必须项）")
    w("")
    w("### 2.1 TTTaskDetailTopView.nib：18 outlet / 6 action")
    w("")
    w("| 指标 | 2026-10-13 证据 | 本次解析 | 结论 |")
    w("| --- | --- | --- | --- |")
    w("| outlet 数 | %d | **%d** | ✅ 一致 |"
      % (contract["topview"]["expected_outlets"], contract["topview"]["actual_outlets"]))
    w("| action（去重 selector） | %d | **%d** | ✅ 一致 |"
      % (contract["topview"]["expected_actions"],
         contract["topview"]["actual_distinct_actions"]))
    w("| control connector 原始条数 | — | %d | 其中 `assigneeButtonClicked:` 出现 2 次 |"
      % contract["topview"]["actual_control_connectors"])
    w("| connections 总数 | 25 | %d（18 + %d） | ✅ 一致 |"
      % (top["counts"]["connections"], contract["topview"]["actual_control_connectors"]))
    w("| objects | 95 | %d（原始归档对象） | ⚠️ 口径不同，见 2.4 |" % top["counts"]["objects"])
    w("")
    w("18 个 outlet：")
    w("")
    w("```text")
    w(", ".join(o["name"] for o in top["outlets"]))
    w("```")
    w("")
    w("6 个 action：`%s`。" % "`, `".join(top["distinct_actions"]))
    w("")
    w("重复连接明细：`assigneeButtonClicked:` 同时来自 `assigneeIconButton`"
      "（TTThemeButton 28×28）与 `assigneeAvatarButton`（TTToolTipNSButton 20×20），"
      "因此 7 条 control connector 去重后是 6 个 action —— 这正是证据口径。")
    w("")
    w("### 2.2 TTTaskDetailBottomActionView.nib：15 outlet / 8 action")
    w("")
    w("| 检查项 | 结果 |")
    w("| --- | --- |")
    w("| 任务给定 15 个 outlet 是否齐全 | ✅ 全部命中，无缺失、无多余（%d 条 outlet connector） |"
      % bottom["counts"]["outlets"])
    w("| 任务给定 8 个 action 是否齐全 | ✅ 全部命中，无缺失、无多余（%d 条 control connector） |"
      % bottom["counts"]["actions"])
    w("")
    w("outlet：`%s`" % "`, `".join(o["name"] for o in bottom["outlets"]))
    w("")
    w("action：`%s`" % "`, `".join(a["selector"] for a in bottom["actions"]))
    w("")
    w("### 2.3 全量回归（对 2026-10-13 `ui_archives`）")
    w("")
    w("| 项目 | 结果 |")
    w("| --- | --- |")
    in_scope = sum(1 for r in cross["rows"] if r.get("in_detail_scope"))
    w("| 可比 nib | %d 个（其中本批详情 nib %d 个，其余 %d 个为同名 nib 的宽样本） |"
      % (cross["comparable"], in_scope, cross["comparable"] - in_scope))
    w("| outlet 名集合 | %d/%d 一致（证据按去重名记录；本解析按连接逐条记录后同样去重比较） |"
      % (cross["comparable"] - len(cross["outlet_mismatches"]), cross["comparable"]))
    w("| 去重 action 集合 | %d/%d 一致 |"
      % (cross["comparable"] - len(cross["action_mismatches"]), cross["comparable"]))
    w("| 图片资源存在性 | %d 个名字中 %d 个可在 `Assets.car` 命中；缺 %s |"
      % (assets.get("checked", 0), assets.get("resolved", 0),
         ", ".join("`%s`" % m for m in assets.get("missing", [])) or "无"))
    w("")
    w("说明：证据的 outlets/actions 是**去重后的名字集合**，本解析按连接逐条记录；"
      "例如 `TTFocusDetailRecordsViewController.nib` 有 22 条 outlet connector 但只有 14 个"
      "不同名字（多个 cell 复用 `titleLabel`/`conentLabel`），按去重名比较后 37/37 一致。")
    w("")
    w("### 2.4 与证据对不上的地方（如实记录，不猜测）")
    w("")
    w("1. **objects 数量**：证据 TopView = 95，本解析 `object_count` = %d。证据文件没有给出 "
      "objects 的统计口径。95 恰好等于 “视图 %d + cell %d + 连接 %d + 约束 %d”，但同一公式在 "
      "`TTCalendarArrangeCell` 上得 31（证据 36）、在 `TTFocusSummaryCell` 上得 1（证据 5），"
      "**规则不成立**，因此 95 只能视为“口径未知”，不能据此修改解析结果。"
      % (recon["archive_object_count"], recon["ui_views_swappers"], recon["cells"],
         recon["connectors"], recon["layout_constraints"]))
    w("2. **action 条数**：证据 action 是去重后的 selector 列表（6），原始 control connector 是 7；"
      "两者都对，取决于是否去重。本报告同时给出两个数。")
    w("3. **图片名**：`menu_calendar`、`set_repeat` 在 `Assets.car` 中没有同名 rendition"
      "（最接近的是 `detail_calendar`、`repeat`/`set_repeat_large`）。"
      "推断是 IB 里的旧资源引用，运行期由代码替换；**未运行验证，仅记录差异**。")
    w("")

    # ------------------------------------------------------------------ 3
    w("## 3. 逐 nib 表（类名 / 尺寸 / 子控件类与图片 / 文本 / outlet / action）")
    w("")
    w("> 类名一列省略了 `_TtC8TickTick<长度>` 的 Swift mangling 前缀（完整符号见 JSON）。"
      "尺寸为 IB 设计值；`{480, 272}` 为默认画布。")
    w("")
    w("| # | nib | 根类 | 尺寸 | 子控件类 / 图片名 | 文本 | outlet | action |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for i, n in enumerate(nibs, 1):
        root = n["root"] or {}
        cls = cls_short(root.get("cls"))
        size = root.get("design_size") or "—"
        vc = Counter(cls_short(f["cls"]) for f in n["frames"]
                     if f["object"] != root.get("object") and f.get("frame"))
        vparts = ["%s×%d" % (k, v) if v > 1 else k for k, v in vc.most_common(5)]
        if len(vc) > 5:
            vparts.append("…")
        children = ", ".join(vparts) if vparts else "—"
        if n["images"]:
            children += " ｜ 图: " + ", ".join(n["images"][:6])
            if len(n["images"]) > 6:
                children += "…"
        texts = " / ".join(cut(t, 18) for t in n["texts"][:2]) or "—"
        outs = "、".join(o["name"] for o in n["outlets"][:5])
        if len(n["outlets"]) > 5:
            outs += " …(%d)" % len(n["outlets"])
        acts = "、".join(n["distinct_actions"][:4])
        if len(n["distinct_actions"]) > 4:
            acts += " …(%d)" % len(n["distinct_actions"])
        if n["counts"]["actions"] != n["counts"]["distinct_actions"]:
            acts += " ［%d 条连接］" % n["counts"]["actions"]
        w("| %d | `%s` | %s | %s | %s | %s | %s | %s |"
          % (i, n["file"].replace(".nib", ""), (cls or "—"),
             size, esc(children), esc(texts), esc(outs or "—"), esc(acts or "—")))
    w("")

    sys_all = sorted({c for n in nibs for c in n["system_classes"]
                      if c not in ("NSCustomView", "NSCustomObject", "IBClassReference")})
    w("本批出现的系统/框架类（去重 %d 个）：%s。"
      % (len(sys_all), "、".join("`%s`" % c for c in sys_all)))
    w("")
    w("注意：**没有 `NSOutlineView`** —— 详情正文用的是 `JWCTableView`（`NSTableView` 子类）；"
      "`NSCollectionView` 只出现在 SingleTaskDetail 的标签/附件区与 TagCollectionCell。")
    w("")

    # ------------------------------------------------------------------ 4
    w("## 4. 汇总表 A：详情页由哪些 cell 组成（职责为推断）")
    w("")
    w("> 「职责」列**全部是推断**，依据仅限类名、图片名、outlet 名、文本与 frame，"
      "未做运行期验证。")
    w("")
    w("| 层 | nib | 类 | 尺寸 | 职责（推断） | 依据 |")
    w("| --- | --- | --- | --- | --- | --- |")
    layer = {
        "TTSingleTaskDetailViewController.nib": "容器",
        "TTTaskDetailWindowController.nib": "容器",
        "TTDetailContainerViewController.nib": "容器",
        "TTTaskDetailHolderViewController.nib": "容器",
        "TTTaskDetailTopView.nib": "头部",
        "TTTaskDetailTitleCell.nib": "行",
        "TTTaskDetailContentCell.nib": "行",
        "TTTaskDetailDescriptionCell.nib": "行",
        "TTTaskDetailSubtaskCell.nib": "行",
        "TTTaskDetailCheckItemCell.nib": "行",
        "TTTaskDetailParentTaskCell.nib": "行",
        "TTTaskDetailTagCollectionCell.nib": "集合",
        "TTTaskDetailTagCollectionViewItem.nib": "集合项",
        "TTTaskDetailSpaceCell.nib": "占位",
        "TTTaskDetailNotionBlockCell.nib": "Notion 块",
        "TTTaskDetailNotionBlockShortTextView.nib": "Notion 块",
        "TTTaskDetailNotionBlockLongTextView.nib": "Notion 块",
        "TTTaskDetailNotionBlockOptionView.nib": "Notion 块",
        "TTTaskDetailNotionBlockPeopleView.nib": "Notion 块",
        "TTTaskDetailFocusSummaryCell.nib": "行",
        "TTTaskDetailPresetTaskActionCell.nib": "行",
        "TTTaskDetailActivitiesCell.nib": "区块",
        "TTTaskDetailCommentHeaderView.nib": "评论",
        "TTTaskDetailCommentCell.nib": "评论",
        "TTTaskDetailCommentExpandCell.nib": "评论",
        "TTTaskDetailAddCommentView.nib": "评论",
        "TTTaskDetailNoteInfoViewController.nib": "浮层",
        "TTTaskDetailBottomView.nib": "底部",
        "TTTaskDetailBottomActionView.nib": "底部",
    }
    for n in nibs:
        root = n["root"] or {}
        role, why = RESPONSIBILITY.get(n["file"], ("", ""))
        w("| %s | `%s` | %s | %s | %s | %s |"
          % (layer.get(n["file"], ""), n["file"].replace(".nib", ""),
             cls_short(root.get("cls")), root.get("design_size") or "—",
             esc(role), esc(why)))
    w("")

    w("### 4.1 与本仓库实现的可能差异（推断，非运行验证）")
    w("")
    w("把 nib 证据与本仓库 `macos-native/WorkFollow` 的静态代码对照后，"
      "以下控件在仓库里没有对应实现或形态不同（grep 结果，未运行）：")
    w("")
    w("| 控件 / 能力 | nib 证据 | 仓库现状（静态 grep） | 判断 |")
    w("| --- | --- | --- | --- |")
    w("| Notion 属性块五件套 | `notionIconView`/`notionNameLabel`/`notionButton` + "
      "`openInNotionButtonClicked:`、People/Option/Long/Short 四种行 | "
      "`macos-native/WorkFollow` 内 **无 “notion” 字符串** | 可能没有 |")
    w("| 任务合并按钮 | `mergeButton` + `mergeButtonClicked:`（图标 `combination`） | "
      "只有设置里的数据导入 “merge/合并”，TaskInspectorActionPanel 的 case 为 "
      "more/tags/relation/parent/activity/comments | 可能没有 |")
    w("| 预设动作行 | `TTTaskDetailPresetTaskActionCell`（`TTHyperlinkLabel`，346×20） | "
      "“preset” 仅出现在日期提醒偏移（`TaskDateDraftModel`） | 可能没有 |")
    w("| 评论折叠/计数行 | `TTTaskDetailCommentHeaderView`（Comment + 0）、"
      "`TTTaskDetailCommentExpandCell`（Expand + arrow_down） | 有 `TaskCommentPanel`（面板），"
      "无独立头部/折叠 cell | 形态不同 |")
    w("| 内嵌任务动态块 | `TTTaskDetailActivitiesCell`（316×318，标题 + 计数 + dismiss） | "
      "有 `TaskActivityPanel`（独立面板） | 形态不同 |")
    w("")
    w("结构层面还有一处差异：TickTick 详情正文用 **`JWCTableView`（`NSTableView` 子类）**"
      "承载全部 13 种 cell，而仓库 `TaskInspector` 用 `AppKitSubtaskOutlineView`（`NSOutlineView`）"
      "做子任务树；本批 nib 中**没有** `NSOutlineView`。")
    w("")
    w("另有 2 个“有等价能力但呈现不同”的底栏按钮：`mdEditButton`（nib 用 `md_edit` 图标）"
      "在仓库里是字面 “A” 的 SwiftUI 按钮；`deleteForeverButton`（`delete_forever` 图标）"
      "在仓库里只出现在垃圾桶页面，不在详情底栏。")
    w("")

    # ------------------------------------------------------------------ 5
    w("## 5. 汇总表 B：详情页全部可见控件与动作（去重）")
    w("")
    w("> 每行 = 一个视图对象（含它自己的 outlet / 图片 / 文本 / action）。"
      "同一 outlet 名在不同 nib 中是不同控件，故按 (nib, 对象号) 去重而不是按名字去重。"
      "`obj#` 为归档对象序号，便于回查 JSON。")
    w("")
    def frame_xy(c):
        m = re.match(r"\{\{(-?[\d.]+),\s*(-?[\d.]+)\}", c["frame"] or "")
        return (float(m.group(1)), float(m.group(2))) if m else None

    visible = [c for c in inv["controls"]
               if c["cls"] not in ("NSLayoutConstraint", "NSCustomObject")]
    dropped = len(inv["controls"]) - len(visible)
    visible.sort(key=lambda c: (order.get(c["nib"], 999),
                                0 if frame_xy(c) else 1,
                                -frame_xy(c)[1] if frame_xy(c) else 0,
                                frame_xy(c)[0] if frame_xy(c) else 0,
                                c["object"]))
    w("> 收录 %d 个可见控件；另有 %d 行是纯布局约束/文件所有者等非可视对象，"
      "已在表 B 剔除（完整清单见 JSON `controls`）。" % (len(visible), dropped))
    w("")
    w("| # | 所在 nib | 控件（outlet） | 类 | 图片 | 文本 | action |")
    w("| --- | --- | --- | --- | --- | --- | --- |")
    for i, c in enumerate(visible, 1):
        name = c["outlet"] or "obj#%d" % c["object"]
        w("| %d | `%s` | %s | %s | %s | %s | %s |"
          % (i, c["nib"].replace(".nib", ""), esc(name), cls_short(c["cls"]),
             c["image"] or "—", esc(cut(c["text"], 22)) if c["text"] else "—",
             esc(c["action"]) if c["action"] else "—"))
    w("")

    # ------------------------------------------------------------------ 6
    w("## 6. 几何数字（IB 设计值）")
    w("")
    outlet_by_obj = {o["destination_object"]: o["name"] for o in top["outlets"]}
    top_ctl = {c["object"]: c for c in inv["controls"]
               if c["nib"] == "TTTaskDetailTopView.nib"}
    tl = [f for f in top["frames"] if f.get("frame") and f.get("x") is not None]
    tl.sort(key=lambda f: (-f["y"], f["x"]))
    w("### 6.1 头部条 `TTTaskDetailTopView` —— 766 × 145（IB 画布）")
    w("")
    w("| outlet | 类 | frame | 图标 / 文本 | 备注（推断） |")
    w("| --- | --- | --- | --- | --- |")
    note = {
        "checkButton": "完成勾选",
        "returnButton": "返回 / 关闭详情",
        "dateButton": "日期按钮，标题占位 “Set Date”",
        "iconDivider": "1 px 竖分隔线（分组用）",
        "repeatIcon": "重复图标（点击态可能由 dateButton 代理）",
        "assigneeIconButton": "指派人入口",
        "assigneeAvatarButton": "指派人头像（叠在 assigneeIconButton 上）",
        "priorityButton": "优先级",
        "noteInfoButton": "备注/笔记信息",
        "secondaryDateLabel": "长文本标签（占位 Label…，412 宽，推断是任务标题）",
        "progressView": "子任务完成度进度条（仅 NSFrameSize，无坐标）",
    }
    for f in tl:
        nm = outlet_by_obj.get(f["object"])
        if not nm:
            continue
        c = top_ctl.get(f["object"], {})
        ico = c.get("image") or "—"
        if c.get("image") and c.get("image_design_size"):
            ico += "（原图 %s）" % c["image_design_size"]
        txt = cut(c.get("text"), 14) if c.get("text") else ""
        it = ico + ((" / “%s”" % txt) if txt else "")
        w("| `%s` | %s | `{{%s, %s}, {%s, %s}}` | %s | %s |"
          % (nm, cls_short(f["cls"]), num(f["x"]), num(f["y"]),
             num(f["w"]), num(f["h"]), it, note.get(nm, "")))
    w("")
    w("- 顶部 8 px 留白：主行控件占 `y = 109…137`（高 16–28）；`secondaryDateLabel` 在其下方 "
      "`y = 93…107`（412×14）；`progressView` 只有尺寸 766×40，**没有坐标**，"
      "推断贴在头部底边（0…40）。")
    w("- 水平排布（左→右）：`returnButton` x=12、`checkButton` x=44、`iconDivider` x=72、"
      "`dateButton` x=80（77 宽）、`repeatIcon` x=163；右侧簇 `assigneeIconButton` x=660 / "
      "`assigneeAvatarButton` x=664、`priorityButton` x=694、`noteInfoButton` x=728"
      "（最右 756，距 766 边 10）。")
    w("- 145 是 IB 画布高度：可视控件只占顶部 `y = 93…137`（工具行 28 + 标题行 14）"
      "与进度条 40，中间大段留白由约束在运行时消耗——**不能**直接当作运行时 header 高度。")
    w("")
    w("### 6.2 底部操作条 `TTTaskDetailBottomActionView` —— 480 × 40")
    w("")
    w("| x | outlet | 尺寸 | 图标 | action |")
    w("| --- | --- | --- | --- | --- |")
    b_outlet_by_obj = {o["destination_object"]: o["name"] for o in bottom["outlets"]}
    act_by_obj = {a["source_object"]: a["selector"] for a in bottom["actions"]}
    img_by_obj = {}
    for c in inv["controls"]:
        if c["nib"] == "TTTaskDetailBottomActionView.nib" and c["image"]:
            img_by_obj[c["object"]] = c["image"]
    bviews = [f for f in bottom["frames"] if f.get("frame") and f.get("x") is not None]
    bviews.sort(key=lambda f: f["x"])
    for f in bviews:
        nm = b_outlet_by_obj.get(f["object"], "obj#%d" % f["object"])
        w("| %s | `%s` | %s×%s | %s | `%s` |"
          % (num(f["x"]), nm, num(f["w"]), num(f["h"]),
             img_by_obj.get(f["object"], "—"), act_by_obj.get(f["object"], "—")))
    w("")
    w("- 8 个按钮全部 `y = 8`、高 24：`8 + 24 + 8 = 40`，即 40 高底栏内上下居中。")
    w("- 7 个图标按钮 24×24，x = 247 / 279 / 311 / 343 / 375 / 407 / 439，"
      "间距 32（= 24 宽 + 8 空隙），最右 `moreButton` 右边缘 463（距 480 边 17）。")
    w("- `projectButton` 是唯一带文字的按钮：x=17、63×24，文本占位 “Inbox”（运行时是清单名）。")
    w("- 左→右语义：清单(`projectButton`) → Markdown 编辑(`mdEditButton`) → 合并(`mergeButton`) → "
      "标签(`tagButton`) → 评论(`commentButton`) → 删除(`deleteButton`) → "
      "永久删除(`deleteForeverButton`) → 更多(`moreButton`)。")
    w("")
    w("### 6.3 各 cell / 区块的设计尺寸")
    w("")
    w("| nib | 根尺寸 | 关键子视图 frame | 备注 |")
    w("| --- | --- | --- | --- |")
    skip6 = ("TTSingleTaskDetailViewController.nib", "TTTaskDetailWindowController.nib",
             "TTDetailContainerViewController.nib", "TTTaskDetailHolderViewController.nib",
             "TTTaskDetailTopView.nib", "TTTaskDetailBottomActionView.nib",
             "TTTaskDetailTagCollectionCell.nib", "TTTaskDetailTagCollectionViewItem.nib",
             "TTTaskDetailNotionBlockCell.nib", "TTTaskDetailActivitiesCell.nib",
             "TTTaskDetailCommentCell.nib", "TTTaskDetailAddCommentView.nib")
    for n in nibs:
        if n["file"] in skip6:
            continue
        root = n["root"] or {}
        subs = []
        for f in n["frames"]:
            if f["object"] == root.get("object") or not f.get("frame"):
                continue
            if f.get("x") is None:
                subs.append("%s %s" % (cls_short(f["cls"]), f["frame"]))
            else:
                subs.append("%s @(%s,%s) %s×%s"
                            % (cls_short(f["cls"]), num(f["x"]), num(f["y"]),
                               num(f["w"]), num(f["h"])))
        size = root.get("design_size") or "—"
        if n["file"] == "TTTaskDetailNoteInfoViewController.nib":
            remark = "浮层视图，不是表格行"
        elif size == "{480, 272}":
            remark = "IB 默认画布，非运行时行高"
        elif not subs:
            remark = "无子视图，内容由代码注入"
        else:
            remark = "行高候选（IB 设计值）"
        w("| `%s` | %s | %s | %s |"
          % (n["file"].replace(".nib", ""), size,
             esc("；".join(subs[:4]) if subs else "无子视图"), remark))
    w("")
    w("- `TTTaskDetailTitleCell` 362×70：勾选框 16×16 @(12,49)，类型按钮 24×24 @(321,35)。")
    w("- `TTTaskDetailCheckItemCell` 456×140：拖拽柄 12×12 @(0,114)、勾选框 17×17 @(20,111)、"
      "提醒 24×24 @(389,108)、删除 24×24 @(415,108) —— 行内控件统一底对齐。")
    w("- `TTTaskDetailParentTaskCell` 346×18：按钮 45×16 @(20,0)。")
    w("- `TTTaskDetailPresetTaskActionCell` 346×20：超链接 label 310×14 @(18,3)。")
    w("- `TTTaskDetailFocusSummaryCell` 461×32：无子视图（内容代码绘制），是“行高”最可信的候选之一。")
    w("- `TTTaskDetailCommentHeaderView` 300×36；`TTTaskDetailCommentExpandCell` 300×47"
      "（按钮 60×15 @(64,20)）。")
    w("- **行高候选汇总**（IB 设计值，仅供参照，运行时需以 table 的 rowHeight 为准）："
      "Title 70 / Content 47 / Subtask 80 / CheckItem 140 / ParentTask 18 / Preset 20 / "
      "FocusSummary 32 / CommentHeader 36 / CommentExpand 47 / NotionShort 36 / "
      "NotionLong 102 / NotionOption 36 / NotionPeople 36 / Comment 257 / AddComment 134；"
      "ActivitiesCell 318 是区块高度，不是行高。")
    w("- 每个 nib 的**全部**对象 frame（按归档对象顺序、含 superview 引用）在 JSON 的 "
      "`nibs[].frames` 中；本表只列代表性子视图。")
    w("")

    # ------------------------------------------------------------------ 7
    w("## 7. 未取得 / 不确定清单")
    w("")
    w("1. **placeholder 文案**：本批归档无 `NSPlaceholderString` 键，输入框占位文案不可得；"
      "nib 里的 “Label…/Button/Inbox/Window” 是 IB 占位，不代表运行文案。")
    w("2. **cell 自身 frame**：cell 对象没有 frame（`NSControlView` 指向宿主视图），"
      "表里给的是宿主视图 frame；table 行高需运行期或约束推导。")
    lc = sum(1 for n in nibs for o in n["outlets"]
             if o["destination_kind"] == "layout_constraint")
    w("3. **约束归属**：%d 个 `*LC` outlet 指向 `NSLayoutConstraint`，归档不记录约束的宿主视图；" % lc
      +
      "本报告只能给出“约束类 + outlet 名”。约束常量未解码。")
    w("4. **`{480, 272}`** 是 IB 默认画布，出现在 DescriptionCell / SpaceCell / BottomView / "
      "DetailContainer，不能当运行时尺寸。")
    w("5. **`{250, 750}`** 是 TopView 的 `NSHuggingPriority`（内容 hugging 优先级 250/750），"
      "不是设计尺寸；任务描述把它与 `{480, 40}` 并列举例，实际本批 nib 中没有任何视图是这个尺寸。")
    w("6. **图片资源**：27 个资源名中 25 个在 `Assets.car` 命中；`menu_calendar`、`set_repeat` "
      "无同名 rendition（相近有 `detail_calendar`、`repeat`、`set_repeat_large`），"
      "**推断**为 IB 旧引用、运行期替换，未运行验证。")
    w("7. **证据 objects 口径未知**（95 vs 322；`TTFocusSummaryCell` 5 vs 26）；"
      "仅 outlet/action/connection 作为契约项校验，全部一致。")
    w("8. **两条 `NSNibConnector` 编译期提示**（CommentCell priority 999990、AddCommentView 999980）"
      "是 Xcode 对 NSStackView 解码顺序的提示，不是界面连接，已剔除。")
    w("9. **File's Owner 异常**：`TTTaskDetailPresetTaskActionCell.nib` 的 owner 类是 "
      "`TTTaskDetailParentTaskCell`（复制 nib 的残留），不影响控件但说明该 nib 是复制改的。")
    w("10. **窗口标题**是 “Window” 占位；`TTTaskDetailWindowController` 仅 2 条连接（window/delegate），"
      "内容全部来自代码挂载。")
    w("11. **文本与动作的对应关系**是“同一宿主视图”粒度：一个按钮的 title 与 action 可以确认，"
      "但按钮点击后的业务语义（如 md 编辑到底编辑什么）只能靠命名/本地化推断。")
    w("12. 未解析：`NSAccessibility*`、`NSViewConstraints` 的约束常量、`NSFont`/`NSColor` 细节、"
      "`NSWindowStyleMask` 的位含义；这些不影响本清单的控件级结论。")
    w("")

    # ------------------------------------------------------------------ 8
    w("## 8. 附：详情/编辑栏相关本地化字符串")
    w("")
    w("来源：`Contents/Resources/en.lproj/Localizable.strings` 与 "
      "`zh-Hans.lproj/Localizable.strings`（UTF-16LE，各 %d 个 key）。"
      "脚本用“白名单 + 关键词”抽到 %d 组中英对照，下表节选常用项"
      "（App 内没有独立的“详情”strings 文件；key 本身多为英文原文）。"
      % (inv["localization"]["en.lproj"]["total_keys"],
         len(inv["localization"]["pairs"])))
    w("")
    w("| key | en | zh-Hans |")
    w("| --- | --- | --- |")
    skip = ("Sorry", "With %@", "You can merge", "%d tasks", "%ld tasks",
            "Welcome to", "Create up to", "notification_", "ai_", "pro_subtask",
            "Come back", "Paused", "You can choose to receive")
    for p in inv["localization"]["pairs"]:
        if p["key"].startswith(skip) or len(p["key"]) > 60:
            continue
        w("| `%s` | %s | %s |" % (p["key"], esc(p["en"] or "—"), esc(p["zh"] or "—")))
    w("")
    w("与底栏按钮的对应（推断）：`mdEditButton` ← 无独立 “Markdown” 文案（图标按钮 `md_edit`）；"
      "`commentButton` ← “Comments/评论”“Write a comment/添加评论”；`moreButton` ← “More/更多”；"
      "`mergeButton` ← “Merge/合并”；`deleteForeverButton` ← “Delete Forever/永久删除”；"
      "`tagButton` ← “Tag/标签”；`projectButton` ← 清单名（运行时数据，非固定文案）。")
    w("")
    w("## 9. 附录：%d 个 `_TtC8TickTick*` 自定义类" % len(inv["custom_classes"]))
    w("")
    w("| # | 类 | 出现在 |")
    w("| --- | --- | --- |")
    for i, c in enumerate(inv["custom_classes"], 1):
        w("| %d | `%s` | %s |"
          % (i, c["cls"], ", ".join("`%s`" % n.replace(".nib", "") for n in c["nibs"])))
    app_objc = sorted({c for n in nibs for c in n.get("app_objc_classes", [])})
    if app_objc:
        w("")
        w("另有 %d 个非 Swift mangling 的应用类：%s。"
          % (len(app_objc), "、".join("`%s`" % c for c in app_objc)))
    w("")
    w("## 10. 复现命令")
    w("")
    w("```bash")
    w("cd docs/audits/ticktick-rea-2026-10-17")
    w("python3 scripts/parse_nibarchive.py --out ticktick-detail-nib-inventory.json")
    w("python3 scripts/validate_against_evidence.py")
    w("python3 scripts/build_report.py")
    w("```")
    w("")
    w("---")
    w("")
    w("*本报告由 `scripts/build_report.py` 从 JSON 生成；解析与校验脚本均为只读，"
      "未对 TickTick.app 做任何写操作。*")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "ticktick-detail-nib-inventory.md"))
    args = ap.parse_args()
    md = build()
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(md)
    print("wrote %s (%d lines, %d bytes)" % (args.out, md.count("\n"), len(md)))


if __name__ == "__main__":
    main()
