import dayjs from 'dayjs'
import { describe, expect, it } from 'vitest'

import { dateOnlyDueAt, isDateOnlyDue } from './dueDate'

describe('date-only todo due dates', () => {
  it('normalizes a manual default to the start of that day', () => {
    expect(dateOnlyDueAt(dayjs('2026-08-09T16:42:31'))).toBe('2026-08-09T00:00:00')
  })

  it('distinguishes a date-only task from an explicitly timed task', () => {
    expect(isDateOnlyDue('2026-08-09T00:00:00')).toBe(true)
    expect(isDateOnlyDue('2026-08-09T18:00:00')).toBe(false)
  })
})
