// 主题视觉基线截图:登录测试账号后,对全部主题 × 明暗模式截工作台图,
// 再补一张设置页主题分组总览。输出到仓库根 output/playwright/theme-baseline/
// (output/ 已在 .gitignore 中,基线只留在本地用于肉眼对比)。
//
// 用法:
//   node scripts/visual-check.mjs                     # 全量 13 主题 × 2 模式
//   SUFFIX=after PALETTES=winter,damo node scripts/visual-check.mjs   # 抽查
//
// 环境变量:BASE_URL(默认 127.0.0.1:5173)、OUT_DIR、SUFFIX、PALETTES、MODES(CSV 过滤)。
// 依赖全局 playwright + 系统 Chrome:npm i -g playwright && npx playwright install chrome
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import fs from 'node:fs'

const require = createRequire(import.meta.url)
const { chromium } = require('/opt/homebrew/lib/node_modules/playwright')

// 与 src/modules/theme.ts 的 appearancePalettes 保持同步。
const ALL_PALETTES = [
  'default', 'sky', 'teal', 'amber', 'purple',
  'spring', 'summer', 'autumn', 'winter',
  'qianshan', 'jiangnan', 'damo', 'pinghu',
]
const ALL_MODES = ['light', 'dark']
const BASE = process.env.BASE_URL || 'http://127.0.0.1:5173'
const SUFFIX = process.env.SUFFIX ? `-${process.env.SUFFIX}` : ''
const OUT_DIR = process.env.OUT_DIR
  || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../output/playwright/theme-baseline')
const USER = { username: 'claude-preview', password: 'preview-pass-123' }
const PALETTES = (process.env.PALETTES?.split(',').filter(Boolean)) ?? ALL_PALETTES
const MODES = (process.env.MODES?.split(',').filter(Boolean)) ?? ALL_MODES

fs.mkdirSync(OUT_DIR, { recursive: true })

async function ensureAuth(page) {
  const registerStatus = await page.evaluate(async ({ username, password }) => {
    const res = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ username, password }),
    })
    return res.status
  }, USER)
  if (registerStatus === 200) return
  const loginStatus = await page.evaluate(async ({ username, password }) => {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ identifier: username, password }),
    })
    return res.status
  }, USER)
  if (loginStatus !== 200) throw new Error(`auth failed: register=${registerStatus} login=${loginStatus}`)
}

async function seedTodosIfEmpty(page) {
  await page.evaluate(async () => {
    const res = await fetch('/api/todos', { credentials: 'include' })
    if (!res.ok) return
    const data = await res.json()
    const items = Array.isArray(data) ? data : data.items ?? []
    if (items.length > 0) return
    const seeds = ['整理季度 OKR 草稿', '回复设计评审意见', '准备周会演示要点']
    for (const title of seeds) {
      await fetch('/api/todos', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ title }),
      })
    }
  })
}

async function main() {
  const browser = await chromium.launch({ channel: 'chrome', headless: true })

  for (const palette of PALETTES) {
    for (const mode of MODES) {
      const context = await browser.newContext({ viewport: { width: 1440, height: 900 } })
      await context.addInitScript(
        ({ p, m }) => {
          localStorage.setItem('workfollow-appearance-v2-palette', p)
          localStorage.setItem('workfollow-appearance-v2-mode', m)
          localStorage.setItem('workfollow-appearance-v2-background', 'theme')
        },
        { p: palette, m: mode },
      )
      const page = await context.newPage()
      await page.goto(BASE, { waitUntil: 'networkidle' }).catch(() => {})
      await ensureAuth(page)
      await seedTodosIfEmpty(page)

      await page.goto(BASE + '/todos', { waitUntil: 'networkidle' }).catch(() => {})
      await page.waitForTimeout(2000)
      // 点开一条任务让详情面板参与对比;找不到就只截列表区。
      for (const title of ['整理季度 OKR 草稿', '回复设计评审意见', '准备周会演示要点']) {
        if (await page.getByText(title).count()) {
          await page.getByText(title).first().click().catch(() => {})
          break
        }
      }
      await page.waitForTimeout(800)
      const file = path.join(OUT_DIR, `workbench-${palette}-${mode}${SUFFIX}.png`)
      await page.screenshot({ path: file })
      console.log('shot:', file)
      await context.close()
    }
  }

  // 设置页:三个主题分组 + 迷你场景色板总览
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } })
  const page = await context.newPage()
  await page.goto(BASE, { waitUntil: 'networkidle' }).catch(() => {})
  await ensureAuth(page)
  await page.goto(BASE + '/settings', { waitUntil: 'networkidle' }).catch(() => {})
  await page.waitForTimeout(1200)
  await page.locator('.appearance-theme-grid').first().scrollIntoViewIfNeeded()
  await page.waitForTimeout(400)
  const settingsFile = path.join(OUT_DIR, `settings-swatches${SUFFIX}.png`)
  await page.screenshot({ path: settingsFile })
  console.log('shot:', settingsFile)
  await context.close()

  await browser.close()
  console.log('ALL DONE')
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
