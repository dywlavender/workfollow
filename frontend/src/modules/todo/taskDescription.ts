type RichTextNode = {
  type?: string
  text?: string
  content?: RichTextNode[]
}

const namedEntities: Record<string, string> = {
  amp: '&', apos: "'", gt: '>', lt: '<', nbsp: ' ', quot: '"',
}

function decodeHtmlEntities(value: string): string {
  return value.replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (entity, code: string) => {
    if (code[0] === '#') {
      const hexadecimal = code[1]?.toLowerCase() === 'x'
      const numeric = Number.parseInt(code.slice(hexadecimal ? 2 : 1), hexadecimal ? 16 : 10)
      if (!Number.isFinite(numeric) || numeric < 0 || numeric > 0x10ffff) return entity
      try { return String.fromCodePoint(numeric) } catch { return entity }
    }
    return namedEntities[code.toLowerCase()] ?? entity
  })
}

function textFromRichContent(node: RichTextNode): string {
  if (node.type === 'text') return node.text ?? ''
  if (node.type === 'hardBreak') return '\n'
  const content = node.content?.map(textFromRichContent).join('') ?? ''
  return ['paragraph', 'heading', 'listItem', 'blockquote', 'codeBlock'].includes(node.type ?? '')
    ? `${content}\n`
    : content
}

function normalizeDescription(value: string): string {
  return decodeHtmlEntities(value)
    .replace(/[\u200b-\u200d\ufeff]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

/** Converts legacy HTML, plain text, or ProseMirror JSON to safe list-preview text. */
export function taskDescriptionText(description?: string | null, contentJson?: unknown): string {
  const source = description?.trim() ?? ''
  if (source) {
    const withoutUnsafeContent = source.replace(/<(script|style|template|svg|math)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, ' ')
    const withBlockSpacing = withoutUnsafeContent.replace(/<\s*(?:br\s*\/?|\/?(?:p|div|li|h[1-6]|blockquote|pre|tr))\b[^>]*>/gi, ' ')
    return normalizeDescription(withBlockSpacing.replace(/<[^>]*>/g, ''))
  }

  if (contentJson && typeof contentJson === 'object') {
    return normalizeDescription(textFromRichContent(contentJson as RichTextNode))
  }
  return ''
}
