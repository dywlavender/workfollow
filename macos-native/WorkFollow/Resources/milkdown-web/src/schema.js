import { Schema } from '@milkdown/prose/model';
import { $node, $mark } from '@milkdown/utils';

export const uuid = () => crypto.randomUUID().toUpperCase();
export const markNames = ['bold', 'italic', 'underline', 'highlight', 'strikethrough', 'code', 'link',
  'muted', 'caption', 'symbol', 'ink', 'textColor', 'highlightColor'];
const defaults = { id: null, kind: 'paragraph', level: null, checked: null, indentLevel: 0,
  listStart: null, align: null, bodySize: null, checklist: null, emptyRuns: false };
const attrs = Object.fromEntries(Object.entries(defaults).map(([key, value]) => [key, { default: value }]));
const leafMarkdown = {
  parseMarkdown: { match: () => false, runner: () => {} },
  toMarkdown: { match: node => node.isLeaf, runner: (state, node) => state.addNode('text', undefined, node.attrs.text || '') },
};

export const nodeSpecs = {
  doc: {
    content: 'wf_block+',
    parseMarkdown: { match: node => node.type === 'root', runner: (state, node, type) => state.injectRoot(node, type) },
    toMarkdown: { match: node => node.type.name === 'doc', runner: (state, node) => { state.openNode('root'); state.next(node.content); } },
  },
  text: {
    group: 'inline',
    parseMarkdown: { match: node => node.type === 'text', runner: (state, node) => state.addText(node.value || '') },
    toMarkdown: { match: node => node.isText, runner: (state, node) => state.addNode('text', undefined, node.text) },
  },
  wf_block: {
    content: 'inline*', group: 'block', attrs, defining: true,
    parseDOM: [{ tag: '[data-wf-block]', getAttrs: dom => ({ kind: dom.dataset.kind || 'paragraph' }) }, { tag: 'p' }],
    toDOM: node => ['div', { 'data-wf-block': '', 'data-kind': node.attrs.kind, 'data-block-id': node.attrs.id || '' }, 0],
    parseMarkdown: {
      match: node => ['paragraph', 'heading', 'blockquote', 'code', 'thematicBreak'].includes(node.type),
      runner: (state, node, type) => {
        state.openNode(type, { id: uuid(), kind: ({ heading: 'heading', blockquote: 'quote', code: 'code', thematicBreak: 'divider' })[node.type] || 'paragraph', level: node.depth || null });
        if (node.children) state.next(node.children); else if (node.value) state.addText(node.value);
        state.closeNode();
      },
    },
    toMarkdown: { match: node => node.type.name === 'wf_block', runner: (state, node) => { state.openNode('paragraph'); state.next(node.content); state.closeNode(); } },
  },
  wf_embed: {
    inline: true, group: 'inline', atom: true, draggable: true,
    attrs: { embed: {}, text: { default: '\uFFFC' } },
    leafText: node => node.attrs.text,
    toDOM: node => ['span', { 'data-wf-embed': node.attrs.embed.type }, node.attrs.embed.name || node.attrs.embed.latex || '附件'],
    ...leafMarkdown,
  },
  wf_empty: {
    inline: true, group: 'inline', atom: true, selectable: false,
    attrs: { run: {} }, leafText: () => '',
    toDOM: () => ['span', { class: 'wf-empty-run', 'aria-hidden': 'true' }, '\u200b'],
    ...leafMarkdown,
  },
};

function markDOM(type, value) {
  const tags = { bold: 'strong', italic: 'em', underline: 'u', highlight: 'mark', strikethrough: 's', code: 'code', link: 'a' };
  const properties = { 'data-wf-mark': type };
  if (type === 'link') properties.href = value || '';
  if (type === 'textColor') properties.style = `color:${value}`;
  if (type === 'highlightColor') properties.style = `background-color:${value}`;
  if (type === 'muted' || type === 'caption') properties.class = `wf-${type}`;
  if (type === 'ink') {
    properties.class = `wf-ink-${value?.split(':')[0]}`;
    if (value?.startsWith('argb:')) {
      const number = Number(value.slice(5)) >>> 0;
      properties.style = `color:rgba(${(number >>> 16) & 255},${(number >>> 8) & 255},${number & 255},${(number >>> 24) / 255})`;
    }
  }
  return [tags[type] || 'span', properties, 0];
}

export const markSpecs = Object.fromEntries(markNames.map(type => [type, {
  attrs: { value: { default: null } }, inclusive: type !== 'link',
  toDOM: mark => markDOM(type, mark.attrs.value),
  parseDOM: [{ tag: `[data-wf-mark="${type}"]` }],
  parseMarkdown: { match: () => false, runner: () => {} },
  toMarkdown: { match: mark => mark.type.name === type, runner: (state, mark, node) => state.next(node) },
}]));
// Native run boundaries survive a no-op round trip even when adjacent runs have identical styles.
markSpecs.wf_run = { attrs: { key: {} }, inclusive: true, toDOM: () => ['span', 0],
  parseMarkdown: { match: () => false, runner: () => {} },
  toMarkdown: { match: mark => mark.type.name === 'wf_run', runner: (state, mark, node) => state.next(node) } };

export const schemaPlugins = () => [
  ...Object.entries(nodeSpecs).map(([name, spec]) => $node(name, () => spec)),
  ...Object.entries(markSpecs).map(([name, spec]) => $mark(name, () => spec)),
];
export const createSchema = () => new Schema({ nodes: nodeSpecs, marks: markSpecs });

export const isList = attrs => ['bullet', 'ordered', 'checklist'].includes(attrs.kind);
export function shiftedBlocks(blocks, selected, delta) {
  const affected = new Set(selected);
  for (const index of selected) {
    if (!isList(blocks[index])) continue;
    for (let child = index + 1; child < blocks.length && isList(blocks[child]) && blocks[child].indentLevel > blocks[index].indentLevel; child++) affected.add(child);
  }
  if (!affected.size) return blocks;
  const levels = [...affected].map(index => blocks[index].indentLevel || 0);
  const change = delta > 0 ? Math.min(delta, 8 - Math.max(...levels)) : Math.max(delta, -Math.min(...levels));
  return blocks.map((block, index) => affected.has(index) ? { ...block, indentLevel: (block.indentLevel || 0) + change } : block);
}

export function listNumbers(blocks) {
  const levels = [];
  return blocks.map(attrs => {
    if (!isList(attrs)) { levels.length = 0; return null; }
    const depth = attrs.indentLevel || 0, previous = levels[depth];
    levels.length = depth + 1;
    const number = attrs.kind === 'ordered' ? attrs.listStart ?? (previous?.kind === 'ordered' ? previous.number + 1 : 1) : null;
    levels[depth] = { kind: attrs.kind, number }; return number;
  });
}

export function fromNative(schema, wire, { newIDs = false } = {}) {
  const blocks = wire.blocks?.length ? wire.blocks : [{ id: uuid(), kind: 'paragraph', runs: [] }];
  return schema.nodes.doc.create(null, blocks.map(block => {
    const id = newIDs ? uuid() : block.id || uuid();
    const content = [];
    for (const [index, run] of (block.runs || []).entries()) {
      const marks = (run.marks || []).filter(mark => schema.marks[mark.type]).map(mark => schema.marks[mark.type].create({ value: mark.value ?? null }));
      marks.push(schema.marks.wf_run.create({ key: `${id}:${index}` }));
      if (run.embed) content.push(schema.nodes.wf_embed.create({ embed: run.embed, text: run.text }, null, marks));
      else if (run.text) content.push(schema.text(run.text, marks));
      else content.push(schema.nodes.wf_empty.create({ run }, null, marks));
    }
    const blockAttrs = Object.fromEntries(Object.keys(defaults).map(key => [key, block[key] ?? defaults[key]]));
    blockAttrs.id = id; blockAttrs.emptyRuns = (block.runs || []).length === 0;
    return schema.nodes.wf_block.create(blockAttrs, content);
  }));
}

/// 按块序列化：`id` 是块的稳定身份（appendTransaction 过滤器保证提交时唯一），
/// 增量提交靠它对比变化块、原生靠它按 order 重组。
/// ProseMirror 节点不可变、事务后结构共享，未改动的块仍是同一个节点对象；
/// 按节点缓存序列化结果，typing 时只有受影响块重新序列化与 stringify。
const blockCache = new WeakMap();
const plainCache = new WeakMap();
const wireCache = new WeakMap();
// 测试探针：统计实际发生的块序列化次数，断言增量路径只触碰变化块。
let serializeCount = 0;
export function getSerializeCount() { return serializeCount; }

function serializeBlock(block) {
  serializeCount += 1;
  const runs = []; let previousKey;
  block.forEach(node => {
    if (node.type.name === 'wf_empty') { runs.push(structuredClone(node.attrs.run)); previousKey = undefined; return; }
    const marks = node.marks.filter(mark => mark.type.name !== 'wf_run').map(mark => ({ type: mark.type.name, ...(mark.attrs.value == null ? {} : { value: mark.attrs.value }) }))
      .sort((a, b) => (a.type + (a.value || '')).localeCompare(b.type + (b.value || ''), 'en'));
    const key = node.marks.find(mark => mark.type.name === 'wf_run')?.attrs.key;
    const run = { text: node.isText ? node.text : node.attrs.text, marks };
    if (node.type.name === 'wf_embed') run.embed = structuredClone(node.attrs.embed);
    const last = runs.at(-1);
    if (last && !last.embed && !run.embed && previousKey === key && JSON.stringify(last.marks) === JSON.stringify(marks)) last.text += run.text;
    else runs.push(run);
    previousKey = key;
  });
  const attrs = Object.fromEntries(Object.entries(block.attrs).filter(([key, value]) => key !== 'emptyRuns' && value != null));
  return { id: block.attrs.id, wire: { ...attrs, runs } };
}

function cachedBlock(block) {
  let part = blockCache.get(block);
  if (!part) { part = serializeBlock(block); blockCache.set(block, part); }
  return part;
}

export function toNativeBlocks(doc) {
  const blocks = [];
  doc.forEach(block => blocks.push(cachedBlock(block)));
  return blocks;
}

export function wireKey(wire) {
  let key = wireCache.get(wire);
  if (key === undefined) { key = JSON.stringify(wire); wireCache.set(wire, key); }
  return key;
}

export function blockPlainText(block) {
  let text = plainCache.get(block);
  if (text === undefined) {
    text = cachedBlock(block).wire.runs.map(run => run.text ?? '').join('');
    plainCache.set(block, text);
  }
  return text;
}

export function toNative(doc) {
  return { blocks: toNativeBlocks(doc).map(part => part.wire) };
}

export function plainText(doc) {
  const parts = [];
  doc.forEach(block => parts.push(blockPlainText(block)));
  return parts.join('\n');
}

export function selectionDocument(state) {
  const { from, to } = state.selection;
  const content = state.doc.cut(from, to);
  return toNative(content);
}

export function plainOffset(doc, position) {
  let offset = 0;
  for (let index = 0, start = 0; index < doc.childCount; index++) {
    const block = doc.child(index), end = start + block.nodeSize;
    if (position <= end - 1) return offset + block.textBetween(0, Math.max(0, Math.min(block.content.size, position - start - 1)), '', leaf => leaf.type.name === 'wf_embed' ? leaf.attrs.text : '').length;
    offset += blockPlainText(block).length + 1; start = end;
  }
  return Math.max(0, offset - 1);
}

export function positionForPlainOffset(doc, offset) {
  let remaining = Math.max(0, offset), start = 0;
  for (let index = 0; index < doc.childCount; index++) {
    const block = doc.child(index); let position = start + 1;
    for (const child of block.content.content) {
      const length = child.isText ? child.text.length : child.type.name === 'wf_embed' ? child.attrs.text.length : 0;
      if (length && remaining <= length) return position + (child.isText ? remaining : remaining > 0 ? 1 : 0);
      remaining -= length; position += child.nodeSize;
    }
    if (remaining === 0 || index === doc.childCount - 1) return start + 1 + block.content.size;
    remaining -= 1; start += block.nodeSize;
  }
  return 1;
}
