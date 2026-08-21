export const TABLE_MIN_COLUMN_WIDTH = 96
export const TABLE_MAX_INSERT_COLUMNS = 8

/** Keep newly inserted columns readable within the editor's content width. */
export function tableColumnLimit(contentWidth: number): number {
  if (!Number.isFinite(contentWidth) || contentWidth <= 0) return 3
  return Math.max(1, Math.min(TABLE_MAX_INSERT_COLUMNS, Math.floor(contentWidth / TABLE_MIN_COLUMN_WIDTH)))
}

