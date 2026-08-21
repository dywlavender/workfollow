import { describe, expect, it } from 'vitest'

import {
  MAX_IMAGE_WIDTH_PERCENT,
  MIN_IMAGE_WIDTH_PERCENT,
  normalizeImageWidth,
} from './imageSizing'

describe('image sizing', () => {
  it('keeps an unset width responsive', () => {
    expect(normalizeImageWidth(null)).toBeNull()
    expect(normalizeImageWidth(undefined)).toBeNull()
  })

  it('clamps and rounds persisted widths', () => {
    expect(normalizeImageWidth(12)).toBe(MIN_IMAGE_WIDTH_PERCENT)
    expect(normalizeImageWidth(68.436)).toBe(68.44)
    expect(normalizeImageWidth(120)).toBe(MAX_IMAGE_WIDTH_PERCENT)
  })

  it('rejects invalid widths', () => {
    expect(normalizeImageWidth('not-a-number')).toBeNull()
  })
})
