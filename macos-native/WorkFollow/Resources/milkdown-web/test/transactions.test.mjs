import test from 'node:test';
import assert from 'node:assert/strict';
import { EditorState, TextSelection, Plugin } from '@milkdown/prose/state';
import { Slice } from '@milkdown/prose/model';
import { history, undo, redo, closeHistory, undoDepth } from '@milkdown/prose/history';
import { createSchema, fromNative, toNative, uuid } from '../src/schema.js';
import { HostHistoryStep, hostHistory, historyBoundary, clipboardBoundaries, synchronizeDocument } from '../src/transactions.js';

const schema = createSchema();
const block = (text, attrs = {}) => ({ id: uuid(), kind: 'paragraph', indentLevel: 0, runs: [{ text, marks: [] }], ...attrs });
const doc = blocks => fromNative(schema, { blocks });
const text = state => state.doc.textContent;
const boundaries = new Plugin({ appendTransaction: (transactions, _, state) => historyBoundary(transactions, state) });
function fixture(blocks) {
  const value = doc(blocks);
  let state = EditorState.create({ doc: value, selection: TextSelection.atEnd(value), plugins: [history(), boundaries] });
  const events = [];
  return { get state() { return state; }, events, dispatch(tr) {
    const result = state.applyTransaction(tr); state = result.state;
    for (const value of result.transactions) for (const step of value.steps) if (step instanceof HostHistoryStep) events.push([step.token, step.operation]);
  } };
}

test('external checklist metadata preserves typing undo, redo and selection', () => {
  const original = block('原文', { kind: 'checklist', checked: false });
  const f = fixture([original]);
  f.dispatch(f.state.tr.insertText('补充').setTime(1000));
  const selected = f.state.selection.from;
  const next = toNative(f.state.doc); next.blocks[0].checklist = { reminderAt: 9000 };
  f.dispatch(synchronizeDocument(f.state, fromNative(schema, next)));
  assert.equal(f.state.selection.from, selected);
  assert(undo(f.state, f.dispatch)); assert.equal(text(f.state), '原文');
  assert.equal(f.state.doc.firstChild.attrs.checklist.reminderAt, 9000);
  assert(redo(f.state, f.dispatch)); assert.equal(text(f.state), '原文补充');
  assert.equal(f.state.doc.firstChild.attrs.checklist.reminderAt, 9000);
});

test('host transaction is isolated from rapid typing and redo followed by typing', () => {
  const f = fixture([block('原文')]);
  const reference = doc([block('关联笔记')]);
  f.dispatch(hostHistory(closeHistory(f.state.tr).replaceSelection(new Slice(reference.firstChild.content, 0, 0)), 'HOST').setTime(1000));
  f.dispatch(f.state.tr.insertText('续写').setTime(1100));
  assert.equal(undoDepth(f.state), 2);
  assert(undo(f.state, f.dispatch)); assert.equal(text(f.state), '原文关联笔记');
  assert(undo(f.state, f.dispatch)); assert.equal(text(f.state), '原文');
  assert.deepEqual(f.events, [['HOST', 'commit'], ['HOST', 'undo']]);
  assert(redo(f.state, f.dispatch)); assert.equal(text(f.state), '原文关联笔记');
  f.dispatch(f.state.tr.insertText('新续写').setTime(1200));
  assert(undo(f.state, f.dispatch)); assert.equal(text(f.state), '原文关联笔记');
  assert(undo(f.state, f.dispatch)); assert.equal(text(f.state), '原文');
  assert.deepEqual(f.events.slice(-2), [['HOST', 'redo'], ['HOST', 'undo']]);
});

test('host inverse survives external metadata update without full snapshot equality', () => {
  const f = fixture([block('原文')]);
  f.dispatch(hostHistory(closeHistory(f.state.tr).insertText('引用'), 'HOST'));
  const next = toNative(f.state.doc); next.blocks[0].align = 'right';
  f.dispatch(synchronizeDocument(f.state, fromNative(schema, next)));
  assert(undo(f.state, f.dispatch)); assert.equal(text(f.state), '原文');
  assert.equal(f.state.doc.firstChild.attrs.align, 'right');
  assert.deepEqual(f.events.at(-1), ['HOST', 'undo']);
});

test('external content patch keeps untouched paragraph history and inserted neighbours', () => {
  const first = block('首段'), second = block('尾段');
  const f = fixture([first, second]);
  f.dispatch(f.state.tr.insertText('本地').setTime(1000));
  const next = toNative(f.state.doc); next.blocks.unshift(block('外部新增'));
  next.blocks[1].runs[0].text = '首段远程';
  f.dispatch(synchronizeDocument(f.state, fromNative(schema, next)));
  assert.deepEqual(toNative(f.state.doc), next);
  assert(undo(f.state, f.dispatch));
  assert.deepEqual(toNative(f.state.doc).blocks.map(b => b.runs.map(r => r.text).join('')), ['外部新增', '首段远程', '尾段']);
});

test('clipboard distinguishes partial paragraph start from complete block selection', () => {
  const value = doc([block('ABCDE', { kind: 'heading', level: 2 }), block('下一段')]);
  assert.deepEqual(clipboardBoundaries(TextSelection.create(value, 1, 3)), { startsAtParagraphBoundary: true, endsAtParagraphBoundary: false });
  assert.deepEqual(clipboardBoundaries(TextSelection.create(value, 1, 6)), { startsAtParagraphBoundary: true, endsAtParagraphBoundary: true });
  assert.deepEqual(clipboardBoundaries(TextSelection.create(value, 3, 6)), { startsAtParagraphBoundary: false, endsAtParagraphBoundary: true });
});
