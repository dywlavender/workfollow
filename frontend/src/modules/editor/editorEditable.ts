import { onBeforeUnmount, ref } from 'vue'
import type { Editor } from '@tiptap/core'

/**
 * editor.isEditable 不是 Vue 响应式属性（vue-3 包装只代理了 state/storage），
 * NodeView 挂载早于协同就绪时直接读它会永远拿到 false。
 * setEditable 会发 'update' 事件，这里借事件驱动一个响应式副本。
 */
export function useEditorEditable(editor: Editor) {
  const editable = ref(editor.isEditable)
  const sync = () => { editable.value = editor.isEditable }
  editor.on('update', sync)
  editor.on('selectionUpdate', sync)
  onBeforeUnmount(() => {
    editor.off('update', sync)
    editor.off('selectionUpdate', sync)
  })
  return editable
}
