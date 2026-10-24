/* WorkFollow 编辑器：斜杠菜单（滴答 13 项 + 我们独有的流程图 = 14 项）。
   菜单项与 2026-10-24 REA 取证的滴答斜杠菜单逐条对齐。 */
"use strict";

(function () {
  var GROUPS = [
    [
      { name: "paragraph", title: "文本", glyph: "¶" },
      { name: "heading1", title: "标题1", glyph: "H1" },
      { name: "heading2", title: "标题2", glyph: "H2" },
      { name: "heading3", title: "标题3", glyph: "H3" }
    ],
    [
      { name: "bullet", title: "无序列表", glyph: "•" },
      { name: "ordered", title: "有序列表", glyph: "1." },
      { name: "checklist", title: "清单", glyph: "☑" }
    ],
    [
      { name: "blockquote", title: "引用", glyph: "❝" },
      { name: "code-block", title: "代码块", glyph: "{ }" },
      { name: "divider", title: "分割线", glyph: "—" }
    ],
    [
      { name: "image", title: "图片", glyph: "🖼" },
      { name: "attachment", title: "附件", glyph: "📎" },
      { name: "table", title: "表格", glyph: "▦" },
      { name: "diagram", title: "流程图（draw.io）", glyph: "◬" }
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
        glyph.textContent = item.glyph;
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
