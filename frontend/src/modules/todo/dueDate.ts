import dayjs, { type Dayjs } from 'dayjs'

/** Midnight is the UI sentinel for a date-only task in the current API. */
export function dateOnlyDueAt(value: Dayjs = dayjs()): string {
  return value.startOf('day').format('YYYY-MM-DDTHH:mm:ss')
}

export function isDateOnlyDue(value: string | null | undefined): boolean {
  if (!value) return false
  const due = dayjs(value)
  return due.hour() === 0 && due.minute() === 0 && due.second() === 0
}

export function isDueOverdue(value: string | null | undefined): boolean {
  if (!value) return false
  const due = dayjs(value)
  return isDateOnlyDue(value) ? due.isBefore(dayjs(), 'day') : due.isBefore(dayjs())
}
