import { describe, expect, it } from 'vitest'

import { formatLastSavedAt } from './saveStatus'

describe('last saved status', () => {
  it('uses a full numeric date and time', () => {
    expect(formatLastSavedAt('2026-08-27T09:04:05')).toBe('最近保存于 2026-08-27 09:04')
  })

  it('falls back when no valid timestamp is available', () => {
    expect(formatLastSavedAt(null)).toBe('尚未保存')
    expect(formatLastSavedAt('not-a-date')).toBe('尚未保存')
  })
})
