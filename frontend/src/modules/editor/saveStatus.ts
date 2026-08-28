import dayjs from 'dayjs'

/** Format a compact, local-time label for the latest successful server save. */
export function formatLastSavedAt(value: string | null | undefined): string {
  if (!value) return '尚未保存'
  const savedAt = dayjs(value)
  if (!savedAt.isValid()) return '尚未保存'
  return `最近保存于 ${savedAt.format('YYYY-MM-DD HH:mm')}`
}
