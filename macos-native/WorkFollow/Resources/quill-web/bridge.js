/* WorkFollow 编辑器主装配：内核实例、Swift 桥、工具条联动、
   斜杠会话、markdown 触发、块 embed 双击、高度上报。 */
"use strict";

(function () {
  var root = document.getElementById("root");
  var editorHost = document.createElement("div");
  editorHost.id = "editor";
  // 工具条（滴答：顶部裸条）必须挂在编辑器**上方**——先 build 工具条
  // 再 append 编辑器，DOM 顺序即视觉顺序。
  var toolbar = window.WorkFollowToolbar.build(root, {
    colorMenu: function (anchorButton) {
      if (window.WorkFollowColorMenu.isOpen()) {
        window.WorkFollowColorMenu.close();
        quill.focus();
        return;
      }
      window.WorkFollowColorMenu.open(anchorButton, {
        applyText: function (value) {
          quill.format("color", value === null ? false : value, "user");
          quill.focus();
        },
        applyHighlight: function (value) {
          quill.format("background", value === null ? false : value, "user");
          quill.focus();
        }
      });
    },
    toggle: function (name) {
      var format = quill.getFormat();
      switch (name) {
        case "bold": quill.format("bold", !format.bold); break;
        case "italic": quill.format("italic", !format.italic); break;
        case "underline": quill.format("underline", !format.underline); break;
        case "strike": quill.format("strike", !format.strike); break;
        case "highlight": quill.format("background", format.background ? false : "#ffe98a"); break;
        case "bullet": quill.format("list", format.list === "bullet" ? false : "bullet"); break;
        case "ordered": quill.format("list", format.list === "ordered" ? false : "ordered"); break;
        case "checklist":
          var inChecklist = format.list === "checked" || format.list === "unchecked";
          quill.format("list", inChecklist ? false : "unchecked");
          break;
        case "blockquote": quill.format("blockquote", !format.blockquote); break;
        case "code": quill.format("code", !format.code); break;
        case "code-block": quill.format("code-block", !format["code-block"]); break;
      }
      quill.focus();
    },
    action: function (name) {
      post({ event: "requestAction", action: name });
      if (name === "divider") insertDivider();
      if (name === "code-block") quill.format("code-block", !quill.getFormat()["code-block"]);
    }
  });

  root.appendChild(editorHost);
  // 滴答口径：工具条默认隐藏，展开时出现在编辑区**底部**（DOM 移到编辑器之后）。
  root.appendChild(toolbar);
  toolbar.style.display = "none";
  var quill = new Quill("#editor", {
    theme: "snow",
    placeholder: "写下你的想法…",
    modules: {
      toolbar: false,
      history: { delay: 400, maxStack: 200 }
    }
  });
  window.quill = quill;

  function post(message) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.quill) {
      window.webkit.messageHandlers.quill.postMessage(message);
    }
  }

  var deltaRevision = 0;        // 防同步回环：宿主记录"最后一次 load 的 rev"
  function emitDelta() {
    deltaRevision += 1;
    post({
      event: "deltaChanged",
      rev: deltaRevision,
      delta: JSON.stringify(quill.getContents().ops),
      plainText: trimTrailingNewline(quill.getText()),
      length: quill.getLength()
    });
  }

  function trimTrailingNewline(text) {
    if (text.endsWith("\n")) return text.slice(0, -1);
    return text;
  }

  function caretRect() {
    var selection = quill.getSelection();
    if (!selection) return { left: 40, top: 40, bottom: 70 };
    var bounds = quill.getBounds(selection.index, Math.max(selection.length, 1));
    return bounds;
  }

  // ---------- 斜杠会话（对齐 Flutter：新插入单个 / 且光标紧跟才开会话） ----------

  var slashIndex = null;

  quill.on("text-change", function (delta, oldDelta, source) {
    if (source === "silent") return;
    emitDelta();
    reportHeight();              // 高度随内容变化立即上报（不等 ResizeObserver 的下一拍）
    handleMarkdown();
    handleSlash(delta);
  });

  function handleSlash(delta) {
    var last = delta.ops[delta.ops.length - 1];
    var inserted = last && typeof last.insert === "string" ? last.insert : "";
    if (inserted === "/" && slashIndex === null) {
      slashIndex = quill.getSelection().index;
      window.WorkFollowSlashMenu.open(slashIndex, caretRect(), {
        onPick: applySlash
      });
    } else if (slashIndex !== null && window.WorkFollowSlashMenu.isOpen()) {
      // 打开期间的输入 = 过滤（简化为任意字符继续、Esc/失焦关）。
      var selection = quill.getSelection();
      if (selection && selection.index < slashIndex) {
        closeSlash();
      }
    }
  }

  function closeSlash() {
    slashIndex = null;
    window.WorkFollowSlashMenu.close();
  }

  function applySlash(name, index) {
    quill.deleteText(index - 1, 1, "user");     // 移除 "/"
    quill.setSelection(index - 1, 0, "user");
    runSlashCommand(name);
  }

  function runSlashCommand(name) {
    var selection = quill.getSelection() || { index: quill.getLength() - 1, length: 0 };
    switch (name) {
      case "paragraph": quill.formatLine(selection.index, 0, "header", false, "user"); break;
      case "heading1": quill.formatLine(selection.index, 0, "header", 1, "user"); break;
      case "heading2": quill.formatLine(selection.index, 0, "header", 2, "user"); break;
      case "heading3": quill.formatLine(selection.index, 0, "header", 3, "user"); break;
      case "bullet": quill.formatLine(selection.index, 0, "list", "bullet", "user"); break;
      case "ordered": quill.formatLine(selection.index, 0, "list", "ordered", "user"); break;
      case "checklist": quill.formatLine(selection.index, 0, "list", "unchecked", "user"); break;
      case "blockquote": quill.formatLine(selection.index, 0, "blockquote", true, "user"); break;
      case "code-block": quill.formatLine(selection.index, 0, "code-block", true, "user"); break;
      case "divider": insertDivider(); break;
      case "image": post({ event: "requestAction", action: "image" }); break;
      case "attachment": post({ event: "requestAction", action: "attachment" }); break;
      case "table": insertTableStub(); break;
      case "diagram": post({ event: "requestAction", action: "diagram" }); break;
    }
  }

  function insertDivider() {
    var selection = quill.getSelection();
    var index = selection ? selection.index : quill.getLength() - 1;
    quill.insertEmbed(index, "workfollow-block", { type: "divider" }, "user");
    quill.insertText(index + 1, "\n", "user");
    quill.setSelection(index + 1, 0, "user");
  }

  function insertTableStub() {
    // 表格（滴答有、Quill 2 核心无）：P2 先落只读占位（对齐 Flutter 笔记现状），
    // 后续评估 quill-table-better 模块化升级。
    var selection = quill.getSelection();
    var index = selection ? selection.index : quill.getLength() - 1;
    quill.insertEmbed(index, "workfollow-block", { type: "table", rows: 3, cols: 3 }, "user");
    quill.insertText(index + 1, "\n", "user");
    quill.setSelection(index + 1, 0, "user");
  }

  // ---------- markdown 触发（与 DocumentMarkdownInput 口径一致） ----------

  function currentLineText() {
    var selection = quill.getSelection();
    if (!selection) return "";
    var index = selection.index;
    var before = quill.getText(0, index);
    var lineStart = before.lastIndexOf("\n") + 1;
    return before.slice(lineStart);
  }

  function handleMarkdown() {
    var selection = quill.getSelection();
    if (!selection || selection.length > 0) return;
    var line = currentLineText();

    // 1) 块级前缀（空格结尾触发）
    var block = window.WorkFollowMarkdown.blockPrefix(line);
    if (block) {
      var lineStart = selection.index - line.length;
      quill.deleteText(lineStart, line.length, "user");
      quill.setSelection(lineStart, 0, "user");
      switch (block.kind) {
        case "header": quill.formatLine(lineStart, 0, "header", block.level, "user"); break;
        case "list": quill.formatLine(lineStart, 0, "list", block.value, "user"); break;
        case "blockquote": quill.formatLine(lineStart, 0, "blockquote", true, "user"); break;
      }
      return;
    }

    // 2) 分割线（整行敲完）
    if (window.WorkFollowMarkdown.isDividerLine(line)) {
      var lineStart2 = selection.index - line.length;
      quill.deleteText(lineStart2, line.length, "user");
      quill.insertEmbed(lineStart2, "workfollow-block", { type: "divider" }, "user");
      quill.insertText(lineStart2 + 1, "\n", "user");
      quill.setSelection(lineStart2 + 1, 0, "user");
      return;
    }

    // 3) 围栏代码块（整行敲完）
    if (window.WorkFollowMarkdown.isFenceLine(line)) {
      var lineStart3 = selection.index - line.length;
      quill.deleteText(lineStart3, line.length, "user");
      quill.formatLine(lineStart3, 0, "code-block", true, "user");
      return;
    }

    // 4) 行内闭合标记
    var before = quill.getText(0, selection.index);
    var inline = window.WorkFollowMarkdown.matchInline(before);
    if (inline) {
      var start = selection.index - inline.removeLength;
      var keptText = inline.keepText;
      quill.deleteText(start, inline.removeLength, "user");
      if (keptText !== undefined) {
        quill.insertText(start, keptText, inline.mark, "user");
        quill.setSelection(start + keptText.length, 0, "user");
      } else {
        var plain = before.slice(before.length - inline.removeLength);
        var body = plain.replace(/^(\*\*|\*|~~|~|::|`)/, "").replace(/(\*\*|\*|~~|~|::|`)$/, "");
        quill.insertText(start, body, inline.mark, "user");
        quill.setSelection(start + body.length, 0, "user");
      }
    }
  }

  // ---------- 工具条激活态 ----------

  quill.on("selection-change", function (range) {
    if (range) {
      window.WorkFollowToolbar.syncActive(toolbar, quill.getFormat(range.index, range.length));
      if (window.WorkFollowSlashMenu.isOpen() && range.index < slashIndex) closeSlash();
    }
    post({ event: "selectionChanged", range: range ? { index: range.index, length: range.length } : null });
  });

  // ---------- Swift 桥 ----------

  window.workfollowQuill = { send: handleSwiftMessage };

  // 宿主稳定 API：load(deltaOps) / focus / tab / insertImage(base64)
  window.workfollowEditor = {
    load: function (ops) {
      quill.setContents(ops || [], "silent");
      quill.setSelection(ops && ops.length ? quill.getLength() - 1 : 0, "silent");
      // 静默装载也要推 rev：宿主随后收到的 deltaChanged（用户键入）才不会
      // 被误判为"自己刚 load 的回声"。
      deltaRevision += 1;
      post({ event: "loaded", rev: deltaRevision });
      emitDelta();
    },
    focus: function () { quill.focus(); },
    setGrows: function (grows) {
      document.body.classList.toggle("wf-grows", !!grows);
      reportHeight();
    },
    setToolbar: function (visible) {
      toolbar.style.display = visible ? "flex" : "none";
      reportHeight();
    },
    tab: function () {
      // 列表行内 Tab 缩进（Quill 键盘绑定默认不覆盖 Tab），这里手动实现。
      var selection = quill.getSelection();
      if (!selection) return;
      var format = quill.getFormat(selection.index, selection.length);
      if (format.list || format.blockquote || format["code-block"]) {
        quill.indent(selection.index, selection.length);
      }
    },
    insertText: function (text) {
      var selection = quill.getSelection();
      var index = selection ? selection.index : quill.getLength() - 1;
      quill.insertText(index, text, "user");
      quill.setSelection(index + text.length, 0, "user");
    },
    // Swift 宿主的键盘直注通道（焦点攻坚终案：不走 contenteditable 焦点）。
    injectKeyEvent: function (text, isShift) {
      var selection = quill.getSelection();
      var index = selection ? selection.index : quill.getLength() - 1;
      if (text === "\n") { quill.insertText(index, "\n", "user"); quill.setSelection(index + 1, 0, "user"); return; }
      quill.insertText(index, text, "user");
      quill.setSelection(index + text.length, 0, "user");
    },
    backspace: function () {
      var selection = quill.getSelection();
      if (!selection) return;
      if (selection.length > 0) {
        quill.deleteText(selection.index, selection.length, "user");
      } else if (selection.index > 0) {
        quill.deleteText(selection.index - 1, 1, "user");
        quill.setSelection(selection.index - 1, 0, "user");
      }
    },
    arrow: function (keyCode) {
      var selection = quill.getSelection();
      if (!selection) { quill.setSelection(quill.getLength() - 1, 0, "user"); return; }
      var index = selection.index;
      var text = quill.getText();
      switch (keyCode) {
        case 123: index = Math.max(0, index - 1); break;               // left
        case 124: index = Math.min(quill.getLength() - 1, index + 1); break;  // right
        case 125:                                                   // down
          var nl = text.indexOf("\n", index);
          index = nl < 0 ? quill.getLength() - 1 : Math.min(nl + 1, quill.getLength() - 1);
          break;
        case 126:                                                   // up
          var before = text.substring(0, index);
          var lastNl = before.lastIndexOf("\n", before.length - 2);
          index = lastNl < 0 ? 0 : lastNl + 1;
          break;
      }
      quill.setSelection(index, 0, "user");
    },
    insertImage: function (base64) {
      var selection = quill.getSelection();
      var index = selection ? selection.index : quill.getLength() - 1;
      quill.insertEmbed(index, "image", "data:image/png;base64," + base64, "user");
      quill.setSelection(index + 1, 0, "user");
    }
  };

  function handleSwiftMessage(message) {
    switch (message.action) {
      case "load":
        quill.setContents(message.delta || [], "silent");
        quill.setSelection(message.delta && message.delta.length ? quill.getLength() - 1 : 0, "silent");
        emitDelta();
        break;
      case "focus": quill.focus(); break;
      case "blur": quill.blur(); break;
      case "setPlaceholder":
        var editor = document.querySelector(".ql-editor");
        if (editor) editor.setAttribute("data-placeholder", message.text || "");
        break;
      case "setReadOnly": quill.enable(message.enabled === false ? false : true); break;
      case "insertDelta":
        var ops = message.delta || [];
        var target = quill.getSelection() || { index: quill.getLength() - 1 };
        var change = new window.Quill.import("delta")(ops);
        quill.updateContents(change.retain ? change : change.compose(new window.Quill.import("delta")()), "user");
        quill.setSelection(target.index, 0, "user");
        break;
      case "insertBlockEmbed":
        var at = quill.getSelection() ? quill.getSelection().index : quill.getLength() - 1;
        quill.insertEmbed(at, "workfollow-block", message.value, "user");
        quill.insertText(at + 1, "\n", "user");
        quill.setSelection(at + 1, 0, "user");
        break;
    }
  }

  // ---------- 键盘拦截（Esc / Tab / 斜杠菜单导航） ----------

  document.addEventListener("keydown", function (event) {
    if (window.WorkFollowSlashMenu.isOpen()) {
      switch (event.key) {
        case "Escape": event.preventDefault(); closeSlash(); return;
        case "ArrowDown": event.preventDefault(); window.WorkFollowSlashMenu.move(1); return;
        case "ArrowUp": event.preventDefault(); window.WorkFollowSlashMenu.move(-1); return;
        case "Enter":
          event.preventDefault();
          var item = window.WorkFollowSlashMenu.current();
          if (item) { applySlash(item.name, slashIndex); }
          return;
      }
    }
    if (event.key === "Escape") {
      if (window.WorkFollowColorMenu && window.WorkFollowColorMenu.isOpen()) {
        event.preventDefault();
        window.WorkFollowColorMenu.close();
        return;
      }
      event.preventDefault();
      post({ event: "escapePressed" });
    } else if (event.key === "Tab") {
      event.preventDefault();
      post({ event: "tabPressed", shift: event.shiftKey });
    }
  }, true);

  // ---------- 块 embed 双击（drawio 编辑入口） ----------

  editorHost.addEventListener("dblclick", function (event) {
    var card = event.target.closest(".wf-embed-card");
    if (card && card.dataset.wfBlock) {
      try {
        var data = JSON.parse(card.dataset.wfBlock);
        if (data.type === "diagram") post({ event: "requestAction", action: "editDiagram", diagram: data });
      } catch (error) { /* 占位卡 */ }
    }
  });

  // ---------- 高度上报 ----------

  function reportHeight() {
    post({ event: "heightChanged", height: root.scrollHeight });
  }
  if (window.ResizeObserver) {
    new ResizeObserver(reportHeight).observe(root);
  }

  // SwiftUI 宿主下点击夺焦保底：WKWebView 的 mouseDown 不总是触发
  // firstResponder 变更（实测缺陷），这里显式 focus 编辑器。
  editorHost.addEventListener("mousedown", function () {
    setTimeout(function () { quill.focus(); }, 0);
  });

  window.addEventListener("load", function () {
    post({ event: "ready" });
    reportHeight();
  });
})();
