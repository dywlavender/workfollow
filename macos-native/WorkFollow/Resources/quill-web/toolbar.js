/* WorkFollow 编辑器：工具条（滴答同款顶部裸条）。
   按钮集 = 2026-10-24 REA 取证（笔记视图）+ 我们独有的 drawio（保留项）。
   图标 = 滴答 Assets.car 提取的原版图标（icons/md_*.png），
   图片/表格/流程图为同风格自绘 SVG。 */
"use strict";

(function () {
  function icon(name) {
    return "<img class='wf-icon' src='icons/" + name + "' alt=''>";
  }

  var SEPARATED_GROUPS = [
    [
      { name: "color", title: "字体颜色", glyph: "<span class='wf-letter'>A</span>" + icon("md_arrow_down_alpha57.png") },
      { name: "bold", title: "粗体", glyph: icon("md_bold.png") },
      { name: "italic", title: "斜体", glyph: icon("md_italic.png") },
      { name: "underline", title: "下划线", glyph: icon("md_underline.png") },
      { name: "strike", title: "删除线", glyph: icon("md_strike.png") },
      { name: "highlight", title: "高亮", glyph: icon("md_highlight.png") }
    ],
    [
      { name: "bullet", title: "无序列表", glyph: icon("md_list.png") },
      { name: "ordered", title: "有序列表", glyph: icon("md_orderList.png") },
      { name: "checklist", title: "清单", glyph: icon("md_checkBox.png") }
    ],
    [
      { name: "blockquote", title: "引用", glyph: icon("md_quote.png") },
      { name: "code", title: "行内代码", glyph: icon("md_code.png") },
      { name: "code-block", title: "代码块", glyph: icon("md_code.png") }
    ],
    [
      { name: "image", title: "图片", glyph: icon("wf_image.svg") },
      { name: "attachment", title: "上传附件", glyph: icon("md_attachment.png") },
      { name: "link", title: "链接", glyph: icon("md_link.png") },
      { name: "table", title: "表格", glyph: icon("wf_table.svg") },
      { name: "divider", title: "分割线", glyph: icon("md_horizontal.png") },
      { name: "time", title: "插入当前时间", glyph: icon("md_time.png") },
      { name: "more", title: "更多", glyph: icon("md_more.png") }
    ],
    [
      { name: "diagram", title: "流程图（draw.io）", glyph: icon("wf_diagram.svg") }
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
        button.innerHTML = item.glyph;
        if (item.name === "color") {
          button.addEventListener("mousedown", function (event) { event.preventDefault(); });
          button.addEventListener("click", function (event) {
            event.preventDefault();
            if (handlers.colorMenu) handlers.colorMenu(button);
          });
        } else if (["image", "attachment", "link", "table", "divider", "time", "more", "diagram"].indexOf(item.name) >= 0) {
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
