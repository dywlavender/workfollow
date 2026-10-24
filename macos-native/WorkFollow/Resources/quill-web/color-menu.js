/* WorkFollow 编辑器：A▾ 字体颜色下拉面板（滴答同款双区色板）。
   上区 = 字体颜色（含"默认"清除项），下区 = 背景高亮。
   #ffe98a 为高亮标记的规范色（与 QuillDeltaCodec.highlightBackground 对齐）。 */
"use strict";

(function () {
  var TEXT_COLORS = [
    { value: null, title: "默认", clear: true },
    { value: "#e74c3c", title: "红色" },
    { value: "#f2762e", title: "橙色" },
    { value: "#f7c74d", title: "黄色" },
    { value: "#53b685", title: "绿色" },
    { value: "#4a90e2", title: "蓝色" },
    { value: "#9b72e3", title: "紫色" },
    { value: "#ed7dd9", title: "粉色" },
    { value: "#43bfcb", title: "青色" },
    { value: "#8c8c8c", title: "灰色" }
  ];

  var HIGHLIGHTS = [
    { value: null, title: "无", clear: true },
    { value: "#ffe98a", title: "黄色" },
    { value: "#c9f2c7", title: "绿色" },
    { value: "#c7e3f8", title: "蓝色" },
    { value: "#fcd6f0", title: "粉色" },
    { value: "#fde3c0", title: "橙色" }
  ];

  var panel = null;

  function ensurePanel() {
    if (panel) return panel;
    panel = document.createElement("div");
    panel.id = "wf-color-menu";
    panel.style.display = "none";
    document.body.appendChild(panel);
    document.addEventListener("mousedown", function (event) {
      if (panel.style.display === "none") return;
      if (!panel.contains(event.target)) close();
    }, true);
    return panel;
  }

  function swatchRow(list, apply) {
    var row = document.createElement("div");
    row.className = "wf-color-row";
    list.forEach(function (item) {
      var cell = document.createElement("button");
      cell.className = "wf-color-cell" + (item.clear ? " wf-color-clear" : "");
      cell.title = item.title;
      cell.setAttribute("aria-label", item.title);
      if (item.clear) {
        cell.innerHTML = "<img class='wf-icon' src='icons/color_picker_clear.png' alt=''>";
      } else {
        var dot = document.createElement("span");
        dot.className = "wf-color-dot";
        dot.style.background = item.value;
        cell.appendChild(dot);
      }
      cell.addEventListener("mousedown", function (event) { event.preventDefault(); });
      cell.addEventListener("click", function () {
        apply(item.value);
        close();
      });
      row.appendChild(cell);
    });
    return row;
  }

  function sectionLabel(text) {
    var label = document.createElement("div");
    label.className = "wf-color-label";
    label.textContent = text;
    return label;
  }

  function open(anchorButton, handlers) {
    var el = ensurePanel();
    el.innerHTML = "";
    el.appendChild(sectionLabel("字体颜色"));
    el.appendChild(swatchRow(TEXT_COLORS, function (value) {
      handlers.applyText(value);
    }));
    el.appendChild(sectionLabel("背景高亮"));
    el.appendChild(swatchRow(HIGHLIGHTS, function (value) {
      handlers.applyHighlight(value);
    }));
    el.style.display = "block";
    var rect = anchorButton.getBoundingClientRect();
    el.style.left = Math.max(8, Math.min(rect.left, window.innerWidth - el.offsetWidth - 8)) + "px";
    el.style.top = Math.min(rect.bottom + 5, window.innerHeight - el.offsetHeight - 8) + "px";
  }

  function close() {
    if (panel) panel.style.display = "none";
  }

  function isOpen() {
    return !!panel && panel.style.display !== "none";
  }

  window.WorkFollowColorMenu = { open: open, close: close, isOpen: isOpen };
})();
