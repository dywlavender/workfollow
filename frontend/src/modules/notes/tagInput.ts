export function parseTagInput(value: string): string[] {
  const result: string[] = []
  const keys = new Set<string>()
  for (const raw of value.split(/[,，]/)) {
    const tag = raw.trim().replace(/^#+/, '').trim().replace(/\s+/g, ' ')
    if (!tag || tag.length > 50) continue
    const key = tag.toLocaleLowerCase()
    if (keys.has(key)) continue
    keys.add(key)
    result.push(tag)
    if (result.length >= 20) break
  }
  return result
}

export function formatTagInput(tags: string[]): string {
  return tags.join(', ')
}
