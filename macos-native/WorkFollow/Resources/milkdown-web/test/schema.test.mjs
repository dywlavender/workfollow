import test from 'node:test';
import assert from 'node:assert/strict';
import { EditorState, TextSelection } from '@milkdown/prose/state';
import { history, undo, redo } from '@milkdown/prose/history';
import { createSchema, fromNative, toNative, toNativeBlocks, wireKey, blockPlainText, plainText, plainOffset, positionForPlainOffset, selectionDocument, uuid, shiftedBlocks, listNumbers } from '../src/schema.js';

const run = (text, marks = [], embed) => ({ text, marks, ...(embed ? { embed } : {}) });
const block = (kind, runs = [run('中文🙂正文')], attrs = {}) => ({ id: uuid(), kind, indentLevel: 0, ...attrs, runs });
const schema = createSchema();
function roundtrip(blocks) {
  const value = { blocks }, doc = fromNative(schema, value); doc.check();
  assert.deepEqual(toNative(doc), value); return doc;
}

test('all native block kinds retain IDs, layout and checklist business metadata', () => {
  roundtrip([
    block('paragraph', undefined, { align: 'justify', bodySize: '18', indentLevel: 3 }),
    ...[1, 2, 3, 4, 5, 6].map(level => block('heading', undefined, { level })),
    block('bullet', undefined, { indentLevel: 2 }), block('ordered', undefined, { listStart: 7 }),
    block('checklist', undefined, { checked: true, checklist: { completedAt: 8000, reminderAt: 9000, allDay: true } }),
    block('quote'), block('code', [run('const x = 1;\n第二行')]), block('divider', []),
  ]);
});

test('all thirteen marks and adjacent native run boundaries survive', () => {
  const marks = ['bold','italic','underline','highlight','strikethrough','code','link','muted','caption','symbol','ink','textColor','highlightColor']
    .map(type => ({ type, ...({ link: 'https://example.com/中文', symbol: 'checkmark.circle', ink: 'argb:4289331200', textColor: '#aa3311', highlightColor: '#ffe98a' }[type] ? { value: { link: 'https://example.com/中文', symbol: 'checkmark.circle', ink: 'argb:4289331200', textColor: '#aa3311', highlightColor: '#ffe98a' }[type] } : {}) }));
  const styled = marks.map(mark => run(mark.type, [mark]));
  roundtrip([block('paragraph', [...styled, run('前', [{ type: 'bold' }]), run('后', [{ type: 'bold' }])])]);
});

test('four embed kinds keep their editable references without copying binary payloads', () => {
  const embeds = [
    { type: 'attachment', id: uuid(), name: '截图.png', src: 'workfollow-milkdown://editor/asset/image', image: true, width: 312.5, height: 140 },
    { type: 'diagram', id: uuid(), name: '流程图', src: 'workfollow-milkdown://editor/asset/drawing' },
    { type: 'table', id: uuid(), rows: [['中文', '第二列'], ['1', '2']] },
    { type: 'formula', id: uuid(), latex: '\\frac{1}{2}' },
  ];
  roundtrip([block('paragraph', embeds.map(embed => run('\uFFFC', [], embed)))]);
});

test('empty native run styles and truly empty run arrays are distinct', () => {
  roundtrip([block('paragraph', []), block('paragraph', [run('', [{ type: 'bold' }])])]);
});

test('UTF-16 selection offsets account for block boundaries, emoji and embeds', () => {
  const doc = roundtrip([block('paragraph', [run('中文🙂')]), block('paragraph', [run('下一段')])]);
  assert.equal(plainOffset(doc, 1), 0); assert.equal(plainOffset(doc, 5), 4); assert.equal(plainOffset(doc, 7), 5);
  assert.equal(plainOffset(doc, doc.content.size), '中文🙂\n下一段'.length);
  const state = EditorState.create({ doc, selection: TextSelection.create(doc, 2, 5) });
  assert.equal(selectionDocument(state).blocks[0].runs[0].text, '文🙂');
});

test('editor undo and redo preserve the native data rather than regenerating block IDs', () => {
  const doc = roundtrip([block('checklist', [run('原文')], { checked: false, checklist: { reminderAt: 9000, allDay: false } })]);
  let state = EditorState.create({ doc, plugins: [history()] });
  const original = toNative(state.doc);
  const dispatch = tr => { state = state.apply(tr); };
  dispatch(state.tr.insertText('补充', 3));
  const edited = toNative(state.doc);
  assert(undo(state, dispatch)); assert.deepEqual(toNative(state.doc), original);
  assert(redo(state, dispatch)); assert.deepEqual(toNative(state.doc), edited);
});

test('pasted blocks receive new IDs while the original document remains unchanged', () => {
  const wire = { blocks: [block('paragraph')] };
  const copy = toNative(fromNative(schema, wire, { newIDs: true }));
  assert.notEqual(copy.blocks[0].id, wire.blocks[0].id);
  assert.equal(copy.blocks[0].runs[0].text, wire.blocks[0].runs[0].text);
});

test('plain offsets map back to ProseMirror positions across empty runs and emoji', () => {
  const doc = fromNative(schema, { blocks: [block('paragraph', [run('甲🙂')]), block('paragraph', [run('')]), block('paragraph', [run('乙')])] });
  for (let offset = 0; offset <= 6; offset++) assert.equal(plainOffset(doc, positionForPlainOffset(doc, offset)), offset);
});

test('list indentation moves descendants as a group and clamps their relative depths', () => {
  const blocks = [block('bullet'), block('bullet', undefined, { indentLevel: 1 }), block('bullet')];
  const moved = shiftedBlocks(blocks, [0], 1);
  assert.deepEqual(moved.map(block => block.indentLevel), [1, 2, 0]);
  assert.deepEqual(shiftedBlocks(moved, [0], -1), blocks);
  assert.deepEqual(shiftedBlocks(blocks, [0], -1), blocks);
});

test('ordered numbering continues past nested bullet and checklist children', () => {
  const blocks = [block('ordered', undefined, { listStart: 7 }), block('bullet', undefined, { indentLevel: 1 }),
    block('ordered', undefined, { indentLevel: 2, listStart: 3 }), block('checklist', undefined, { indentLevel: 1 }),
    block('ordered'), block('paragraph'), block('ordered')];
  assert.deepEqual(listNumbers(blocks), [7, null, 3, null, 8, null, 1]);
});

test('block cache reuses untouched blocks and invalidates changed ones', () => {
  const doc = roundtrip([block('paragraph', [run('甲')]), block('paragraph', [run('乙')]), block('paragraph', [run('丙')])]);
  const before = toNativeBlocks(doc);
  assert.equal(plainText(doc), '甲\n乙\n丙');
  const state = EditorState.create({ doc });
  const edited = state.apply(state.tr.insertText('X', 2)).doc;
  const after = toNativeBlocks(edited);
  assert.notEqual(after[0].wire, before[0].wire);
  assert.equal(after[1].wire, before[1].wire);
  assert.equal(after[2].wire, before[2].wire);
  assert.equal(wireKey(after[1].wire), wireKey(before[1].wire));
  assert.equal(blockPlainText(edited.child(1)), '乙');
  assert.equal(plainText(edited), '甲X\n乙\n丙');
  const text = '甲X\n乙\n丙';
  for (let offset = 0; offset <= text.length; offset++) {
    assert.equal(plainOffset(edited, positionForPlainOffset(edited, offset)), offset);
  }
});
