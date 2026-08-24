import { onBeforeUnmount, onMounted, type Ref } from 'vue'

/** Closes a popover when the pointer starts outside its trigger/content host. */
export function useClickOutside(
  target: Ref<HTMLElement | null>,
  open: Readonly<Ref<boolean>>,
  close: () => void,
) {
  function handlePointerDown(event: PointerEvent) {
    if (!open.value) return
    const eventTarget = event.target
    if (eventTarget instanceof Node && target.value?.contains(eventTarget)) return
    close()
  }

  onMounted(() => document.addEventListener('pointerdown', handlePointerDown))
  onBeforeUnmount(() => document.removeEventListener('pointerdown', handlePointerDown))
}
