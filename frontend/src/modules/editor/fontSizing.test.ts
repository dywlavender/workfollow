import { describe, expect, it } from 'vitest'

import { normalizeFontSize } from './fontSizing'

describe('editor font sizing', () => {
  it('accepts the supported preset sizes', () => {
    expect(normalizeFontSize('12px')).toBe('12px')
    expect(normalizeFontSize(' 20PX ')).toBe('20px')
    expect(normalizeFontSize('24px')).toBe('24px')
  })

  it('rejects arbitrary or malformed values', () => {
    expect(normalizeFontSize('13px')).toBeNull()
    expect(normalizeFontSize('120%')).toBeNull()
    expect(normalizeFontSize('var(--font-size-body)')).toBeNull()
    expect(normalizeFontSize(null)).toBeNull()
  })
})
