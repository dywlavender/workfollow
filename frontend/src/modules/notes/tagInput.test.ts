import { describe, expect, it } from 'vitest'

import { formatTagInput, parseTagInput } from './tagInput'

describe('team submission tag input', () => {
  it('preserves spaces inside a tag when personal tags are carried into a submission', () => {
    const input = formatTagInput(['性能 优化', '会议记录'])

    expect(input).toBe('性能 优化, 会议记录')
    expect(parseTagInput(input)).toEqual(['性能 优化', '会议记录'])
  })

  it('normalizes prefixes, whitespace, Chinese commas, and display-case duplicates', () => {
    expect(parseTagInput(' #项目A ，  性能   优化,work,WORK ')).toEqual(['项目A', '性能 优化', 'work'])
  })
})
