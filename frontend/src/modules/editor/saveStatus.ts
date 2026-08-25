import dayjs from 'dayjs'

/** Format a compact, local-time label for the latest successful server save. */
export function formatLastSavedAt(value: string | null | undefined): string {
  if (!value) return '尚未保存'
  const savedAt = dayjs(value)
  if (!savedAt.isValid()) return '尚未保存'
  const stamp = savedAt.isSame(dayjs(), 'day')
    ? savedAt.format('HH:mm')
    : savedAt.format('M月D日 HH:mm')
  return `最近保存于 ${stamp}`
}
