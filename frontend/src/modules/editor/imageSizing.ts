export const MIN_IMAGE_WIDTH_PERCENT = 20
export const MAX_IMAGE_WIDTH_PERCENT = 100
const IMAGE_WIDTH_PRECISION = 100

/**
 * Image width is persisted as a percentage of the editor content width.
 * Keeping the value numeric makes it safe to use in both JSON and inline CSS.
 */
export function normalizeImageWidth(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null

  const numeric = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(numeric)) return null

  const clamped = Math.min(MAX_IMAGE_WIDTH_PERCENT, Math.max(MIN_IMAGE_WIDTH_PERCENT, numeric))
  return Math.round(clamped * IMAGE_WIDTH_PRECISION) / IMAGE_WIDTH_PRECISION
}
