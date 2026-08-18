/** Keeps an unknown count visually distinct from a confirmed zero. */
export function taskCountLabel(hasLoadedCounts: boolean, count: number): string {
  return hasLoadedCounts ? String(count) : '—'
}
