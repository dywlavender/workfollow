import test from 'node:test';
import assert from 'node:assert/strict';
import { EditorState, TextSelection } from '@milkdown/prose/state';
import { history, undo } from '@milkdown/prose/history';
import { createSchema, fromNative, toNative, toNativeBlocks, wireKey, uuid } from '../src/schema.js';
import { dropTarget, moveBlock } from '../src/drag.js';

const schema = createSchema();
const block = (text, attrs = {}) => ({ id: uuid(), kind: 'paragraph', indentLevel: 0, runs: [{ text, marks: [] }], ...attrs });
const doc = blocks => fromNative(schema, { blocks });
const ids = state => toNative(state.doc).blocks.map(part => part.id);
function fixture(blocks) {
  let state = EditorState.create({ doc: doc(blocks), plugins: [history()] });
  return { get state() { return state; }, dispatch(tr) { state = state.apply(tr); } };
}

test('drop target picks the gap nearest to the pointer', () => {
  const rects = [
    { top: 10, bottom: 30, left: 20, right: 200 },
    { top: 40, bottom: 60, left: 20, right: 200 },
    { top: 70, bottom: 90, left: 20, right: 200 },
  ];
  assert.equal(dropTarget([], 40), null);
  assert.equal(dropTarget(rects, 0).index, 0);
  assert.equal(dropTarget(rects, 25).index, 1);
  assert.equal(dropTarget(rects, 35).index, 1);
  assert.equal(dropTarget(rects, 55).index, 2);
  assert.equal(dropTarget(rects, 200).index, 3);
  assert.equal(dropTarget(rects, 35).lineY, 35);
  assert.equal(dropTarget(rects, 0).lineY, 8);
  assert.equal(dropTarget(rects, 200).lineY, 92);
  assert.equal(dropTarget(rects, 35).left, 20);
});

test('move block preserves ids, business attrs and wire keys', () => {
  const first = block('首段', { kind: 'checklist', checked: true, indentLevel: 2, align: 'right',
    checklist: { reminderAt: 123, reminderTaskID: 'TASK' } });
  const second = block('中段'), third = block('尾段');
  const f = fixture([first, second, third]);
  const before = new Map(toNativeBlocks(f.state.doc).map(part => [part.id, wireKey(part.wire)]));
  f.dispatch(moveBlock(f.state, 0, 3));
  assert.deepEqual(ids(f.state), [second.id, third.id, first.id]);
  assert.deepEqual(toNative(f.state.doc).blocks.at(-1), toNative(doc([first])).blocks[0]);
  for (const part of toNativeBlocks(f.state.doc)) assert.equal(wireKey(part.wire), before.get(part.id));
});

test('move block supports forward, backward and no-op positions', () => {
  const [a, b, c] = [block('A'), block('B'), block('C')];
  assert.deepEqual(ids(fixture([a, b, c]).state), [a.id, b.id, c.id]);
  const forward = fixture([a, b, c]);
  forward.dispatch(moveBlock(forward.state, 0, 2));
  assert.deepEqual(ids(forward.state), [b.id, a.id, c.id]);
  const backward = fixture([a, b, c]);
  backward.dispatch(moveBlock(backward.state, 2, 0));
  assert.deepEqual(ids(backward.state), [c.id, a.id, b.id]);
  const state = fixture([a, b]).state;
  assert.equal(moveBlock(state, 0, 0), null);
  assert.equal(moveBlock(state, 0, 1), null);
  assert(moveBlock(state, 1, 0));
  assert.equal(moveBlock(state, -1, 1), null);
  assert.equal(moveBlock(state, 0, 9), null);
  const single = fixture([a]).state;
  assert.equal(moveBlock(single, 0, 0), null);
  assert.equal(moveBlock(single, 0, 1), null);
});

test('move block is a single undo step', () => {
  const [a, b, c] = [block('A'), block('B'), block('C')];
  const f = fixture([a, b, c]);
  f.dispatch(moveBlock(f.state, 2, 0));
  assert.deepEqual(ids(f.state), [c.id, a.id, b.id]);
  assert(undo(f.state, f.dispatch));
  assert.deepEqual(ids(f.state), [a.id, b.id, c.id]);
});

test('caret inside the moved block travels with it', () => {
  const [a, b] = [block('ABCDE'), block('尾段')];
  const value = doc([a, b]);
  let state = EditorState.create({ doc: value, selection: TextSelection.create(value, 3, 3), plugins: [history()] });
  const tr = moveBlock(state, 0, 2);
  state = state.apply(tr);
  assert.deepEqual(ids(state), [b.id, a.id]);
  assert.equal(state.selection.from, state.doc.child(0).nodeSize + 3);
  assert.equal(state.doc.textBetween(state.selection.from, state.selection.from + 2), 'CD');
});
