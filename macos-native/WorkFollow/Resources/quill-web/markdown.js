/* WorkFollow 编辑器：Markdown 输入期触发器（JS 版）。
   口径 1:1 迁移自原生 `DocumentMarkdownInput`（滴答 8.0.80，2026-10-16 产品确认）：
   - 空格结尾的块级前缀：# ～ ######、* / - / +、1.、- [ ] / - [x]、>；
   - 整行 3+ 相同符号成分割线（--- / *** / ___）；
   - 整行 3+ 反引号成围栏代码块（行首最多 3 空格）；
   - 闭合即转的行内标记：**粗**、*斜*、~~删除线~~、~下划线~、::高亮::、`码`、[文字](url)。
   触发后标记串从正文移除（"符号隐藏"），格式按设值语义应用。 */
"use strict";

(function () {
  var BLOCK_RULES = [
    { re: /^(#{1,6})\s$/, apply: function (m) { return { kind: "header", level: m[1].length }; } },
    { re: /^[-*+]\s$/, apply: function () { return { kind: "list", value: "bullet" }; } },
    { re: /^1\.\s$/, apply: function () { return { kind: "list", value: "ordered" }; } },
    { re: /^-\s\[\s\]\s$/, apply: function () { return { kind: "list", value: "unchecked" }; } },
    { re: /^-\s\[x\]\s$/i, apply: function () { return { kind: "list", value: "checked" }; } },
    { re: /^>\s$/, apply: function () { return { kind: "blockquote" }; } }
  ];

  function isDividerLine(line) {
    return /^(-{3,}|\*{3,}|_{3,})$/.test(line);
  }

  function isFenceLine(line) {
    return /^\s{0,3}`{3,}$/.test(line);
  }

  var INLINE_RULES = [
    { re: /\*\*([^*\s][^*]*)\*\*$/, mark: { bold: true } },
    { re: /(?<!\*)\*([^*\s][^*]*)\*(?!\*)$/, mark: { italic: true } },
    { re: /~~([^~\s][^~]*)~~$/, mark: { strike: true } },
    { re: /(?<!~)~([^~\s][^~]*)~(?!~)$/, mark: { underline: true } },
    { re: /::([^:\s][^:]*)::$/, mark: { background: "#ffe98a" } },
    { re: /`([^`\s][^`]*)`$/, mark: { code: true } },
    { re: /\[([^\]\s]+)\]\(([^()\s]+)\)$/, mark: null }   // link 特例（带 url）
  ];

  /** 返回需要应用到 [start,end) 的格式，或 null（不触发）。 */
  function matchInline(textBeforeCaret) {
    for (var i = 0; i < INLINE_RULES.length; i += 1) {
      var rule = INLINE_RULES[i];
      var m = rule.re.exec(textBeforeCaret);
      if (m) {
        if (rule.mark) return { removeLength: m[0].length, mark: rule.mark };
        return { removeLength: m[0].length, mark: { link: m[2] }, keepText: m[1] };
      }
    }
    return null;
  }

  window.WorkFollowMarkdown = {
    blockPrefix: function (lineText) {
      for (var i = 0; i < BLOCK_RULES.length; i += 1) {
        var m = BLOCK_RULES[i].re.exec(lineText);
        if (m) return BLOCK_RULES[i].apply(m);
      }
      return null;
    },
    isDividerLine: isDividerLine,
    isFenceLine: isFenceLine,
    matchInline: matchInline
  };
})();
