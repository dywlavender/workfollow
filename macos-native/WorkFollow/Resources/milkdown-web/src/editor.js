import './workfollow.css';
import 'katex/dist/katex.min.css';
import { Editor, editorViewCtx, rootCtx, defaultValueCtx, editorViewOptionsCtx, nodeViewCtx } from '@milkdown/core';
import { history } from '@milkdown/plugin-history';
import { $prose } from '@milkdown/utils';
import { Plugin, EditorState, TextSelection } from '@milkdown/prose/state';
import { Fragment, Slice } from '@milkdown/prose/model';
import { toggleMark, splitBlock, deleteSelection, joinBackward, joinForward, selectAll } from '@milkdown/prose/commands';
import { undo, redo, undoDepth, redoDepth, closeHistory } from '@milkdown/prose/history';
import { inputRules, InputRule, undoInputRule } from '@milkdown/prose/inputrules';
import { Decoration, DecorationSet } from '@milkdown/prose/view';
import katex from 'katex';
import hljs from 'highlight.js/lib/common';
import { schemaPlugins, fromNative, toNative, toNativeBlocks, wireKey, plainText, plainOffset, positionForPlainOffset, selectionDocument, uuid, isList, shiftedBlocks, listNumbers, getSerializeCount } from './schema.js';
import { HostHistoryStep, hostHistory, historyBoundary, clipboardBoundaries, synchronizeDocument } from './transactions.js';

let editor, view, current, loading = false, revision = 0, height = -1, pendingCommit = false;
let settings = { readOnly: false }, popup, painter, pendingHostToken, lastOperation, lastCommit;
let numberedDocument, numberedNodes = [], numberedMarkers = new Map();
let syntaxDocument, syntaxDecorations;
let ghostVersion = 0, renderedGhostVersion = -1, renderedGhostAnchor = -1;
let ghostTimer, ghostRequest = 0;
let ghost = { text: '', anchor: -1, documentID: '', epoch: '' };
const INLINE_DATE = /(?:今天|明天|后天|大后天|明早|明晚|今早|今晚|下下周[一二三四五六日天]|下周[一二三四五六日天]|本周[一二三四五六日天]|周[一二三四五六日天]|星期[一二三四五六日天]|\d{1,2}月\d{1,2}[日号]|\d{1,2}\/\d{1,2}|\d+\s*(?:天|周|小时)后)(?:前|之前|截止|以前)?/g;
let pointerAnchor;
let hoverTimer, hoveredLink;
let popupSession = 0;
const syntaxCache = new Map();
// 行内日期命中区间按块节点缓存：ProseMirror 结构共享，未改动块不再全文重扫正则。
const dateSpansCache = new WeakMap();
const emptyBlock = node => node.content.size === 0 || node.content.content.every(child => child.type.name === 'wf_empty');
const post = message => window.webkit?.messageHandlers?.milkdown?.postMessage({ ...message,
  documentID: current?.documentID, epoch: current?.epoch });
const action = (name, payload = {}) => post({ event: 'requestAction', action: name, payload });
const nativeTime = () => Date.now() / 1000 - 978307200;
const blockAt = () => view?.state.selection.$from.parent;
const editable = () => !!current && !settings.readOnly;
const button = (text, title, fn) => {
  const element = document.createElement('button'); element.type = 'button'; element.textContent = text; element.title = title;
  // Node-view controls are outside the document. WebKit must not move the
  // caret into their labels while navigating between editable paragraphs.
  element.contentEditable = 'false';
  element.setAttribute('aria-label', title); element.addEventListener('mousedown', event => event.preventDefault());
  element.addEventListener('click', fn); return element;
};
function snapshot() {
  const state = view.state, selection = state.selection, block = selection.$from.parent;
  let marks = state.storedMarks || selection.$from.marks();
  if (!selection.empty) {
    let intersection;
    state.doc.nodesBetween(selection.from, selection.to, node => {
      if (!node.isInline) return;
      intersection = intersection ? intersection.filter(mark => node.marks.some(other => other.eq(mark))) : node.marks;
    });
    marks = intersection || [];
  }
  return { revision, from: selection.from, to: selection.to,
    text: selection.empty ? '' : state.doc.textBetween(selection.from, selection.to, '\n', node => node.type.name === 'wf_embed' ? node.attrs.text : ''),
    plainFrom: plainOffset(state.doc, selection.from), plainTo: plainOffset(state.doc, selection.to),
    style: { blockToken: block.attrs.kind === 'heading' ? `h${block.attrs.level}` : block.attrs.kind === 'checklist' && block.attrs.checked ? 'checked' : block.attrs.kind,
      marks: marks.filter(mark => mark.type.name !== 'wf_run').map(mark => ({ type: mark.type.name, value: mark.attrs.value })),
      indentLevel: block.attrs.indentLevel || 0, align: block.attrs.align, bodySize: block.attrs.bodySize },
    canUndo: undoDepth(state) > 0, canRedo: redoDepth(state) > 0, empty: state.doc.childCount === 1 && emptyBlock(state.doc.firstChild), formatPainterActive: !!painter,
    ...(selection.empty ? {} : { fragment: selectionDocument(state) }) };
}
let sentBlocks = null, sentOrder = null; // 差量基线：load 后置空，下一次提交转全量
function commitNow() {
  if (loading || !current || !view) return;
  const parts = toNativeBlocks(view.state.doc);
  const order = parts.map(part => part.id);
  const token = pendingHostToken ? { hostToken: pendingHostToken } : {};
  if (sentBlocks) {
    const changed = {};
    let touched = false;
    for (const part of parts) {
      const key = wireKey(part.wire);
      if (sentBlocks.get(part.id) !== key) { changed[part.id] = part.wire; touched = true; }
    }
    const orderChanged = !sentOrder || sentOrder.length !== order.length
      || order.some((id, index) => sentOrder[index] !== id);
    // 无变化且没有宿主事务要确认时不再过桥（编号刷新等空转一律拦下）。
    if (!touched && !orderChanged && !pendingHostToken && !lastOperation) return;
    revision += 1;
    const doc = { blocks: parts.map(part => part.wire) };
    lastCommit = { revision, doc, ...token, operation: lastOperation };
    post({ event: 'docChanged', revision, order, ...(touched ? { changed } : {}), ...token, operation: lastOperation });
  } else {
    revision += 1;
    const doc = { blocks: parts.map(part => part.wire) };
    lastCommit = { revision, doc, ...token, operation: lastOperation };
    post({ event: 'docChanged', revision, doc, ...token, operation: lastOperation });
  }
  sentBlocks = new Map(parts.map(part => [part.id, wireKey(part.wire)]));
  sentOrder = order;
  pendingHostToken = undefined; lastOperation = undefined;
}
function commitSoon() {
  if (pendingCommit || loading) return;
  pendingCommit = true; const epoch = current?.epoch;
  queueMicrotask(() => { if (!pendingCommit) return; pendingCommit = false; if (epoch === current?.epoch) commitNow(); });
}
function updateUI() {
  if (!view || loading) return;
  post({ event: 'selectionChanged', selection: snapshot() });
  updateNumbering(); updateToolbar(); updateSuggestions(); reportHeight();
}
function revealSelection() {
  const rect = view.coordsAtPos(view.state.selection.head);
  post({ event: 'revealRect', rect: { x: rect.left, y: rect.top, width: Math.max(1, rect.right - rect.left), height: rect.bottom - rect.top } });
}
function selectedBlocks(state = view.state) {
  const blocks = [], end = state.selection.empty ? state.selection.to : state.selection.to - 1;
  state.doc.forEach((node, pos, index) => {
    if (pos + 1 <= end && pos + node.nodeSize - 1 >= state.selection.from) blocks.push({ node, pos, index });
  });
  return blocks;
}
function setBlock(attrs) {
  const { state } = view, tr = closeHistory(state.tr);
  for (const { node, pos } of selectedBlocks(state)) {
    const next = { ...node.attrs, ...attrs };
    if (attrs.kind && attrs.kind !== 'ordered') next.listStart = null;
    if (attrs.kind && attrs.kind !== 'paragraph') next.bodySize = null;
    tr.setNodeMarkup(pos, undefined, next);
  }
  view.dispatch(tr.scrollIntoView()); view.focus();
}
function format(id, toggle = true) {
  const mark = { bold: 'bold', italic: 'italic', underline: 'underline', strikethrough: 'strikethrough', highlight: 'highlight', inlineCode: 'code' }[id];
  if (mark) { toggleMark(view.state.schema.marks[mark])(view.state, view.dispatch); view.focus(); return; }
  if (/^heading[1-6]$/.test(id)) {
    const level = Number(id.at(-1)), repeated = toggle && selectedBlocks().every(({ node }) => node.attrs.kind === 'heading' && node.attrs.level === level);
    setBlock({ kind: repeated ? 'paragraph' : 'heading', level: repeated ? null : level });
  } else if (/^body[1-3]$/.test(id)) {
    const size = ({ body1: '12', body2: '16', body3: '18' })[id];
    setBlock({ kind: 'paragraph', level: null, bodySize: toggle && selectedBlocks().every(({ node }) => node.attrs.kind === 'paragraph' && node.attrs.bodySize === size) ? null : size });
  }
  else {
    const kind = ({ codeBlock: 'code', checkedChecklist: 'checklist' })[id] || id;
    const repeat = toggle && kind !== 'paragraph' && selectedBlocks().every(({ node }) => node.attrs.kind === kind && (kind !== 'checklist' || node.attrs.checked === (id === 'checkedChecklist')));
    setBlock({ kind: repeat ? 'paragraph' : kind, checked: kind === 'checklist' ? id === 'checkedChecklist' : null, level: null, bodySize: null });
  }
}
function setMark(type, value) {
  const { state } = view, markType = state.schema.marks[type], tr = closeHistory(state.tr);
  if (state.selection.empty) {
    value == null ? tr.removeStoredMark(markType) : tr.addStoredMark(markType.create({ value }));
    if (type === 'highlightColor') tr.removeStoredMark(state.schema.marks.highlight);
  } else {
    tr.removeMark(state.selection.from, state.selection.to, markType);
    if (type === 'highlightColor') tr.removeMark(state.selection.from, state.selection.to, state.schema.marks.highlight);
    if (value != null) tr.addMark(state.selection.from, state.selection.to, markType.create({ value }));
  }
  view.dispatch(tr); view.focus();
}
function insertFragment(wire, { whole = false, hostToken } = {}) {
  const doc = fromNative(view.state.schema, wire, { newIDs: !whole });
  let tr = closeHistory(view.state.tr);
  if (whole) tr.replaceWith(0, tr.doc.content.size, doc.content);
  else if (doc.childCount === 1 && !wire.wholeBlocks) tr.replaceSelection(new Slice(doc.firstChild.content, 0, 0));
  else tr.replaceSelection(new Slice(doc.content, wire.wholeBlocks ? 0 : 1, wire.wholeBlocks ? 0 : 1));
  view.dispatch(hostHistory(tr, hostToken).scrollIntoView()); view.focus();
}
function updateEmbed(id, value) {
  const matches = [];
  view.state.doc.descendants((node, pos) => { if (node.type.name === 'wf_embed' && node.attrs.embed.id === id) matches.push({ node, pos }); });
  const found = matches[0]; if (!found) return false;
  const tr = closeHistory(view.state.tr).setNodeMarkup(found.pos, undefined, { ...found.node.attrs, embed: { ...found.node.attrs.embed, ...value } });
  // Older repeated DrawIO saves could leave duplicate copies of one drawing ID.
  if (found.node.attrs.embed.type === 'diagram') {
    for (const duplicate of matches.slice(1).reverse()) {
      const resolved = tr.doc.resolve(duplicate.pos), parent = resolved.parent;
      if (parent.childCount === 1 && tr.doc.childCount > 1) tr.delete(resolved.before(), resolved.before() + parent.nodeSize);
      else tr.delete(duplicate.pos, duplicate.pos + duplicate.node.nodeSize);
    }
  }
  view.dispatch(tr);
  return true;
}
function insertText(text) {
  const lines = String(text).split(/\r\n?|\n/);
  if (lines.length === 1) { view.dispatch(closeHistory(view.state.tr).insertText(text)); return; }
  const { state } = view, attrs = state.selection.$from.parent.attrs;
  const marks = state.storedMarks || state.selection.$from.marks();
  const blocks = lines.map(line => state.schema.nodes.wf_block.create({ ...attrs, id: uuid(), checklist: null,
    checked: attrs.kind === 'checklist' ? false : attrs.checked }, line ? state.schema.text(line, marks) : null));
  view.dispatch(closeHistory(state.tr).replaceSelection(new Slice(Fragment.from(blocks), 1, 1)).scrollIntoView());
}
function positionNearPoint(x, y) {
  const blocks = Array.from(view.dom.querySelectorAll('.wf-block-content'));
  if (!blocks.length) return 1;
  const last = blocks.at(-1).getBoundingClientRect();
  if (y > last.bottom) return TextSelection.atEnd(view.state.doc).from;
  let nearest = blocks[0], distance = Infinity;
  for (const element of blocks) {
    const rect = element.getBoundingClientRect(), next = Math.max(rect.top - y, y - rect.bottom, 0);
    if (next < distance) { nearest = element; distance = next; }
  }
  const rect = nearest.getBoundingClientRect();
  const hit = view.posAtCoords({ left: Math.max(rect.left + .5, Math.min(rect.right - .5, x)), top: Math.max(rect.top + .5, Math.min(rect.bottom - .5, y)) });
  return hit?.pos ?? 1;
}
function enter(state, dispatch) {
  const block = state.selection.$from.parent;
  if (state.selection.empty && emptyBlock(block) && ['bullet', 'ordered', 'checklist', 'quote', 'code'].includes(block.attrs.kind)) {
    if (isList(block.attrs) && block.attrs.indentLevel > 0) { adjustIndent(-1); return true; }
    setBlock({ kind: 'paragraph', checked: null }); return true;
  }
  return splitBlock(state, tr => {
    const at = tr.selection.$from.before(1), node = tr.doc.nodeAt(at);
    tr.setNodeMarkup(at, undefined, { ...block.attrs, id: uuid(),
      kind: block.attrs.kind === 'heading' || block.attrs.kind === 'divider' ? 'paragraph' : block.attrs.kind,
      level: ['heading', 'divider'].includes(block.attrs.kind) ? null : block.attrs.level,
      checked: block.attrs.kind === 'checklist' ? false : null, listStart: null, checklist: null, emptyRuns: true });
    dispatch(tr);
  });
}
function adjustIndent(delta) {
  const { state } = view, nodes = [], positions = [], selected = [];
  const end = state.selection.empty ? state.selection.to : state.selection.to - 1;
  state.doc.forEach((node, pos, index) => {
    nodes.push(node.attrs); positions.push(pos);
    if (pos + 1 <= end && pos + node.nodeSize - 1 >= state.selection.from) selected.push(index);
  });
  const changed = shiftedBlocks(nodes, selected, delta), tr = closeHistory(state.tr);
  changed.forEach((attrs, index) => { if (attrs !== nodes[index]) tr.setNodeMarkup(positions[index], undefined, attrs); });
  view.dispatch(tr.scrollIntoView()); view.focus();
}
function clearGhost(redraw = true) {
  ghostRequest += 1;
  if (!ghost.text) { if (redraw) ghostVersion += 1; return; }
  ghost = { text: '', anchor: -1, documentID: '', epoch: '' };
  ghostVersion += 1;
  if (redraw && view) view.dispatch(view.state.tr.setMeta('wfGhost', true));
}
function scheduleGhost() {
  clearTimeout(ghostTimer);
  clearGhost(false);
  if (!settings.ghostEnabled || settings.readOnly || loading || !current || !view || view.composing) return;
  const { selection } = view.state;
  if (!selection.empty) return;
  const before = selection.$from.parent.textBetween(0, selection.$from.parentOffset, '', '\uFFFC');
  if (before.length < 8) return;
  const request = ++ghostRequest, anchor = selection.head;
  const documentID = current.documentID, epoch = current.epoch;
  ghostTimer = setTimeout(() => {
    action('ghostRequest', { context: before.slice(-500), documentID, epoch, anchor, request });
  }, 900);
}
function acceptGhost() {
  const text = ghost.text;
  clearGhost(false);
  insertText(text);
}
function applyGhost(payload) {
  if (settings.readOnly || !view || !current || payload.documentID !== current.documentID
      || payload.epoch !== current.epoch || payload.request !== ghostRequest) return false;
  const text = String(payload.text || '').replace(/\s+/g, ' ').trim().slice(0, 80);
  if (!text || !view.state.selection.empty || view.state.selection.head !== payload.anchor) return false;
  ghost = { text, anchor: payload.anchor, documentID: payload.documentID, epoch: payload.epoch };
  ghostVersion += 1;
  view.dispatch(view.state.tr.setMeta('wfGhost', true));
  return true;
}
function handleKeyDown(_, event) {
  if (event.isComposing || view.composing) return false;
  if (popup && ['ArrowUp', 'ArrowDown', 'Enter', 'Escape'].includes(event.key)) {
    event.preventDefault(); popupKey(event.key); return true;
  }
  if (event.key === 'Escape') { if (ghost.text) { clearGhost(); return true; } if (painter) { painter = undefined; return true; } closePopups(); post({ event: 'escapePressed' }); return true; }
  if (!editable()) return false;
  const mod = event.metaKey || event.ctrlKey;
  if (mod && ['b', 'i', 'u'].includes(event.key.toLowerCase())) { format(({ b: 'bold', i: 'italic', u: 'underline' })[event.key.toLowerCase()]); return true; }
  if (mod && event.key.toLowerCase() === 'z') { command(event.shiftKey ? 'redo' : 'undo'); return true; }
  if (event.key === 'Tab' && !event.shiftKey && ghost.text && view.state.selection.empty) { acceptGhost(); return true; }
  if (event.key === 'Tab') { adjustIndent(event.shiftKey ? -1 : 1); return true; }
  // 正文第一行行首按左方向键：把焦点交还标题栏，与标题的回车/右方向键接力互补。
  if (event.key === 'ArrowLeft' && !event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey
      && view.state.selection.empty && view.state.selection.$from.pos === 1) {
    post({ event: 'leftEdgePressed' }); return true;
  }
  if (event.key === 'Enter' && !event.shiftKey) return enter(view.state, view.dispatch);
  if (event.key === 'Backspace' && view.state.selection.empty && view.state.selection.$from.parentOffset === 0) {
    if (blockAt().attrs.indentLevel > 0) { adjustIndent(-1); return true; }
    if (blockAt().attrs.kind !== 'paragraph') { setBlock({ kind: 'paragraph', level: null, checked: null }); return true; }
    return joinBackward(view.state, view.dispatch, view);
  }
  return false;
}
function markdownRules() {
  const block = (pattern, attrs) => new InputRule(pattern, (state, match, start, end) => {
    if (state.selection.$from.parent.attrs.kind === 'code') return null;
    const pos = state.selection.$from.before(1);
    return closeHistory(state.tr).delete(start, end).setNodeMarkup(pos, undefined, { ...state.selection.$from.parent.attrs, ...attrs(match) });
  });
  const inline = (pattern, name) => new InputRule(pattern, (state, match, start, end) => {
    if (state.selection.$from.parent.attrs.kind === 'code') return null;
    if (['italic', 'underline'].includes(name) && start > state.selection.$from.start() && state.doc.textBetween(start - 1, start) === match[0][0]) return null;
    const mark = state.schema.marks[name].create();
    return closeHistory(state.tr).insertText(match[1], start, end).addMark(start, start + match[1].length, mark).addStoredMark(mark);
  });
  const divider = new InputRule(/^(?:-{3,}|\*{3,}|_{3,})$/, (state, match, start, end) => {
    const parent = state.selection.$from.parent;
    if (parent.attrs.kind === 'code' || end !== state.selection.$from.end()) return null;
    const pos = state.selection.$from.before(1), next = pos + parent.nodeSize;
    const line = state.schema.nodes.wf_block.create({ ...parent.attrs, kind: 'divider' }, state.schema.text('\uFFFC'));
    const nodes = [line];
    if (next === state.doc.content.size) nodes.push(state.schema.nodes.wf_block.create({ id: uuid(), kind: 'paragraph' }));
    const tr = closeHistory(state.tr).replaceWith(pos, next, nodes);
    return tr.setSelection(TextSelection.near(tr.doc.resolve(pos + line.nodeSize + 1)));
  });
  const link = new InputRule(/\[([^\]]+)\]\(([^\s()]+)\)$/, (state, match, start, end) => {
    if (state.selection.$from.parent.attrs.kind === 'code') return null;
    return closeHistory(state.tr).insertText(match[1], start, end)
      .addMark(start, start + match[1].length, state.schema.marks.link.create({ value: match[2] }));
  });
  return inputRules({ rules: [
    divider,
    block(/^(#{1,6})\s$/, match => ({ kind: 'heading', level: match[1].length })),
    block(/^[-*+]\s$/, () => ({ kind: 'bullet' })), block(/^(\d+)\.\s$/, match => ({ kind: 'ordered', listStart: Number(match[1]) })),
    block(/^\[([ xX])\]\s$/, match => ({ kind: 'checklist', checked: match[1].toLowerCase() === 'x' })),
    block(/^>\s$/, () => ({ kind: 'quote' })), block(/^`{3,}$/, () => ({ kind: 'code' })),
    inline(/\*\*([^*]+)\*\*$/, 'bold'), inline(/__([^_]+)__$/, 'bold'), inline(/~~([^~]+)~~$/, 'strikethrough'),
    inline(/`([^`]+)`$/, 'code'), inline(/==([^=]+)==$/, 'highlight'), inline(/::([^:]+)::$/, 'highlight'),
    inline(/\*([^*]+)\*$/, 'italic'), inline(/_([^_]+)_$/, 'italic'), inline(/~([^~]+)~$/, 'underline'), link,
  ] });
}
const integration = $prose(() => new Plugin({
  appendTransaction(transactions, old, state) {
    for (const tr of transactions) for (const step of tr.steps) {
      if (step instanceof HostHistoryStep && !loading) { pendingHostToken = step.token; lastOperation = step.operation; }
    }
    if (!transactions.some(tr => tr.docChanged)) return null;
    const seen = new Set(), tr = state.tr;
    const empties = [];
    state.doc.forEach((node, pos) => {
      if (!emptyBlock(node)) node.forEach((child, offset) => { if (child.type.name === 'wf_empty') empties.push({ from: pos + 1 + offset, to: pos + 1 + offset + child.nodeSize }); });
    });
    for (const range of empties.reverse()) tr.delete(range.from, range.to);
    tr.doc.forEach((node, pos) => {
      if (!node.attrs.id || seen.has(node.attrs.id)) tr.setNodeMarkup(pos, undefined, { ...node.attrs, id: uuid(), checklist: null, checked: node.attrs.kind === 'checklist' ? false : node.attrs.checked });
      seen.add(tr.doc.nodeAt(pos).attrs.id);
    });
    const boundary = historyBoundary(transactions, state);
    if (tr.docChanged) return (boundary ? closeHistory(tr) : tr).setMeta('addToHistory', false);
    return boundary;
  },
  props: {
    handleKeyDown,
    handleScrollToSelection() { if (!settings.grows) return false; revealSelection(); return true; },
    handleDOMEvents: {
      copy: (_, event) => copySelection(event, false), cut: (_, event) => copySelection(event, true),
      paste: (_, event) => { if (!editable()) return false; event.preventDefault(); action('paste'); return true; },
      drop: (_, event) => { if (!editable() || !event.dataTransfer?.files?.length) return false;
        event.preventDefault(); const hit = view.posAtCoords({ left: event.clientX, top: event.clientY });
        if (hit) view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(hit.pos))));
        Promise.all(Array.from(event.dataTransfer.files).map(file => new Promise(resolve => { const reader = new FileReader(); reader.onload = () => resolve({ name: file.name, data: String(reader.result).split(',')[1] }); reader.readAsDataURL(file); })))
          .then(files => action('dropFiles', { files })); return true; },
      focus: () => { post({ event: 'focusChanged', focused: true }); return false; },
      blur: () => { post({ event: 'focusChanged', focused: false }); return false; },
      contextmenu: (_, event) => { event.preventDefault(); showContextMenu(event.clientX, event.clientY); return true; },
    },
    decorations(state) {
      const head = state.selection.empty ? state.selection.head : -1;
      if (syntaxDocument === state.doc && renderedGhostVersion === ghostVersion && renderedGhostAnchor === head) return syntaxDecorations;
      const decorations = [];
      state.doc.forEach((node, pos) => {
        if (node.attrs.kind === 'code' && node.textContent.trim()) {
          try {
            let cached = syntaxCache.get(node.attrs.id);
            if (cached?.text !== node.textContent) {
              const result = hljs.highlightAuto(node.textContent), template = document.createElement('div'); template.innerHTML = result.value;
              cached = { text: node.textContent, spans: [] }; let offset = 0;
              const walk = (dom, classes = '') => {
                if (dom.nodeType === 3) { if (classes && dom.textContent.length) cached.spans.push({ from: offset, to: offset + dom.textContent.length, classes }); offset += dom.textContent.length; }
                else for (const child of dom.childNodes) walk(child, [classes, dom.className || ''].filter(Boolean).join(' '));
              };
              walk(template); syntaxCache.set(node.attrs.id, cached);
            }
            for (const span of cached.spans) decorations.push(Decoration.inline(pos + 1 + span.from, pos + 1 + span.to, { class: span.classes }));
          } catch (_) {}
        }
        // 行内日期只加视图层装饰，不进文档模型，也不影响按块差量提交。
        if (settings.inlineDateReminders !== false) {
          let spans = dateSpansCache.get(node);
          if (spans === undefined) {
            spans = []; let offset = 0;
            node.forEach(child => {
              if (child.isText) {
                INLINE_DATE.lastIndex = 0;
                for (let match; (match = INLINE_DATE.exec(child.text)); ) {
                  spans.push({ start: offset + match.index, end: offset + match.index + match[0].length });
                  if (!match[0].length) break;
                }
              }
              offset += child.nodeSize;
            });
            dateSpansCache.set(node, spans);
          }
          for (const span of spans) decorations.push(Decoration.inline(pos + 1 + span.start, pos + 1 + span.end, { class: 'wf-inline-date' }));
        }
      });
      if (ghost.text && head === ghost.anchor && ghost.documentID === current?.documentID && ghost.epoch === current?.epoch && !settings.readOnly) {
        decorations.push(Decoration.widget(head, () => {
          const element = document.createElement('span');
          element.className = 'wf-ghost'; element.textContent = ghost.text; element.contentEditable = 'false';
          return element;
        }, { side: 1, key: 'wf-ghost', ignoreSelection: true, marks: [] }));
      }
      syntaxDocument = state.doc; renderedGhostVersion = ghostVersion; renderedGhostAnchor = head;
      syntaxDecorations = DecorationSet.create(state.doc, decorations); return syntaxDecorations;
    },
  },
  view: () => ({ update: (next, previous) => {
    const changed = !loading && current && !next.state.doc.eq(previous.doc);
    if (changed) commitSoon();
    if (changed) scheduleGhost();
    else if (ghost.text && next.state.selection.head !== ghost.anchor) clearGhost();
    queueMicrotask(updateUI);
  } }),
}));

function copySelection(event, cutting) {
  if (!current || view.state.selection.empty) return false;
  event.preventDefault(); const selection = snapshot();
  event.clipboardData?.setData('text/plain', selection.text);
  action('copy', { doc: selection.fragment, ...clipboardBoundaries(view.state.selection) });
  if (cutting && editable()) view.dispatch(closeHistory(view.state.tr).deleteSelection());
  return true;
}

class BlockView {
  constructor(node, _, getPos) {
    this.node = node; this.getPos = getPos;
    this.dom = document.createElement('div'); this.dom.dataset.wfBlock = '';
    this.gutter = button('⋮⋮', '段落操作', () => showBlockMenu(this)); this.gutter.className = 'wf-block-handle';
    this.marker = button('', '切换检查项', () => {
      if (!editable() || this.node.attrs.kind !== 'checklist') return;
      const checked = !this.node.attrs.checked;
      view.dispatch(closeHistory(view.state.tr).setNodeMarkup(getPos(), undefined, { ...this.node.attrs, checked,
        checklist: { ...(this.node.attrs.checklist || {}), completedAt: checked ? nativeTime() : null } }));
    }); this.marker.className = 'wf-marker';
    this.contentDOM = document.createElement('div'); this.contentDOM.className = 'wf-block-content';
    this.reminder = button('♧', '设置检查项提醒', () => {
      if (!editable()) return;
      const rect = this.reminder.getBoundingClientRect();
      action('reminder', { blockID: this.node.attrs.id, rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height } });
    }); this.reminder.className = 'wf-reminder';
    this.dom.append(this.gutter, this.marker, this.contentDOM, this.reminder); this.update(node);
  }
  update(node) {
    if (node.type.name !== 'wf_block') return false;
    this.node = node;
    const attrs = node.attrs;
    this.dom.dataset.blockId = attrs.id || ''; this.dom.dataset.kind = attrs.kind;
    this.dom.className = `wf-block wf-${attrs.kind}${attrs.checked ? ' wf-checked' : ''}${emptyBlock(node) ? ' wf-is-empty' : ''}`;
    this.dom.style.setProperty('--indent', attrs.indentLevel || 0);
    this.dom.style.textAlign = attrs.align || 'left';
    this.contentDOM.style.fontSize = attrs.kind === 'heading' ? `${attrs.level === 1 ? 18 : attrs.level === 2 ? 16 : 14}px` : attrs.bodySize ? `${attrs.bodySize}px` : '';
    this.marker.textContent = attrs.kind === 'bullet' ? '•' : attrs.kind === 'checklist' ? (attrs.checked ? '✓' : '') : attrs.kind === 'ordered' ? '1.' : '';
    this.marker.disabled = !editable(); this.marker.tabIndex = -1;
    this.marker.setAttribute('role', attrs.kind === 'checklist' ? 'checkbox' : 'presentation');
    this.marker.setAttribute('aria-checked', String(!!attrs.checked));
    this.marker.setAttribute('aria-label', `${attrs.checked ? '取消完成' : '完成'}：${node.textContent || '空白检查项'}`);
    this.gutter.textContent = node.content.size === 0 ? '+' : attrs.kind === 'heading' ? `H${attrs.level}` : '⋮⋮';
    this.gutter.hidden = !editable();
    this.reminder.hidden = !editable() || attrs.kind !== 'checklist' || !settings.checklistReminders;
    this.reminder.classList.toggle('has-reminder', attrs.checklist?.reminderAt != null);
    this.contentDOM.dataset.placeholder = settings.placeholder || '';
    return true;
  }
  stopEvent(event) { return !!event.target.closest('button'); }
  ignoreMutation(mutation) { return mutation.type !== 'selection' && !this.contentDOM.contains(mutation.target); }
}

class EmbedView {
  constructor(node, _, getPos) {
    this.node = node; this.getPos = getPos; this.dom = document.createElement('span');
    this.dom.className = 'wf-embed'; this.dom.contentEditable = 'false'; this.render();
  }
  render() {
    this.dom.replaceChildren(); const embed = this.node.attrs.embed;
    this.dom.dataset.embedId = embed.id; this.dom.dataset.type = embed.type;
    if (embed.type === 'table') { this.renderTable(); return; }
    if (embed.type === 'formula') { this.renderFormula(); return; }
    if (embed.src && (embed.type === 'diagram' || embed.image)) {
      const image = document.createElement('img'); image.src = embed.src; image.alt = image.title = embed.name || '图片';
      if (embed.width) image.style.width = `${embed.width}px`;
      if (embed.height) image.style.height = `${embed.height}px`;
      image.addEventListener('load', reportHeight);
      image.addEventListener('dblclick', event => { event.preventDefault(); const editing = embed.type === 'diagram' && editable(); action(editing ? 'editDiagram' : 'previewImage', { id: editing ? embed.id : embed.assetKey || embed.id }); });
      this.dom.append(image);
      if (editable() && embed.type === 'attachment' && embed.image) {
        const handle = button('', '拖动调整图片大小', () => {}); handle.className = 'wf-image-resize';
        handle.addEventListener('pointerdown', event => {
          event.preventDefault(); event.stopPropagation(); handle.setPointerCapture(event.pointerId);
          const width = image.getBoundingClientRect().width, ratio = image.naturalWidth / image.naturalHeight || 1, x = event.clientX;
          let next = width;
          const move = value => { next = Math.max(48, Math.min(1600, width + value.clientX - x)); image.style.width = `${next}px`; image.style.height = `${next / ratio}px`; reportHeight(); };
          const end = () => { handle.removeEventListener('pointermove', move); handle.removeEventListener('pointerup', end); updateEmbed(embed.id, { width: next, height: next / ratio }); };
          handle.addEventListener('pointermove', move); handle.addEventListener('pointerup', end, { once: true });
        });
        this.dom.append(handle);
      }
    } else {
      this.dom.append(button(`▧ ${embed.name || '附件'}`, embed.name || '打开附件', () => action('openAttachment', { id: embed.assetKey || embed.id })));
    }
  }
  renderTable() {
    const embed = this.node.attrs.embed, rows = embed.rows || [['']], table = document.createElement('table');
    this.dom.classList.add('wf-table-wrap');
    rows.forEach((row, r) => {
      const tr = document.createElement('tr');
      row.forEach((text, c) => {
        const td = document.createElement('td'), field = document.createElement('textarea'); field.value = text;
        field.readOnly = !editable(); field.spellcheck = !!settings.spellChecking; field.rows = Math.max(1, text.split('\n').length); field.setAttribute('aria-label', `表格第${r + 1}行第${c + 1}列`);
        field.addEventListener('input', () => {
          const next = structuredClone(this.node.attrs.embed.rows); next[r][c] = field.value;
          field.rows = Math.max(1, field.value.split('\n').length); updateEmbed(embed.id, { rows: next }); reportHeight();
        });
        field.addEventListener('focus', () => post({ event: 'focusChanged', focused: true }));
        field.addEventListener('keydown', event => {
          if (event.key !== 'Tab') return;
          event.preventDefault(); const fields = Array.from(this.dom.querySelectorAll('textarea')), index = fields.indexOf(field) + (event.shiftKey ? -1 : 1);
          if (fields[index]) fields[index].focus();
        });
        td.append(field); tr.append(td);
      }); table.append(tr);
    });
    this.dom.append(table);
    if (editable()) {
      const controls = document.createElement('span'); controls.className = 'wf-embed-controls';
      controls.append(button('+ 行', '增加一行', () => { const current = this.node.attrs.embed.rows; updateEmbed(embed.id, { rows: [...current, current[0].map(() => '')] }); }),
        button('+ 列', '增加一列', () => updateEmbed(embed.id, { rows: this.node.attrs.embed.rows.map(row => [...row, '']) })),
        button('− 行', '删除最后一行', () => { const current = this.node.attrs.embed.rows; if (current.length > 1) updateEmbed(embed.id, { rows: current.slice(0, -1) }); }),
        button('− 列', '删除最后一列', () => { const current = this.node.attrs.embed.rows; if (current[0].length > 1) updateEmbed(embed.id, { rows: current.map(row => row.slice(0, -1)) }); }));
      this.dom.append(controls);
    }
  }
  renderFormula() {
    const embed = this.node.attrs.embed, preview = document.createElement('span'); preview.className = 'wf-formula-preview';
    katex.render(embed.latex || '', preview, { throwOnError: false, strict: false, trust: false }); this.dom.append(preview);
    if (editable()) {
      const input = document.createElement('input'); input.value = embed.latex || ''; input.spellcheck = false; input.setAttribute('aria-label', 'LaTeX 公式');
      input.addEventListener('compositionstart', () => { input.dataset.composing = 'true'; });
      input.addEventListener('compositionend', () => { delete input.dataset.composing; this.syncFormulaInput(); });
      input.addEventListener('input', () => updateEmbed(embed.id, { latex: input.value }));
      input.addEventListener('focus', () => post({ event: 'focusChanged', focused: true }));
      this.dom.append(input);
    }
  }
  syncFormulaInput() {
    const input = this.dom.querySelector('input'), value = this.node.attrs.embed.latex || '';
    if (!input || input.dataset.composing || input.value === value) return;
    const focused = input === document.activeElement, from = input.selectionStart, to = input.selectionEnd;
    input.value = value;
    if (focused) input.setSelectionRange(Math.min(from ?? value.length, value.length), Math.min(to ?? value.length, value.length));
  }
  update(node) {
    if (node.type.name !== 'wf_embed') return false;
    const old = this.node.attrs.embed, embed = node.attrs.embed; this.node = node;
    if (old.type !== embed.type || old.id !== embed.id) return false;
    if (embed.type === 'formula' && this.dom.contains(document.activeElement)) {
      katex.render(embed.latex || '', this.dom.querySelector('.wf-formula-preview'), { throwOnError: false, strict: false }); this.syncFormulaInput(); return true;
    }
    if (embed.type === 'table' && old.rows?.length === embed.rows?.length && old.rows?.[0]?.length === embed.rows?.[0]?.length) {
      const fields = this.dom.querySelectorAll('textarea');
      embed.rows.flat().forEach((text, index) => { if (fields[index]) { if (fields[index].value !== text) fields[index].value = text; fields[index].rows = Math.max(1, text.split('\n').length); } }); return true;
    }
    if (JSON.stringify(old) !== JSON.stringify(embed)) this.render();
    return true;
  }
  stopEvent(event) { return !!event.target.closest('button, input, textarea, table') || event.type.startsWith('pointer'); }
  ignoreMutation() { return true; }
}

function updateNumbering() {
  const doc = view.state.doc;
  if (numberedDocument === doc) return;
  numberedDocument = doc;
  const nodes = doc.content.content, blocks = nodes.map(node => node.attrs), numbers = listNumbers(blocks);
  // 编号向后传播：只有第一个节点变化的块及其之后的编号才可能改动。
  let firstChanged = -1;
  for (let index = 0; index < nodes.length; index++) {
    if (nodes[index] !== numberedNodes[index]) { firstChanged = index; break; }
  }
  const markers = new Map();
  blocks.forEach((attrs, index) => {
    if (numbers[index] == null) return;
    markers.set(attrs.id, numbers[index]);
    if (firstChanged >= 0 && index < firstChanged) return;
    // 块节点被重建（新插入或 nodeView 重绘）时，即使编号相同也要写回 DOM。
    if (nodes[index] === numberedNodes[index] && numberedMarkers.get(attrs.id) === numbers[index]) return;
    const marker = document.querySelector(`[data-block-id="${attrs.id}"] .wf-marker`);
    if (marker) marker.textContent = `${numbers[index]}.`;
  });
  numberedNodes = nodes.slice(); numberedMarkers = markers;
}
const toolbar = document.createElement('div'); toolbar.id = 'wf-selection'; toolbar.hidden = true;
document.body.append(toolbar);
// 拖动选字期间压住浮条：selectionChanged 在拖动中持续触发，松开鼠标才算选完。
let pointerSelecting = false;
function updateToolbar() {
  if (!view || view.state.selection.empty || !editable() || !settings.selectionToolbar || view.composing || pointerSelecting) { toolbar.hidden = true; reportRegions(); return; }
  toolbar.replaceChildren();
  for (const [text, name, title] of [['B', 'bold', '加粗'], ['I', 'italic', '斜体'], ['U', 'underline', '下划线'], ['S', 'strikethrough', '删除线'], ['▰', 'highlight', '高亮']]) toolbar.append(button(text, title, () => format(name)));
  for (const item of settings.selectionActions || []) toolbar.append(button(item.title, item.title, () => action('selectionAction', { id: item.id, selection: snapshot() })));
  toolbar.hidden = false;
  const rect = view.coordsAtPos(view.state.selection.from), tail = view.coordsAtPos(view.state.selection.to), bounds = visibleBounds();
  toolbar.style.left = `${Math.max(4, Math.min(rect.left, innerWidth - toolbar.offsetWidth - 4))}px`;
  // 第一行选字时上方放不下：翻到选区下方，别钳到容器顶部压住第一行文字。
  // 跨行选区以末尾行的下沿为锚，浮条不会落在选区中间。
  const height = toolbar.offsetHeight, above = rect.top - height - 6, below = tail.bottom + 6;
  const limit = bounds.bottom - height - 4;
  const preferred = above >= bounds.top + 4 ? Math.min(above, limit) : below;
  toolbar.style.top = `${Math.max(bounds.top + 4, Math.min(preferred, limit))}px`;
  reportRegions();
}
function visibleBounds() { return settings.viewport || { top: 0, bottom: innerHeight }; }
function closePopups() {
  if (!popup) return;
  popup = undefined; post({ event: 'popupChanged' });
}
function openMenu(items, anchor, choose, query = '') {
  closePopups(); if (!items.length) return;
  popup = { session: ++popupSession, items, selected: 0, choose, query, anchor };
  paintMenu();
}
function menuState() {
  if (!popup) return null;
  const rect = typeof popup.anchor === 'function' ? popup.anchor() : popup.anchor;
  return { session: popup.session, items: popup.items, selected: popup.selected, query: popup.query,
    anchor: { x: rect.left, y: rect.top ?? rect.bottom, width: Math.max(1, (rect.right ?? rect.left) - rect.left), height: Math.max(1, rect.bottom - (rect.top ?? rect.bottom)) } };
}
function paintMenu() { if (popup) post({ event: 'popupChanged', popup: menuState() }); }
function chooseMenu(index) { const selected = popup?.items[index], choose = popup?.choose; closePopups(); if (selected) choose(selected); }
function popupKey(key) {
  if (!popup) return;
  if (key === 'Escape') { closePopups(); return; }
  if (key === 'Enter') { chooseMenu(popup.selected); return; }
  popup.selected = (popup.selected + (key === 'ArrowDown' ? 1 : -1) + popup.items.length) % popup.items.length; paintMenu();
}
function runMenuCommand(item, range) {
  if (range) view.dispatch(view.state.tr.delete(range.from, range.to));
  if (item.id.startsWith('format.')) format(item.id.slice(7), false);
  else if (item.id === 'shared.divider') command('insertDivider');
  else action('command', { id: item.id });
}
function showBlockMenu(blockView) {
  if (!editable()) return;
  const pos = blockView.getPos(); view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(pos + 1))));
  openMenu(settings.blockCommands || [], () => blockView.gutter.getBoundingClientRect(), item => runMenuCommand(item));
}
function updateSuggestions() {
  if (!editable() || view.composing || !view.state.selection.empty) { if (popup?.query) closePopups(); return; }
  const selection = view.state.selection, before = selection.$from.parent.textBetween(0, selection.$from.parentOffset, '', '\uFFFC');
  const match = before.match(/(?:^|\s)([/#~@])([^/#~@\n]*)$/);
  if (!match) { if (popup?.query) closePopups(); return; }
  const trigger = match[1], query = match[2], token = trigger + query;
  if (popup?.query === token) return;
  let items;
  if (trigger === '/') items = (settings.commands || []).filter(item => (item.title + ' ' + (item.keywords || '')).toLowerCase().includes(query.toLowerCase()));
  else if (trigger === '@') items = (settings.mentions || []).filter(item => item.title.toLowerCase().includes(query.toLowerCase()));
  else items = (trigger === '#' ? settings.tags || [] : settings.lists || []).filter(item => item.toLowerCase().includes(query.toLowerCase())).map(title => ({ title }));
  const from = selection.from - token.length, to = selection.from;
  openMenu(items, () => view.coordsAtPos(view.state.selection.from), item => {
    if (trigger === '/') runMenuCommand(item, { from, to });
    else if (trigger === '@') {
      // 提及插入为带链接的 run（workfollow://task|note/<id>），触发字符与
      // 标题整体着链，尾随空格不着链。打开浮层的 reverse 面板扫这份链接。
      const tr = view.state.tr.insertText(`${trigger}${item.title} `, from, to);
      tr.addMark(from, from + trigger.length + item.title.length,
        view.state.schema.marks.link.create({ value: `workfollow://${item.kind}/${item.id}` }));
      view.dispatch(tr); view.focus();
    }
    else { view.dispatch(view.state.tr.insertText(`${trigger}${item.title} `, from, to)); action(trigger === '#' ? 'tagInserted' : 'listInserted', { value: item.title }); view.focus(); }
  }, token);
}
function showContextMenu(x, y) {
  const items = [{ id: 'copy', title: '复制' }];
  if (editable()) items.push({ id: 'cut', title: '剪切' }, { id: 'paste', title: '粘贴' }, ...((settings.selectionActions || []).map(item => ({ id: `selection:${item.id}`, title: item.title }))));
  openMenu(items, { left: x, bottom: y }, item => {
    if (item.id.startsWith('selection:')) action('selectionAction', { id: item.id.slice(10), selection: snapshot() });
    else if (item.id === 'paste') action('paste');
    else { action('copy', { doc: selectionDocument(view.state), ...clipboardBoundaries(view.state.selection) }); if (item.id === 'cut') view.dispatch(closeHistory(view.state.tr).deleteSelection()); }
  });
}
function reportRegions() {
  const regions = [toolbar.hidden ? null : toolbar].filter(Boolean).map(element => { const rect = element.getBoundingClientRect(); return { x: rect.x, y: rect.y, width: rect.width, height: rect.height }; });
  post({ event: 'scrollRegionsChanged', regions });
}
function reportHeight() {
  const measured = document.getElementById('root')?.scrollHeight || 56;
  if (Math.abs(measured - height) > 0.5) { height = measured; post({ event: 'heightChanged', height }); }
}
function configure(next) {
  if (Object.keys(next).length === 1 && next.viewport) {
    settings.viewport = next.viewport; updateToolbar(); return;
  }
  const readOnlyChanged = Object.hasOwn(next, 'readOnly') && !!next.readOnly !== !!settings.readOnly;
  settings = { ...settings, ...next };
  document.body.classList.toggle('wf-grows', !!settings.grows); document.body.classList.toggle('wf-readonly', !!settings.readOnly);
  const css = document.documentElement.style;
  css.setProperty('--wf-body-size', `${settings.bodyFontSize || 14}px`);
  css.setProperty('--wf-paragraph-spacing', `${settings.paragraphSpacing ?? 10}px`);
  css.setProperty('--wf-marker-left', `${(settings.markerLeft ?? 5) - 5}px`);
  if (settings.textColor) css.setProperty('--wf-text', settings.textColor);
  if (settings.accentColor) css.setProperty('--wf-accent', settings.accentColor);
  document.documentElement.dataset.appearance = settings.dark ? 'dark' : 'light';
  if (view) {
    const props = { editable: () => !settings.readOnly,
      attributes: { ...view.props.attributes, spellcheck: String(!!settings.spellChecking) } };
    if (readOnlyChanged) props.nodeViews = { ...view.props.nodeViews,
      wf_block: (node, owner, getPos) => new BlockView(node, owner, getPos),
      wf_embed: (node, owner, getPos) => new EmbedView(node, owner, getPos) };
    view.setProps(props);
    view.dom.spellcheck = !!settings.spellChecking;
    for (const field of document.querySelectorAll('.wf-embed input, .wf-embed textarea')) {
      field.readOnly = !!settings.readOnly; field.spellcheck = field.tagName === 'TEXTAREA' && !!settings.spellChecking;
    }
    const blocks = new Map(view.state.doc.content.content.map(node => [node.attrs.id, node]));
    for (const element of document.querySelectorAll('[data-wf-block]')) {
      const desc = blocks.get(element.dataset.blockId);
      if (desc) { element.querySelector('.wf-marker').disabled = !!settings.readOnly; element.querySelector('.wf-block-handle').hidden = !!settings.readOnly; element.querySelector('.wf-reminder').hidden = !!settings.readOnly || !settings.checklistReminders || desc.attrs.kind !== 'checklist'; }
    }
  }
  reportHeight();
}
function command(name, payload = {}) {
  if (!view) return false;
  if (['popupChoose', 'popupHover', 'popupDismiss'].includes(name)) {
    if (!popup || payload.session !== popup.session) return false;
    clearTimeout(hoverTimer);
    if (name === 'popupDismiss') closePopups();
    else if (name === 'popupChoose') chooseMenu(payload.index);
    else if (payload.index >= 0 && payload.index < popup.items.length && payload.index !== popup.selected) { popup.selected = payload.index; paintMenu(); }
    return true;
  }
  if (name === 'focus') { view.focus(); return true; }
  // 标题回车接力：光标落到正文第一行末尾；第一行没字时就是第一行的行首。
  if (name === 'focusFirstLine') {
    const first = view.state.doc.firstChild, end = first ? 1 + first.content.size : 1;
    view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(end))).scrollIntoView());
    view.focus(); if (settings.grows) revealSelection(); return true;
  }
  // 标题右方向键接力：光标落到正文第一行行首。
  if (name === 'focusFirstLineStart') {
    view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(1))).scrollIntoView());
    view.focus(); if (settings.grows) revealSelection(); return true;
  }
  // 原生差量缓存缺口时的恢复通道：作废基线并重发全量。
  if (name === 'reloadDocument') { sentBlocks = null; sentOrder = null; commitNow(); return true; }
  if (name === 'focusEnd') { view.dispatch(view.state.tr.setSelection(TextSelection.atEnd(view.state.doc)).scrollIntoView()); view.focus(); if (settings.grows) revealSelection(); return true; }
  if (name === 'select') { view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, payload.from, payload.to ?? payload.from))); return true; }
  if (name === 'selectPlain') {
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc,
      positionForPlainOffset(view.state.doc, payload.from), positionForPlainOffset(view.state.doc, payload.to ?? payload.from)))); return true;
  }
  if (name === 'revealBlock') {
    let position = 0;
    for (let index = 0; index < Math.min(payload.index, view.state.doc.childCount - 1); index++) position += view.state.doc.child(index).nodeSize;
    view.dispatch(view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(position + 1))).scrollIntoView());
    if (settings.grows) revealSelection(); return true;
  }
  if (name === 'search') {
    const needle = String(payload.query || '').toLowerCase(), index = plainText(view.state.doc).toLowerCase().indexOf(needle);
    if (!needle || index < 0) return false;
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc,
      positionForPlainOffset(view.state.doc, index), positionForPlainOffset(view.state.doc, index + needle.length))).scrollIntoView());
    if (settings.grows) revealSelection(); return true;
  }
  if (!editable()) return false;
  switch (name) {
    case 'hostPointer': {
      if (payload.phase === 'up') { pointerAnchor = undefined; break; }
      closePopups();
      const position = positionNearPoint(payload.x, payload.y), previous = view.state.selection;
      if (payload.phase === 'down') pointerAnchor = payload.shift ? previous.anchor : position;
      let from = pointerAnchor ?? position, to = position;
      if (payload.clickCount >= 3) { const resolved = view.state.doc.resolve(position); from = resolved.start(); to = resolved.end(); }
      view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, from, to))); break;
    }
    case 'undo': lastOperation = 'undo'; return undo(view.state, view.dispatch);
    case 'redo': lastOperation = 'redo'; return redo(view.state, view.dispatch);
    case 'format': format(payload.id); break;
    case 'indent': adjustIndent(payload.delta); break;
    case 'align': setBlock({ align: payload.value }); break;
    case 'color': setMark('textColor', payload.value); break;
    case 'highlight': setMark('highlightColor', payload.value); break;
    case 'link': setMark('link', payload.value); break;
    case 'clear': { const { from, to } = view.state.selection; view.dispatch(closeHistory(view.state.tr).removeMark(from, to)); setBlock({ kind: 'paragraph', level: null, checked: null, bodySize: null, align: null, indentLevel: 0, listStart: null }); break; }
    case 'insertText': insertText(payload.text); break;
    case 'insertDivider': {
      const schema = view.state.schema;
      const nodes = [schema.nodes.wf_block.create({ id: uuid(), kind: 'divider' }, schema.text('\uFFFC')),
        schema.nodes.wf_block.create({ id: uuid(), kind: 'paragraph' })];
      view.dispatch(closeHistory(view.state.tr).replaceSelection(new Slice(Fragment.from(nodes), 0, 0)).scrollIntoView()); break;
    }
    case 'insertFragment': insertFragment(payload.doc, payload); break;
    case 'replaceDocument': insertFragment(payload.doc, { ...payload, whole: true }); break;
    case 'updateEmbed': return updateEmbed(payload.id, payload.value);
    case 'captureStyle': painter = snapshot().style; return true;
    case 'cancelPainter': painter = undefined; return true;
    case 'applyStyle': {
      const style = payload.style || painter; if (!style) return false;
      setBlock({ kind: style.blockToken?.startsWith('h') ? 'heading' : style.blockToken === 'checked' ? 'checklist' : style.blockToken, level: Number(style.blockToken?.slice(1)) || null,
        checked: style.blockToken === 'checked' ? true : style.blockToken === 'checklist' ? false : null,
        align: style.align, bodySize: style.bodySize, indentLevel: style.indentLevel || 0 });
      const { from, to } = view.state.selection; let tr = view.state.tr.removeMark(from, to);
      for (const mark of style.marks || []) if (view.state.schema.marks[mark.type]) tr.addMark(from, to, view.state.schema.marks[mark.type].create({ value: mark.value }));
      view.dispatch(tr); painter = undefined; break;
    }
    default: return false;
  }
  view.focus(); return true;
}
window.workfollowEditor = {
  load(packet) {
    if (!view) return false;
    loading = true; pendingCommit = false; closePopups(); painter = undefined;
    clearTimeout(ghostTimer); clearGhost(false);
    sentBlocks = null; sentOrder = null; // 基线作废：下一次提交转全量，原生同步重建块缓存
    const same = current?.documentID === packet.documentID;
    pendingHostToken = undefined; lastOperation = undefined;
    if (!same) { syntaxCache.clear(); syntaxDocument = undefined; syntaxDecorations = undefined; }
    current = { documentID: packet.documentID, epoch: packet.epoch }; revision = 0; lastCommit = undefined;
    const doc = fromNative(view.state.schema, packet.doc);
    if (same) {
      view.updateState(view.state.apply(synchronizeDocument(view.state, doc)));
    } else view.updateState(EditorState.create({ schema: view.state.schema, doc, plugins: view.state.plugins }));
    configure(packet.settings || {}); loading = false;
    post({ event: 'loaded', revision }); updateUI(); return true;
  },
  configure, command,
  flush() {
    if (pendingCommit) { pendingCommit = false; commitNow(); }
    return { ...lastCommit, documentID: current?.documentID, epoch: current?.epoch, revision, doc: view ? toNative(view.state.doc) : { blocks: [] } };
  },
  getDoc() { return view ? toNative(view.state.doc) : null; },
  getSelection() { return view ? snapshot() : null; },
  getMenu: menuState,
  ghostState: () => ({ request: ghostRequest, anchor: view?.state.selection.head ?? -1,
    documentID: current?.documentID, epoch: current?.epoch, text: ghost.text }),
  serializeCount: getSerializeCount,
  applyGhost,
  applySelection(payload) {
    if (!editable() || payload.documentID !== current.documentID || payload.epoch !== current.epoch || payload.revision !== revision) return false;
    const { from, to } = payload;
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, payload.inserting ? to : from, to)));
    if (payload.doc) insertFragment(payload.doc);
    else command('insertText', { text: (payload.inserting ? '\n' : '') + payload.text }); return true;
  },
};
document.addEventListener('pointerdown', event => {
  if (!event.target.closest('.wf-menu,.wf-block-handle,#wf-selection')) closePopups();
  // 工具条/菜单/块把手自身不算选字起点，否则点击浮条按钮也会压住它。
  if (view && editable() && event.target.closest('.ProseMirror')) pointerSelecting = true;
  if (view && editable() && !event.target.closest('.ProseMirror,button,input,textarea,.wf-menu,#wf-selection')) {
    command('hostPointer', { x: event.clientX, y: event.clientY, phase: 'down', shift: event.shiftKey, clickCount: event.detail });
  }
}, true);
document.addEventListener('click', event => {
  const anchor = event.target.closest('a'); if (anchor) { event.preventDefault(); action('openLink', { url: anchor.getAttribute('href') }); }
});
document.addEventListener('pointerover', event => {
  const date = event.target.closest('.wf-inline-date');
  if (date && view && editable() && !popup?.query) {
    const from = view.posAtDOM(date, 0), to = view.posAtDOM(date, date.childNodes.length);
    const text = date.textContent || '', blockID = view.state.doc.resolve(from).parent.attrs.id;
    clearTimeout(hoverTimer); hoveredLink = undefined;
    hoverTimer = setTimeout(() => {
      if (!date.isConnected) return;
      const rect = date.getBoundingClientRect();
      openMenu([{ id: 'setReminder', title: `为「${text}」设置提醒` }], () => date.getBoundingClientRect(), () => {
        action('inlineDateReminder', { text, blockID, from, to,
          rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height } });
      });
      popup.date = true;
    }, 180);
    return;
  }
  const anchor = event.target.closest('a');
  if (!anchor || anchor === hoveredLink || !view || popup?.query) return;
  clearTimeout(hoverTimer); hoveredLink = anchor;
  hoverTimer = setTimeout(() => {
    if (!anchor.isConnected || hoveredLink !== anchor) return;
    const from = view.posAtDOM(anchor, 0), to = view.posAtDOM(anchor, anchor.childNodes.length), url = anchor.getAttribute('href');
    const items = [{ id: 'copy', title: '复制链接' }];
    if (editable()) items.push({ id: 'edit', title: '编辑链接' }, { id: 'remove', title: '移除链接' });
    openMenu(items, () => anchor.getBoundingClientRect(), item => {
      hoveredLink = undefined;
      if (item.id === 'copy') { action('copyLink', { url }); return; }
      view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, from, to)));
      if (item.id === 'remove') command('link', { value: null });
      else action('editLink', { selection: snapshot() });
    });
    popup.link = anchor;
  }, 180);
});
document.addEventListener('pointerout', event => {
  if (!hoveredLink || event.relatedTarget?.closest?.('.wf-menu,a')) return;
  clearTimeout(hoverTimer);
  hoverTimer = setTimeout(() => { if (popup?.link || popup?.date) closePopups(); hoveredLink = undefined; }, 200);
});
document.addEventListener('pointerup', () => {
  // 选区完成：松开时浮条才允许出现（拖动中 selectionChanged 已被压住，
  // 最后一帧定型后不再触发 selectionChanged，需要这里显式刷新）。
  if (pointerSelecting) { pointerSelecting = false; updateToolbar(); }
  if (painter && view && !view.state.selection.empty) command('applyStyle');
});
window.addEventListener('resize', () => { paintMenu(); updateToolbar(); reportHeight(); });
window.addEventListener('scroll', () => { if (popup && typeof popup.anchor === 'function') paintMenu(); else closePopups(); }, true);
async function boot() {
  try {
    editor = await Editor.make().config(ctx => {
      ctx.set(rootCtx, document.getElementById('root'));
      ctx.set(defaultValueCtx, { type: 'json', value: { type: 'doc', content: [{ type: 'wf_block', attrs: { id: uuid() } }] } });
      ctx.set(editorViewOptionsCtx, { attributes: { role: 'textbox', 'aria-label': '正文编辑器', 'aria-multiline': 'true', spellcheck: 'false' } });
      ctx.set(nodeViewCtx, [['wf_block', (node, owner, getPos) => new BlockView(node, owner, getPos)], ['wf_embed', (node, owner, getPos) => new EmbedView(node, owner, getPos)]]);
    }).use(schemaPlugins()).use(history).use($prose(markdownRules)).use(integration).create();
    view = editor.ctx.get(editorViewCtx); new ResizeObserver(reportHeight).observe(document.getElementById('root'));
    post({ event: 'ready' }); reportHeight();
  } catch (error) { console.error(error); post({ event: 'error', message: String(error) }); }
}
boot();
