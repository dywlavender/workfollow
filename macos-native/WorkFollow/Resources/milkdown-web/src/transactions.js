import { Step, StepResult } from '@milkdown/prose/transform';
import { closeHistory } from '@milkdown/prose/history';

// A zero-width history step carries the business transaction through undo/redo,
// independently of subsequent edits or external paragraph metadata updates.
export class HostHistoryStep extends Step {
  constructor(token, operation = 'commit') { super(); this.token = token; this.operation = operation; }
  apply(doc) { return StepResult.ok(doc); }
  invert() { return new HostHistoryStep(this.token, this.operation === 'undo' ? 'redo' : 'undo'); }
  map() { return this; }
  toJSON() { return { stepType: 'workfollowHost', token: this.token, operation: this.operation }; }
  static fromJSON(_, value) { return new HostHistoryStep(value.token, value.operation); }
}
Step.jsonID('workfollowHost', HostHistoryStep);

export function hostHistory(tr, token) {
  return token ? tr.step(new HostHistoryStep(token)) : tr;
}
export function historyBoundary(transactions, state) {
  return transactions.some(tr => tr.steps.some(step => step instanceof HostHistoryStep)) ? closeHistory(state.tr) : null;
}

export function clipboardBoundaries(selection) {
  return { startsAtParagraphBoundary: selection.$from.parentOffset === 0,
    endsAtParagraphBoundary: selection.$to.parentOffset === selection.$to.parent.content.size };
}

function updateBlock(tr, pos, target) {
  const current = tr.doc.nodeAt(pos);
  for (const [key, value] of Object.entries(target.attrs)) {
    if (JSON.stringify(current.attrs[key]) !== JSON.stringify(value)) tr.setNodeAttribute(pos, key, value);
  }
  const start = current.content.findDiffStart(target.content);
  if (start == null) return;
  let { a, b } = current.content.findDiffEnd(target.content);
  const overlap = start - Math.min(a, b);
  if (overlap > 0) { a += overlap; b += overlap; }
  tr.replace(pos + 1 + start, pos + 1 + a, target.slice(start, b));
}

// Preserve common paragraphs and their history maps; attribute-only updates
// must not look like deletion/reinsertion of the entire document.
export function synchronizeDocument(state, target) {
  const tr = state.tr.setMeta('addToHistory', false);
  const old = state.doc.content.content, next = target.content.content;
  let prefix = 0, suffix = 0;
  while (prefix < Math.min(old.length, next.length) && old[prefix].attrs.id === next[prefix].attrs.id) prefix++;
  while (suffix < Math.min(old.length, next.length) - prefix && old[old.length - 1 - suffix].attrs.id === next[next.length - 1 - suffix].attrs.id) suffix++;
  let pos = 0;
  for (let index = 0; index < prefix; index++) { updateBlock(tr, pos, next[index]); pos += tr.doc.child(index).nodeSize; }
  const from = pos;
  for (let index = prefix; index < tr.doc.childCount - suffix; index++) pos += tr.doc.child(index).nodeSize;
  if (old.length - prefix - suffix || next.length - prefix - suffix) tr.replaceWith(from, pos, next.slice(prefix, next.length - suffix));
  pos = 0;
  for (let index = 0; index < tr.doc.childCount - suffix; index++) pos += tr.doc.child(index).nodeSize;
  for (let index = next.length - suffix; index < next.length; index++) {
    updateBlock(tr, pos, next[index]); pos += tr.doc.nodeAt(pos).nodeSize;
  }
  return tr;
}
