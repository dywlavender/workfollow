/* WorkFollow 编辑器：自定义 blot（与 Flutter `workfollow-block` embed key 对齐）。
   divider / attachment / diagram 三类块级 embed + image。 */
"use strict";

(function () {
  var Quill = window.Quill;
  var BlockEmbed = Quill.import("blots/block/embed");
  var Inline = Quill.import("blots/inline");

  var WorkFollowBlock = function (_BlockEmbed) {
    function WorkFollowBlock() {
      return _BlockEmbed.apply(this, arguments) || this;
    }
    Object.assign(WorkFollowBlock, _BlockEmbed);
    WorkFollowBlock.prototype = Object.create(_BlockEmbed && _BlockEmbed.prototype);
    WorkFollowBlock.prototype.constructor = WorkFollowBlock;

    WorkFollowBlock.blotName = "workfollow-block";
    WorkFollowBlock.tagName = "div";
    WorkFollowBlock.className = "wf-embed";

    WorkFollowBlock.create = function (value) {
      var node = _BlockEmbed.create.call(WorkFollowBlock, value);
      var data = typeof value === "string" ? JSON.parse(value) : (value || {});
      switch (data.type) {
        case "divider":
          node.classList.add("wf-embed-divider");
          break;
        case "attachment":
          node.classList.add("wf-embed-card");
          node.textContent = "📎 " + (data.name || "附件");
          break;
        case "diagram":
          node.classList.add("wf-embed-card");
          node.dataset.wfDiagram = JSON.stringify(data);
          if (data.png) {
            var image = document.createElement("img");
            image.src = "data:image/png;base64," + data.png;
            image.alt = data.title || "流程图";
            node.appendChild(image);
          }
          var caption = document.createElement("span");
          caption.textContent = (data.title || "流程图") + " · 双击编辑";
          node.appendChild(caption);
          break;
        default:
          node.classList.add("wf-embed-card");
          node.textContent = "[" + (data.type || "?") + "]";
      }
      node.dataset.wfBlock = JSON.stringify(data);
      return node;
    };

    WorkFollowBlock.value = function (node) {
      try { return JSON.parse(node.dataset.wfBlock || "{}"); }
      catch (error) { return { type: "unknown" }; }
    };

    return WorkFollowBlock;
  }(BlockEmbed);
  Quill.register(WorkFollowBlock);

  // 图片：data: URL（粘贴管线走 base64，离线无外链）。
  var WFImage = function (_Image) {
    function WFImage() { return _Image.apply(this, arguments) || this; }
    Object.assign(WFImage, _Image);
    WFImage.prototype = Object.create(_Image && _Image.prototype);
    WFImage.prototype.constructor = WFImage;
    WFImage.blotName = "image";
    return WFImage;
  }(Quill.import("formats/image"));
  Quill.register(WFImage, true);

  // 高亮：background 属性的可视化由 snow 主题 + ::selection 承担，
  // 这里不需要自定义 inline；导出 link/code 用官方格式。
  window.WorkFollowBlots = { ready: true };
})();
