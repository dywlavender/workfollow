import { onBeforeUnmount, watch, type WatchSource } from 'vue'

const openDialogs: symbol[] = []

function removeDialog(token: symbol) {
  const index = openDialogs.lastIndexOf(token)
  if (index >= 0) openDialogs.splice(index, 1)
}

export function useDialogEscape(open: WatchSource<boolean>, close: () => void) {
  if (typeof document === 'undefined') return
  const token = Symbol('dialog')

  function onKeydown(event: KeyboardEvent) {
    if (event.key !== 'Escape' || openDialogs.at(-1) !== token) return
    event.preventDefault()
    event.stopImmediatePropagation()
    close()
  }

  watch(open, (isOpen) => {
    removeDialog(token)
    if (isOpen) openDialogs.push(token)
  }, { immediate: true })

  document.addEventListener('keydown', onKeydown)
  onBeforeUnmount(() => {
    removeDialog(token)
    document.removeEventListener('keydown', onKeydown)
  })
}
