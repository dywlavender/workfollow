/* WorkFollow 编辑器：工具条（滴答同款顶部裸条）。
   按钮集 = 2026-10-24 REA 取证（笔记视图）+ 我们独有的 drawio（保留项）：
   A▾字体色 · B · I · U · S · 高亮A ｜ 无序 · 有序 · 清单 ｜
   引用 · 代码(行内) · 代码块 ｜ 图片 · 附件 · 链接 · 表格 · 分割线 · 时间 · 更多(…) ｜ 流程图 */
"use strict";

(function () {
  var SEPARATED_GROUPS = [
    [
      { name: "color", title: "字体颜色", glyph: "A▾" },
      { name: "bold", title: "粗体", glyph: "<span class='wf-letter'>B</span>" },
      { name: "italic", title: "斜体", glyph: "<span class='wf-letter' style='font-style:italic'>I</span>" },
      { name: "underline", title: "下划线", glyph: "<span class='wf-letter' style='text-decoration:underline'>U</span>" },
      { name: "strike", title: "删除线", glyph: "<span class='wf-letter' style='text-decoration:line-through'>S</span>" },
      { name: "highlight", title: "高亮", glyph: "<span class='wf-letter'>A</span>" }
    ],
    [
      { name: "bullet", title: "无序列表", glyph: "•" },
      { name: "ordered", title: "有序列表", glyph: "1." },
      { name: "checklist", title: "清单", glyph: "☑" }
    ],
    [
      { name: "blockquote", title: "引用", glyph: "❝" },
      { name: "code", title: "行内代码", glyph: "{·}" },
      { name: "code-block", title: "代码块", glyph: "{ }" }
    ],
    [
      { name: "image", title: "图片", glyph: "🖼" },
      { name: "attachment", title: "上传附件", glyph: "📎" },
      { name: "link", title: "链接", glyph: "🔗" },
      { name: "table", title: "表格", glyph: "▦" },
      { name: "divider", title: "分割线", glyph: "—" },
      { name: "time", title: "插入当前时间", glyph: "🕐" },
      { name: "more", title: "更多", glyph: "…" }
    ],
    [
      { name: "diagram", title: "流程图（draw.io）", glyph: "◬" }
    ]
  ];

  var MORE_ITEMS = [
    { name: "paragraph", title: "正文" },
    { name: "heading1", title: "一级标题" },
    { name: "heading2", title: "二级标题" },
    { name: "heading3", title: "三级标题" }
  ];

  function buildToolbar(container, handlers) {
    var bar = document.createElement("div");
    bar.id = "wf-toolbar";
    SEPARATED_GROUPS.forEach(function (group, groupIndex) {
      if (groupIndex > 0) {
        var sep = document.createElement("span");
        sep.className = "wf-sep";
        bar.appendChild(sep);
      }
      group.forEach(function (item) {
        var button = document.createElement("button");
        button.className = "wf-btn";
        button.dataset.name = item.name;
        button.title = item.title;
        button.setAttribute("aria-label", item.title);
        button.innerHTML = item.glyph.indexOf("<") === 0 ? item.glyph : "<span class='wf-letter'>" + item.glyph + "</span>";
        if (["image", "attachment", "link", "table", "divider", "time", "more", "diagram"].indexOf(item.name) >= 0) {
          button.addEventListener("click", function (event) {
            event.preventDefault();
            handlers.action(item.name, button);
          });
        } else {
          button.addEventListener("mousedown", function (event) {
            event.preventDefault();          // 保留编辑器选区（Quill 惯例）
          });
          button.addEventListener("click", function (event) {
            event.preventDefault();
            handlers.toggle(item.name, button);
          });
        }
        bar.appendChild(button);
      });
    });
    container.appendChild(bar);
    return bar;
  }

  /** Quill getFormat → 按钮激活态同步。 */
  function syncActive(bar, format) {
    bar.querySelectorAll(".wf-btn").forEach(function (button) {
      var name = button.dataset.name;
      var active = false;
      switch (name) {
        case "bold": active = !!format.bold; break;
        case "italic": active = !!format.italic; break;
        case "underline": active = !!format.underline; break;
        case "strike": active = !!format.strike; break;
        case "highlight": active = !!format.background; break;
        case "bullet": active = format.list === "bullet"; break;
        case "ordered": active = format.list === "ordered"; break;
        case "checklist": active = format.list === "checked" || format.list === "unchecked"; break;
        case "blockquote": active = !!format.blockquote; break;
        case "code": active = !!format.code; break;
        case "code-block": active = !!format["code-block"]; break;
        case "color": active = !!format.color; break;
      }
      button.classList.toggle("active", active);
    });
  }

  window.WorkFollowToolbar = { build: buildToolbar, syncActive: syncActive, moreItems: MORE_ITEMS };
})();
