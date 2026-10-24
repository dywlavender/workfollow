/* WorkFollow 编辑器：斜杠菜单（滴答 13 项 + 我们独有的流程图 = 14 项）。
   菜单项与 2026-10-24 REA 取证的滴答斜杠菜单逐条对齐；
   图标用滴答 Assets.car 原版（icons/md_*.png），图片/表格/流程图为同风格自绘 SVG。 */
"use strict";

(function () {
  function icon(name) {
    return "<img class='wf-slash-img' src='icons/" + name + "' alt=''>";
  }

  var GROUPS = [
    [
      { name: "paragraph", title: "文本", glyph: icon("md_body.png") },
      { name: "heading1", title: "标题1", glyph: icon("md_header1.png") },
      { name: "heading2", title: "标题2", glyph: icon("md_header2.png") },
      { name: "heading3", title: "标题3", glyph: icon("md_header3.png") }
    ],
    [
      { name: "bullet", title: "无序列表", glyph: icon("md_list.png") },
      { name: "ordered", title: "有序列表", glyph: icon("md_orderList.png") },
      { name: "checklist", title: "清单", glyph: icon("md_checkBox.png") }
    ],
    [
      { name: "blockquote", title: "引用", glyph: icon("md_quote.png") },
      { name: "code-block", title: "代码块", glyph: icon("md_code.png") },
      { name: "divider", title: "分割线", glyph: icon("md_horizontal.png") }
    ],
    [
      { name: "image", title: "图片", glyph: icon("wf_image.svg") },
      { name: "attachment", title: "附件", glyph: icon("md_attachment.png") },
      { name: "table", title: "表格", glyph: icon("wf_table.svg") },
      { name: "diagram", title: "流程图（draw.io）", glyph: icon("wf_diagram.svg") }
    ]
  ];

  var state = { element: null, items: [], selected: 0, slashIndex: null, handlers: null };

  function buildMenu() {
    var menu = document.createElement("div");
    menu.id = "wf-slash";
    menu.style.display = "none";
    document.body.appendChild(menu);
    state.element = menu;
    return menu;
  }

  function flatItems() {
    return state.items;
  }

  function render() {
    var menu = state.element || buildMenu();
    menu.innerHTML = "";
    state.items = [];
    var flatIndex = 0;
    GROUPS.forEach(function (group, groupIndex) {
      if (groupIndex > 0) {
        var sep = document.createElement("div");
        sep.className = "wf-slash-sep";
        menu.appendChild(sep);
      }
      group.forEach(function (item) {
        var row = document.createElement("div");
        row.className = "wf-slash-item" + (flatIndex === state.selected ? " selected" : "");
        row.dataset.index = flatIndex;
        var glyph = document.createElement("span");
        glyph.className = "wf-slash-glyph";
        glyph.innerHTML = item.glyph;
        var label = document.createElement("span");
        label.textContent = item.title;
        row.appendChild(glyph);
        row.appendChild(label);
        row.addEventListener("click", function () {
          activate(item);
        });
        menu.appendChild(row);
        state.items.push(item);
        flatIndex += 1;
      });
    });
    menu.style.display = state.items.length ? "block" : "none";
  }

  function activate(item) {
    var handlers = state.handlers;
    close();
    if (handlers && handlers.onPick) handlers.onPick(item.name, state.slashIndex);
  }

  function open(slashIndex, caretRect, handlers) {
    state.handlers = handlers;
    state.slashIndex = slashIndex;
    state.selected = 0;
    render();
    var menu = state.element;
    var x = Math.max(8, caretRect.left);
    var y = caretRect.bottom + 6;
    menu.style.left = Math.min(x, window.innerWidth - menu.offsetWidth - 8) + "px";
    menu.style.top = Math.min(y, window.innerHeight - menu.offsetHeight - 8) + "px";
  }

  function close() {
    if (state.element) {
      state.element.style.display = "none";
      state.element.innerHTML = "";
      state.items = [];
    }
    state.slashIndex = null;
  }

  function isOpen() {
    return !!state.element && state.element.style.display !== "none" && state.items.length > 0;
  }

  function move(delta) {
    var count = flatItems().length;
    if (!count) return;
    state.selected = (state.selected + delta + count) % count;
    render();
    var rows = state.element.querySelectorAll(".wf-slash-item");
    var row = rows[state.selected];
    if (row) row.scrollIntoView({ block: "nearest" });
  }

  function current() {
    return flatItems()[state.selected] || null;
  }

  window.WorkFollowSlashMenu = {
    open: open,
    close: close,
    isOpen: isOpen,
    move: move,
    current: current
  };
})();
