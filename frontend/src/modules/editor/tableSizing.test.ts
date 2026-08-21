import { describe, expect, it } from 'vitest'

import { TABLE_MAX_INSERT_COLUMNS, tableColumnLimit } from './tableSizing'

describe('table sizing', () => {
  it('reduces the selectable columns for narrow editors', () => {
    expect(tableColumnLimit(320)).toBe(3)
    expect(tableColumnLimit(190)).toBe(1)
  })

  it('caps wide editors at the supported grid size', () => {
    expect(tableColumnLimit(840)).toBe(TABLE_MAX_INSERT_COLUMNS)
    expect(tableColumnLimit(1600)).toBe(TABLE_MAX_INSERT_COLUMNS)
  })

  it('uses a safe default before the editor is measured', () => {
    expect(tableColumnLimit(0)).toBe(3)
    expect(tableColumnLimit(Number.NaN)).toBe(3)
  })
})

