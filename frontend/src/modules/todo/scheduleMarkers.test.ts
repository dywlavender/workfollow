import dayjs from 'dayjs'
import { describe, expect, it } from 'vitest'

import { getScheduleMarkers } from './scheduleMarkers'

const visibleDays = (start: string, count: number) => Array.from(
  { length: count },
  (_, index) => dayjs(start).add(index, 'day'),
)

describe('task schedule markers', () => {
  it('marks every day in a date range', () => {
    const markers = getScheduleMarkers({
      startDate: '2026-08-25T00:00:00',
      endDate: '2026-08-28T00:00:00',
      visibleDays: visibleDays('2026-08-24', 10),
    })

    expect([...markers.scheduled]).toEqual(['2026-08-25', '2026-08-26', '2026-08-27', '2026-08-28'])
    expect([...markers.range]).toEqual(['2026-08-25', '2026-08-26', '2026-08-27', '2026-08-28'])
    expect(markers.recurring.size).toBe(0)
  })

  it('marks visible daily occurrences without creating future records', () => {
    const markers = getScheduleMarkers({
      startDate: '2026-08-25T00:00:00',
      recurrenceType: 'DAILY',
      visibleDays: visibleDays('2026-08-24', 11),
    })

    expect([...markers.scheduled]).toEqual([
      '2026-08-25', '2026-08-26', '2026-08-27', '2026-08-28', '2026-08-29',
      '2026-08-30', '2026-08-31', '2026-09-01', '2026-09-02', '2026-09-03',
    ])
    expect(markers.range.size).toBe(0)
    expect(markers.recurring).toEqual(markers.scheduled)
  })

  it('respects weekly intervals', () => {
    const markers = getScheduleMarkers({
      startDate: '2026-08-07T00:00:00',
      recurrenceType: 'WEEKLY',
      recurrenceConfig: { interval: 2 },
      visibleDays: visibleDays('2026-08-01', 31),
    })

    expect([...markers.scheduled]).toEqual(['2026-08-07', '2026-08-21'])
  })

  it('uses the backend-compatible end-of-month behavior', () => {
    const markers = getScheduleMarkers({
      startDate: '2026-01-31T00:00:00',
      recurrenceType: 'MONTHLY',
      visibleDays: visibleDays('2026-02-01', 60),
    })

    expect(markers.scheduled.has('2026-02-28')).toBe(true)
    expect(markers.scheduled.has('2026-03-31')).toBe(true)
  })

  it('supports custom recurrence rules', () => {
    const markers = getScheduleMarkers({
      startDate: '2026-08-03T00:00:00',
      recurrenceType: 'CUSTOM',
      recurrenceConfig: { frequency: 'WEEKLY', interval: 2 },
      visibleDays: visibleDays('2026-08-01', 31),
    })

    expect([...markers.scheduled]).toEqual(['2026-08-03', '2026-08-17', '2026-08-31'])
  })

  it('follows the previous due day for custom monthly recurrence', () => {
    const markers = getScheduleMarkers({
      startDate: '2026-01-31T00:00:00',
      recurrenceType: 'CUSTOM',
      recurrenceConfig: { frequency: 'MONTHLY', interval: 1 },
      visibleDays: visibleDays('2026-02-01', 90),
    })

    expect(markers.scheduled.has('2026-02-28')).toBe(true)
    expect(markers.scheduled.has('2026-03-28')).toBe(true)
    expect(markers.scheduled.has('2026-03-31')).toBe(false)
  })
})
