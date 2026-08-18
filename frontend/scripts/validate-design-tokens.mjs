import { readFile, readdir } from 'node:fs/promises'
import { extname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const sourceRoot = fileURLToPath(new URL('../src/', import.meta.url))
const tokenFile = 'design-tokens.css'
const oldTokens = /var\(--(?:bg-page|bg-sidebar|bg-panel|bg-hover|bg-muted|bg-selected|text-primary|text-secondary|text-tertiary|border-light|border-normal|primary|primary-hover|primary-dark|primary-soft|text-on-primary|success|success-soft|danger|danger-hover|danger-soft|bg|panel|line|text|muted|metric|metric-soft|sidebar-rail-[a-z-]+|surface-code|text-on-code|highlight)\)/g
const rawColor = /#[0-9a-fA-F]{3,8}\b|rgba?\([^;})]+\)/g
const rawType = /font-size:\s*(?:[0-9.]+(?:px|rem|em)|clamp\()|font-weight:\s*[0-9]+/g
const rawFontFamily = /font-family:(?!\s*(?:var\(|inherit\b))\s*[^;}\n]+/g
const failures = []

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const path = join(directory, entry.name)
    if (entry.isDirectory()) files.push(...await walk(path))
    else if (['.css', '.vue'].includes(extname(entry.name))) files.push(path)
  }
  return files
}

for (const file of await walk(sourceRoot)) {
  if (file.endsWith(tokenFile)) continue
  const content = await readFile(file, 'utf8')
  for (const [label, pattern] of [
    ['legacy token', oldTokens],
    ['raw color', rawColor],
    ['raw typography', rawType],
    ['raw font family', rawFontFamily],
  ]) {
    for (const match of content.matchAll(pattern)) {
      const line = content.slice(0, match.index).split('\n').length
      failures.push(`${relative(sourceRoot, file)}:${line} ${label}: ${match[0]}`)
    }
  }
}

if (failures.length) {
  console.error(`Design token validation failed (${failures.length}):`)
  console.error(failures.join('\n'))
  process.exitCode = 1
} else {
  console.log('Design token validation passed.')
}
