/**
 * Normalize editor-only JSON differences before comparing a local Yjs
 * document with the relational projection. Tiptap may add block ids and
 * default null attributes while mounting; those are useful in the editor but
 * are not a user edit and must not make a navigation/action barrier wait
 * forever for a byte-for-byte match that can never occur.
 */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize)
  if (!isRecord(value)) return value

  const result: Record<string, unknown> = {}
  for (const key of Object.keys(value).sort()) {
    const child = value[key]
    if (key === 'attrs' && isRecord(child)) {
      const attrs: Record<string, unknown> = {}
      for (const attrKey of Object.keys(child).sort()) {
        if (attrKey === 'blockId' || child[attrKey] === null) continue
        attrs[attrKey] = canonicalize(child[attrKey])
      }
      if (Object.keys(attrs).length > 0) result[key] = attrs
      continue
    }
    if (key === 'content' && Array.isArray(child)) {
      if (child.length > 0) result[key] = child.map(canonicalize)
      continue
    }
    result[key] = canonicalize(child)
  }
  return result
}

export function contentJsonSemanticallyEqual(left: unknown, right: unknown): boolean {
  return JSON.stringify(canonicalize(left)) === JSON.stringify(canonicalize(right))
}
