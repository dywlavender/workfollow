export const workFollowFontSizes = [
  { label: '默认', value: null },
  { label: '小', value: '12px' },
  { label: '正文', value: '14px' },
  { label: '较大', value: '16px' },
  { label: '大', value: '18px' },
  { label: '标题', value: '20px' },
  { label: '特大', value: '24px' },
] as const

const allowedFontSizes = new Set<string>(
  workFollowFontSizes.flatMap((option) => option.value ? [option.value] : []),
)

/** Only persist the product's supported sizes so imported content cannot
 * introduce arbitrary inline typography. */
export function normalizeFontSize(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const normalized = value.trim().toLowerCase()
  return allowedFontSizes.has(normalized) ? normalized : null
}
