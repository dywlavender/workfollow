// 中文输入法确认候选词的那次回车，不能当成编辑器的「回车」命令。
// WebKit 上它可能以两种形态抵达 keydown：
//   1) keyCode 229（IME 处理中），但 isComposing 已经是 false；
//   2) compositionend 先于 keydown 派发，回车看起来就是普通的 keyCode 13，
//      此时 isComposing=false 且 ProseMirror 的 view.composing 也已清除。
// 若放行进 enter()，文字尚未上屏的列表块会被判为空块，触发「空列表回车
// 退出列表」降级成普通段落，随后文字才上屏——表现为列表标记凭空消失。
export const IME_COMMIT_WINDOW = 60;

export function isImeCommitEnter(event, committedAt, now = Date.now()) {
  if (event.shiftKey || event.key !== 'Enter') return false;
  if (event.keyCode === 229) return true;
  // committedAt 为 0 表示从未提交；时钟回拨造成的未来值也不能算命中。
  return committedAt > 0 && now >= committedAt && now - committedAt < IME_COMMIT_WINDOW;
}
