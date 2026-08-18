import dayjs, { type Dayjs } from 'dayjs'

export type RecurrenceType = 'NONE' | 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'CUSTOM'

export interface ParsedRecurrence {
  type: RecurrenceType
  config: Record<string, number | string>
}

export interface RecognitionToken {
  kind: 'date' | 'time' | 'recurrence'
  text: string
  label: string
}

export interface ParsedTaskText {
  originalText: string
  title: string
  dueAt: string | null
  recurrence: ParsedRecurrence | null
  tokens: RecognitionToken[]
}

export interface ParseOptions {
  disabledTokens?: ReadonlySet<string>
}

const WEEKDAY_MAP: Record<string, number> = {
  一: 0,
  二: 1,
  三: 2,
  四: 3,
  五: 4,
  六: 5,
  日: 6,
  天: 6,
}

function startOfLocalDay(reference: Dayjs): Dayjs {
  return reference.hour(0).minute(0).second(0).millisecond(0)
}

function nextWeekday(reference: Dayjs, weekday: number, forceNextWeek = false): Dayjs {
  const start = startOfLocalDay(reference)
  const currentWeekday = (start.day() + 6) % 7
  const monday = start.subtract(currentWeekday, 'day')
  if (forceNextWeek) return monday.add(7 + weekday, 'day')
  const candidate = monday.add(weekday, 'day')
  return candidate.isBefore(start, 'day') ? candidate.add(7, 'day') : candidate
}

function nextMonthDay(reference: Dayjs, day: number): Dayjs {
  const start = startOfLocalDay(reference)
  let candidate = start.date(Math.min(day, start.daysInMonth()))
  if (candidate.isBefore(start, 'day')) {
    const nextMonth = start.add(1, 'month').date(1)
    candidate = nextMonth.date(Math.min(day, nextMonth.daysInMonth()))
  }
  return candidate
}

function explicitMonthDay(reference: Dayjs, month: number, day: number): Dayjs | null {
  const start = startOfLocalDay(reference)
  let candidate = dayjs(new Date(start.year(), month - 1, day, 0, 0, 0, 0))
  if (candidate.month() !== month - 1 || candidate.date() !== day) return null
  if (candidate.isBefore(start, 'day')) candidate = candidate.add(1, 'year')
  return candidate
}

function cleanTitle(value: string): string {
  return value.replace(/[，,。；;]+/g, ' ').replace(/\s+/g, ' ').trim()
}

export function parseTaskText(text: string, reference: Dayjs = dayjs(), options: ParseOptions = {}): ParsedTaskText {
  const originalText = text.trim()
  let remaining = originalText
  let dueDate: Dayjs | null = null
  let hour = 0
  let minute = 0
  let hasTime = false
  let recurrence: ParsedRecurrence | null = null
  const tokens: RecognitionToken[] = []
  const isDisabled = (kind: RecognitionToken['kind'], tokenText: string) => options.disabledTokens?.has(`${kind}:${tokenText}`) ?? false

  const daily = remaining.match(/每天/)
  const weekly = remaining.match(/每周([一二三四五六日天])/)
  const monthly = remaining.match(/每月(\d{1,2})(?:日|号)/)
  if (weekly && !isDisabled('recurrence', weekly[0])) {
    const weekday = WEEKDAY_MAP[weekly[1]]
    recurrence = { type: 'WEEKLY', config: { weekday } }
    dueDate = nextWeekday(reference, weekday)
    tokens.push({ kind: 'recurrence', text: weekly[0], label: weekly[0] })
    remaining = remaining.replace(weekly[0], ' ')
  } else if (monthly && !isDisabled('recurrence', monthly[0])) {
    const day = Number(monthly[1])
    if (day >= 1 && day <= 31) {
      recurrence = { type: 'MONTHLY', config: { day } }
      dueDate = nextMonthDay(reference, day)
      tokens.push({ kind: 'recurrence', text: monthly[0], label: monthly[0] })
      remaining = remaining.replace(monthly[0], ' ')
    }
  } else if (daily && !isDisabled('recurrence', daily[0])) {
    recurrence = { type: 'DAILY', config: {} }
    dueDate = startOfLocalDay(reference)
    tokens.push({ kind: 'recurrence', text: daily[0], label: daily[0] })
    remaining = remaining.replace(daily[0], ' ')
  }

  const relativeDate = remaining.match(/今天|明天|后天/)
  const nextWeekDate = remaining.match(/下周([一二三四五六日天])/)
  const weekdayDate = remaining.match(/周([一二三四五六日天])/)
  const monthDate = remaining.match(/(\d{1,2})月(\d{1,2})(?:日|号)/)
  if (relativeDate && !isDisabled('date', relativeDate[0])) {
    const offset = relativeDate[0] === '今天' ? 0 : relativeDate[0] === '明天' ? 1 : 2
    dueDate = startOfLocalDay(reference).add(offset, 'day')
    tokens.push({ kind: 'date', text: relativeDate[0], label: relativeDate[0] })
    remaining = remaining.replace(relativeDate[0], ' ')
  } else if (nextWeekDate && !isDisabled('date', nextWeekDate[0])) {
    dueDate = nextWeekday(reference, WEEKDAY_MAP[nextWeekDate[1]], true)
    tokens.push({ kind: 'date', text: nextWeekDate[0], label: nextWeekDate[0] })
    remaining = remaining.replace(nextWeekDate[0], ' ')
  } else if (weekdayDate && !isDisabled('date', weekdayDate[0])) {
    dueDate = nextWeekday(reference, WEEKDAY_MAP[weekdayDate[1]])
    tokens.push({ kind: 'date', text: weekdayDate[0], label: weekdayDate[0] })
    remaining = remaining.replace(weekdayDate[0], ' ')
  } else if (monthDate && !isDisabled('date', monthDate[0])) {
    const parsedDate = explicitMonthDay(reference, Number(monthDate[1]), Number(monthDate[2]))
    if (parsedDate) {
      dueDate = parsedDate
      tokens.push({ kind: 'date', text: monthDate[0], label: monthDate[0] })
      remaining = remaining.replace(monthDate[0], ' ')
    }
  }

  const chineseTime = remaining.match(/(上午|下午|晚上)?\s*(\d{1,2})点(半)?/)
  const numericTime = remaining.match(/(?:^|\s)([01]?\d|2[0-3]):([0-5]\d)(?=\s|$)/)
  if (chineseTime && !isDisabled('time', chineseTime[0].trim())) {
    const period = chineseTime[1]
    hour = Number(chineseTime[2])
    minute = chineseTime[3] ? 30 : 0
    if ((period === '下午' || period === '晚上') && hour < 12) hour += 12
    if (period === '上午' && hour === 12) hour = 0
    if (hour <= 23) {
      hasTime = true
      const label = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`
      tokens.push({ kind: 'time', text: chineseTime[0].trim(), label })
      remaining = remaining.replace(chineseTime[0], ' ')
    }
  } else if (numericTime && !isDisabled('time', numericTime[0].trim())) {
    hour = Number(numericTime[1])
    minute = Number(numericTime[2])
    hasTime = true
    const matchedText = numericTime[0].trim()
    tokens.push({ kind: 'time', text: matchedText, label: matchedText })
    remaining = remaining.replace(numericTime[0], ' ')
  }

  if (hasTime && dueDate === null) dueDate = startOfLocalDay(reference)
  if (dueDate !== null) dueDate = dueDate.hour(hour).minute(minute).second(0).millisecond(0)

  return {
    originalText,
    title: cleanTitle(remaining) || originalText,
    dueAt: dueDate?.format('YYYY-MM-DDTHH:mm:ss') ?? null,
    recurrence,
    tokens,
  }
}
