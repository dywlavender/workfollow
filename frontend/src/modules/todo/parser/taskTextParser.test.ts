import dayjs from 'dayjs'
import { describe, expect, it } from 'vitest'

import { parseTaskText } from './taskTextParser'


const friday = dayjs('2026-08-07T10:00:00')

describe('parseTaskText', () => {
  it.each([
    ['今天完成接口', '完成接口', '2026-08-07T00:00:00'],
    ['明天完成接口', '完成接口', '2026-08-08T00:00:00'],
    ['后天下午3点完成接口', '完成接口', '2026-08-09T15:00:00'],
    ['下周一上午9点需求评审', '需求评审', '2026-08-10T09:00:00'],
    ['8月10号 09:30 发布版本', '发布版本', '2026-08-10T09:30:00'],
  ])('parses %s', (input, title, dueAt) => {
    const result = parseTaskText(input, friday)

    expect(result.title).toBe(title)
    expect(result.dueAt).toBe(dueAt)
  })

  it('parses weekly recurrence', () => {
    const result = parseTaskText('每周五整理周报', friday)

    expect(result.title).toBe('整理周报')
    expect(result.recurrence).toEqual({ type: 'WEEKLY', config: { weekday: 4 } })
    expect(result.dueAt).toBe('2026-08-07T00:00:00')
  })

  it('parses monthly recurrence', () => {
    const result = parseTaskText('每月10号检查数据', friday)

    expect(result.title).toBe('检查数据')
    expect(result.recurrence).toEqual({ type: 'MONTHLY', config: { day: 10 } })
    expect(result.dueAt).toBe('2026-08-10T00:00:00')
  })

  it('keeps an ordinary todo in the inbox', () => {
    const result = parseTaskText('研究一下 Oracle 执行计划', friday)

    expect(result.title).toBe('研究一下 Oracle 执行计划')
    expect(result.dueAt).toBeNull()
    expect(result.recurrence).toBeNull()
    expect(result.tokens).toEqual([])
  })

  it('can cancel one recognition token without cancelling the others', () => {
    const result = parseTaskText('明天 15:00 完成评审', friday, {
      disabledTokens: new Set(['date:明天']),
    })

    expect(result.dueAt).toBe('2026-08-07T15:00:00')
    expect(result.tokens).toEqual([{ kind: 'time', text: '15:00', label: '15:00' }])
  })
})
