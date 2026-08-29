import type { Editor as CoreEditor } from '@tiptap/core'
import { nextTick, ref } from 'vue'

import type { WorkFollowSlashCommand, WorkFollowSlashCommandItem } from './slashCommands'

/**
 * 斜杠命令菜单的共享状态机：检测"/"、定位弹层、键盘导航。
 * 各宿主（笔记/任务/模板）的插入逻辑保留在宿主内——它们的特殊命令与
 * 权限门槛不同；这里只负责"菜单出现在哪、高亮哪一项、何时开关"。
 */
export function useSlashMenu(options: {
  commands: () => WorkFollowSlashCommandItem[]
  /** 菜单 DOM id 前缀，用于滚动到当前高亮项。 */
  idPrefix: string
  /** 是否允许菜单出现（如 editable && 协同就绪）。 */
  enabled?: () => boolean
}) {
  const open = ref(false)
  const activeIndex = ref(0)
  const position = ref({ left: 8, top: 8 })
  const range = ref<{ from: number; to: number } | null>(null)

  function close() {
    open.value = false
    range.value = null
  }

  function placeAtCaret(currentEditor: CoreEditor) {
    try {
      const coords = currentEditor.view.coordsAtPos(currentEditor.state.selection.from)
      const menuWidth = 260
      const menuHeight = 430
      position.value = {
        left: Math.max(8, Math.min(coords.left, window.innerWidth - menuWidth - 8)),
        top: Math.max(8, Math.min(coords.bottom + 8, window.innerHeight - menuHeight - 8)),
      }
    } catch {
      close()
    }
  }

  function detect(currentEditor: CoreEditor) {
    if (options.enabled && !options.enabled()) {
      close()
      return
    }
    const { selection } = currentEditor.state
    if (!selection.empty) {
      close()
      return
    }
    const parent = selection.$from.parent
    const textBeforeCursor = parent.textBetween(0, selection.$from.parentOffset, '\n', '\n')
    if (!textBeforeCursor.endsWith('/')) {
      close()
      return
    }
    range.value = { from: Math.max(0, selection.from - 1), to: selection.from }
    placeAtCaret(currentEditor)
    activeIndex.value = 0
    open.value = true
  }

  function moveSelection(delta: number) {
    const commands = options.commands()
    if (!commands.length) return
    activeIndex.value = (activeIndex.value + delta + commands.length) % commands.length
    void nextTick(() => {
      document.getElementById(`${options.idPrefix}-${commands[activeIndex.value]?.type}`)?.scrollIntoView({ block: 'nearest' })
    })
  }

  /** 插入前删掉已输入的 "/"；宿主在自己的 chain 上调用。 */
  function deleteRange(chain: { deleteRange: (r: { from: number; to: number }) => unknown }, selectionFrom: number) {
    if (range.value) chain.deleteRange({ from: range.value.from, to: selectionFrom })
  }

  return { open, activeIndex, position, range, detect, close, moveSelection, deleteRange }
}
