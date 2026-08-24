import type { JSONContent } from '@tiptap/core'

import type { Attachment, Note } from '@/services/api'

type MarkdownNode = JSONContent & {
  attrs?: Record<string, unknown>
  content?: MarkdownNode[]
  marks?: Array<{ type?: string; attrs?: Record<string, unknown> }>
  text?: string
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function nodesOf(value: unknown): MarkdownNode[] {
  if (!Array.isArray(value)) return []
  return value.filter(isRecord).map((item) => item as MarkdownNode)
}

function attrsOf(node: MarkdownNode): Record<string, unknown> {
  return isRecord(node.attrs) ? node.attrs : {}
}

function childrenOf(node: MarkdownNode): MarkdownNode[] {
  return nodesOf(node.content)
}

function escapeText(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/([`*_#[\]~])/g, '\\$1')
}

function escapeTableCell(value: string): string {
  return value.replace(/\|/g, '\\|').replace(/\r?\n/g, ' ')
}

function escapeUrl(value: string): string {
  return value.replace(/[\s<>]/g, (character) => encodeURIComponent(character)).replace(/\)/g, '%29')
}

function renderInline(node: MarkdownNode): string {
  if (node.type === 'text') {
    let value = escapeText(String(node.text ?? ''))
    for (const mark of node.marks ?? []) {
      const type = mark.type
      if (type === 'bold') value = `**${value}**`
      else if (type === 'italic') value = `*${value}*`
      else if (type === 'strike') value = `~~${value}~~`
      else if (type === 'code') value = `\`${String(node.text ?? '').replace(/`/g, '\\`')}\``
      else if (type === 'link') {
        const href = typeof mark.attrs?.href === 'string' ? mark.attrs.href.trim() : ''
        if (href) value = `[${value}](${escapeUrl(href)})`
      }
    }
    return value
  }
  if (node.type === 'hardBreak') return '  \n'
  if (node.type === 'image') {
    const attrs = attrsOf(node)
    const src = typeof attrs.src === 'string' ? attrs.src : ''
    if (!src) return ''
    const alt = typeof attrs.alt === 'string' ? attrs.alt : ''
    return `![${escapeText(alt)}](${escapeUrl(src)})`
  }
  if (node.type === 'taskReference') {
    const taskAttrs = attrsOf(node)
    const taskId = typeof taskAttrs.taskId === 'string' ? taskAttrs.taskId : '任务'
    return `[[${escapeText(taskId)}]]`
  }
  return childrenOf(node).map(renderInline).join('')
}

function renderInlineContent(nodes: MarkdownNode[]): string {
  return nodes.map(renderInline).join('')
}

function renderTable(node: MarkdownNode, depth: number): string {
  const rows = childrenOf(node).filter((child) => child.type === 'tableRow')
  if (!rows.length) return ''
  const renderedRows = rows.map((row) => {
    const cells = childrenOf(row).filter((child) => child.type === 'tableCell' || child.type === 'tableHeader')
    const values = cells.map((cell) => escapeTableCell(renderInlineContent(childrenOf(cell).flatMap(childrenOf))))
    return `| ${values.join(' | ')} |`
  })
  const width = Math.max(1, childrenOf(rows[0]).length)
  const divider = `| ${Array.from({ length: width }, () => '---').join(' | ')} |`
  const indent = '  '.repeat(depth)
  return [renderedRows[0], divider, ...renderedRows.slice(1)].map((line) => `${indent}${line}`).join('\n')
}

function renderList(node: MarkdownNode, depth: number): string {
  const ordered = node.type === 'orderedList'
  const start = typeof attrsOf(node).start === 'number' ? attrsOf(node).start as number : 1
  const indent = '  '.repeat(depth)
  return childrenOf(node).map((item, index) => {
    const blocks = childrenOf(item)
    const first = blocks[0]
    const firstText = first ? renderBlock(first, depth) : ''
    const prefix = item.type === 'taskItem'
      ? `- [${attrsOf(item).checked ? 'x' : ' '}] `
      : ordered ? `${start + index}. ` : '- '
    const firstLines = firstText.split('\n')
    let result = `${indent}${prefix}${firstLines[0] ?? ''}`
    firstLines.slice(1).forEach((line) => { result += `\n${indent}  ${line}` })
    blocks.slice(1).forEach((block) => {
      const rendered = renderBlock(block, depth + 1)
      if (rendered) result += `\n${rendered}`
    })
    return result
  }).join('\n')
}

function renderBlock(node: MarkdownNode, depth = 0): string {
  const children = childrenOf(node)
  if (node.type === 'paragraph') return renderInlineContent(children)
  if (node.type === 'heading') {
    const level = Math.max(1, Math.min(6, Number(attrsOf(node).level) || 1))
    return `${'#'.repeat(level)} ${renderInlineContent(children)}`
  }
  if (node.type === 'blockquote') {
    return renderBlocks(children, depth).split('\n').map((line) => `${'  '.repeat(depth)}> ${line}`).join('\n')
  }
  if (node.type === 'bulletList' || node.type === 'orderedList' || node.type === 'taskList') return renderList(node, depth)
  if (node.type === 'codeBlock') {
    const language = typeof attrsOf(node).language === 'string' ? attrsOf(node).language : ''
    const code = children.map((child) => String(child.text ?? '')).join('')
    return `${'  '.repeat(depth)}\`\`\`${language}\n${code}\n${'  '.repeat(depth)}\`\`\``
  }
  if (node.type === 'horizontalRule') return `${'  '.repeat(depth)}---`
  if (node.type === 'table') return renderTable(node, depth)
  if (node.type === 'image' || node.type === 'taskReference') return `${'  '.repeat(depth)}${renderInline(node)}`
  if (node.type === 'doc') return renderBlocks(children, depth)
  return children.length ? renderBlocks(children, depth) : renderInline(node)
}

function renderBlocks(nodes: MarkdownNode[], depth = 0): string {
  return nodes.map((node) => renderBlock(node, depth)).filter(Boolean).join('\n\n')
}

function quoteFrontMatter(value: string): string {
  return `'${value.replace(/\r?\n/g, ' ').replace(/'/g, "''")}'`
}

function renderAttachments(attachments: Attachment[]): string {
  if (!attachments.length) return ''
  const lines = attachments.map((attachment) => `- [${escapeText(attachment.originalName)}](${escapeUrl(attachment.url)})`)
  return `## 附件\n\n${lines.join('\n')}`
}

/** Serialize a personal note into a Markdown document that can be imported again. */
export function noteToMarkdown(note: Pick<Note, 'title' | 'contentJson'>, attachments: Attachment[] = []): string {
  const title = note.title.trim() || '未命名笔记'
  const body = renderBlock(note.contentJson as MarkdownNode).trim()
  const attachmentSection = renderAttachments(attachments)
  const sections = [body, attachmentSection].filter(Boolean)
  return [`---\ntitle: ${quoteFrontMatter(title)}\n---`, sections.join('\n\n')].filter(Boolean).join('\n\n') + '\n'
}
