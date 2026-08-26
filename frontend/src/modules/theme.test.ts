import { describe, expect, it, vi } from 'vitest'

import {
  appearanceBackgrounds,
  appearancePalettes,
  createNaiveThemeOverrides,
  getStoredAppearance,
  resolveAppearanceMode,
} from './theme'

describe('appearance theme matrix', () => {
  it('exposes thirteen curated palettes across classic, season, and scenic groups', () => {
    expect(appearancePalettes).toHaveLength(13)
    expect(appearancePalettes.map((palette) => palette.id)).toEqual([
      'default', 'sky', 'teal', 'amber', 'purple', 'spring', 'summer', 'autumn', 'winter',
      'qianshan', 'jiangnan', 'damo', 'pinghu',
    ])
  })

  it('ships four seasonal palettes with a built-in atmosphere and translucent page surfaces', () => {
    const seasonal = appearancePalettes.filter((palette) => palette.group === 'season')
    expect(seasonal.map((palette) => palette.id)).toEqual(['spring', 'summer', 'autumn', 'winter'])
    for (const palette of seasonal) {
      expect(palette.atmosphere?.light).toBeTruthy()
      expect(palette.atmosphere?.dark).toBeTruthy()
      expect(palette.light.page.startsWith('rgb')).toBe(true)
      expect(palette.light.page).toContain('/ .')
      expect(palette.dark.page).toContain('/ .')
    }
    const classic = appearancePalettes.filter((palette) => !palette.group || palette.group === 'classic')
    expect(classic).toHaveLength(5)
    for (const palette of classic) {
      expect(palette.atmosphere).toBeUndefined()
    }
    const scenic = appearancePalettes.filter((palette) => palette.group === 'scenic')
    expect(scenic.map((palette) => palette.id)).toEqual(['qianshan', 'jiangnan', 'damo', 'pinghu'])
    for (const palette of scenic) {
      expect(palette.atmosphere?.light).toBeTruthy()
      expect(palette.atmosphere?.dark).toBeTruthy()
      expect(palette.light.page.startsWith('rgb')).toBe(true)
      expect(palette.light.page).toContain('/ .')
      expect(palette.dark.page).toContain('/ .')
    }
  })

  it('ships light and dark scene tokens for every seasonal and scenic palette', () => {
    const scenePalettes = appearancePalettes.filter((palette) => palette.group === 'season' || palette.group === 'scenic')
    for (const palette of scenePalettes) {
      expect(Object.keys(palette.scene?.light ?? {})).not.toHaveLength(0)
      expect(Object.keys(palette.scene?.dark ?? {})).not.toHaveLength(0)
    }
  })

  it('keeps every background preset aligned with the light and dark surface tokens', () => {
    for (const background of appearanceBackgrounds) {
      if (!background.light || !background.dark) continue
      const light = createNaiveThemeOverrides('default', 'light', background.id)
      const dark = createNaiveThemeOverrides('default', 'dark', background.id)

      expect(light.common?.bodyColor).toBe(background.light.page)
      expect(light.common?.cardColor).toBe(background.light.detail)
      expect(light.common?.borderColor).toBe(background.light.borderNormal)
      expect(dark.common?.bodyColor).toBe(background.dark.page)
      expect(dark.common?.cardColor).toBe(background.dark.detail)
      expect(dark.common?.borderColor).toBe(background.dark.borderNormal)
    }
  })

  it('uses the selected palette surfaces when the background follows the theme', () => {
    const amberLight = appearancePalettes.find((palette) => palette.id === 'amber')!.light
    const amberDark = appearancePalettes.find((palette) => palette.id === 'amber')!.dark
    const light = createNaiveThemeOverrides('amber', 'light', 'theme')
    const dark = createNaiveThemeOverrides('amber', 'dark', 'theme')

    expect(light.common?.bodyColor).toBe(amberLight.page)
    expect(light.common?.cardColor).toBe(amberLight.detail)
    expect(dark.common?.bodyColor).toBe(amberDark.page)
    expect(dark.common?.cardColor).toBe(amberDark.detail)
  })

  it('uses contrast-aware foreground text for palette actions', () => {
    expect(createNaiveThemeOverrides('default', 'light').Button?.textColorPrimary).toBe('#FFFFFF')
    expect(createNaiveThemeOverrides('default', 'dark').Button?.textColorPrimary).toBe('#111318')
    expect(createNaiveThemeOverrides('teal', 'light').common?.primaryColor).toBe('#0F766E')
    expect(createNaiveThemeOverrides('teal', 'light').common?.primaryColorHover).toBe('#115E59')
    expect(createNaiveThemeOverrides('teal', 'light').common?.primaryColorPressed).toBe('#134E4A')
  })

  it('uses the basic fallback when no new preference exists', () => {
    expect(getStoredAppearance()).toEqual({ palette: 'default', mode: 'system', background: 'neutral' })
    expect(resolveAppearanceMode('system', true)).toBe('dark')
    expect(resolveAppearanceMode('system', false)).toBe('light')
  })

  it('starts from the basic appearance when only old preference keys exist', () => {
    const oldPreferences = new Map([
      ['workfollow-appearance-palette', 'pink'],
      ['workfollow-appearance-mode', 'dark'],
      ['workfollow-appearance-background', 'warm'],
      ['workfollow-appearance-theme', 'night'],
    ])
    vi.stubGlobal('window', {
      localStorage: {
        getItem: (key: string) => oldPreferences.get(key) ?? null,
      },
    })

    expect(getStoredAppearance()).toEqual({ palette: 'default', mode: 'system', background: 'neutral' })
    vi.unstubAllGlobals()
  })
})
