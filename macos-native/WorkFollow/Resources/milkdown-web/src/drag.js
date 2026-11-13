import { TextSelection } from '@milkdown/prose/state';
import { closeHistory } from '@milkdown/prose/history';

// 指针落在哪两块之间。index 是「插到第 index 个块之前」，0 表示最前，
// rects.length 表示末尾；lineY 画在相邻两块共用的间隙里，不贴在任一块的边线上。
export function dropTarget(rects, y) {
  if (!rects.length) return null;
  let index = rects.length;
  for (let i = 0; i < rects.length; i++) {
    if (y < (rects[i].top + rects[i].bottom) / 2) { index = i; break; }
  }
  const before = rects[index] || null;
  const after = index > 0 ? rects[index - 1] : null;
  const bounds = before || after;
  return {
    index,
    lineY: before && after ? (after.bottom + before.top) / 2 : before ? before.top - 2 : after.bottom + 2,
    left: bounds.left,
    right: bounds.right,
  };
}

// 把第 fromIndex 个块整体搬到「第 toIndex 个块之前」，索引均以移动前的文档为准。
// 复用同一个节点对象：块 id、业务 attrs、结构共享与原生差量提交的 wireKey 基线
// 全部保持不变，commitNow 只会检测到 order 变化而不会把搬动的块当成内容改动。
export function moveBlock(state, fromIndex, toIndex) {
  const doc = state.doc, count = doc.childCount;
  if (fromIndex < 0 || fromIndex >= count || toIndex < 0 || toIndex > count) return null;
  // 插到自己前面或紧跟自己后面都是原位；单块文档的这两种情况也一并挡住，
  // 避免 delete 之后短暂出现违反 doc: wf_block+ 的空文档。
  if (toIndex === fromIndex || toIndex === fromIndex + 1) return null;
  let from = 0;
  for (let i = 0; i < fromIndex; i++) from += doc.child(i).nodeSize;
  const node = doc.child(fromIndex);
  let target = 0;
  for (let i = 0; i < toIndex; i++) target += doc.child(i).nodeSize;
  // 光标在被搬走的块里时跟着一起走，否则由 ProseMirror 自己 map 选区。
  const { from: selFrom, to: selTo } = state.selection;
  const carried = selFrom >= from && selTo <= from + node.nodeSize
    ? { anchor: selFrom - from - 1, head: selTo - from - 1 } : null;
  const tr = closeHistory(state.tr);
  tr.delete(from, from + node.nodeSize);
  const insertAt = tr.mapping.map(target);
  tr.insert(insertAt, node);
  if (carried) {
    const clamp = offset => insertAt + 1 + Math.min(Math.max(0, offset), node.content.size);
    tr.setSelection(TextSelection.create(tr.doc, clamp(carried.anchor), clamp(carried.head)));
  }
  return tr;
}
