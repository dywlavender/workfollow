import type { GlobalThemeOverrides } from 'naive-ui'

export type AppearancePalette =
  | 'default'
  | 'sky'
  | 'teal'
  | 'cyan'
  | 'sage'
  | 'amber'
  | 'pink'
  | 'purple'
  | 'sand'
  | 'navy'
  | 'slate'

export type AppearanceMode = 'system' | 'light' | 'dark'
export type ResolvedAppearanceMode = Exclude<AppearanceMode, 'system'>

export interface AppearancePaletteOption {
  id: AppearancePalette
  label: string
  swatch: string
  primary: string
  primaryHover: string
  primaryPressed: string
  soft: string
  darkSoft: string
  darkPrimary: string
}

const palette = (
  id: AppearancePalette,
  label: string,
  swatch: string,
  primary: string,
  primaryHover: string,
  primaryPressed: string,
  soft: string,
  darkSoft: string,
  darkPrimary: string,
): AppearancePaletteOption => ({ id, label, swatch, primary, primaryHover, primaryPressed, soft, darkSoft, darkPrimary })

export const appearancePalettes: readonly AppearancePaletteOption[] = [
  palette('default', '靛蓝', 'linear-gradient(145deg, #818CF8, #4F46E5)', '#4F46E5', '#4338CA', '#3730A3', '#EEF2FF', '#292752', '#818CF8'),
  palette('sky', '晴蓝', 'linear-gradient(145deg, #60A5FA, #2563EB)', '#2563EB', '#1D4ED8', '#1E40AF', '#EFF6FF', '#1D3154', '#60A5FA'),
  palette('teal', '松石', 'linear-gradient(145deg, #5EEAD4, #0F766E)', '#0F766E', '#115E59', '#134E4A', '#F0FDFA', '#163F3C', '#5EEAD4'),
  palette('cyan', '秘青', 'linear-gradient(145deg, #67E8F9, #0E7490)', '#0E7490', '#155E75', '#164E63', '#ECFEFF', '#173D49', '#67E8F9'),
  palette('sage', '霜荫', 'linear-gradient(145deg, #A3E635, #4D7C0F)', '#4D7C0F', '#3F6212', '#365314', '#F7FEE7', '#2B3B1D', '#A3E635'),
  palette('amber', '杏黄', 'linear-gradient(145deg, #FBBF24, #B45309)', '#B45309', '#92400E', '#78350F', '#FFFBEB', '#49321B', '#FBBF24'),
  palette('pink', '桃夭', 'linear-gradient(145deg, #F9A8D4, #BE185D)', '#BE185D', '#9D174D', '#831843', '#FDF2F8', '#4A2033', '#F9A8D4'),
  palette('purple', '暮山紫', 'linear-gradient(145deg, #C4B5FD, #7E22CE)', '#7E22CE', '#6B21A8', '#581C87', '#FAF5FF', '#39234B', '#C4B5FD'),
  palette('sand', '沉香', 'linear-gradient(145deg, #D6A97C, #92400E)', '#92400E', '#78350F', '#652E0B', '#FFF7ED', '#443021', '#D6A97C'),
  palette('navy', '藏蓝', 'linear-gradient(145deg, #818CF8, #3730A3)', '#3730A3', '#312E81', '#1E1B4B', '#EEF2FF', '#29274D', '#A5B4FC'),
  palette('slate', '石墨', 'linear-gradient(145deg, #94A3B8, #475569)', '#475569', '#334155', '#1E293B', '#F1F5F9', '#303944', '#CBD5E1'),
]

export const appearanceModes: readonly { id: AppearanceMode; label: string; description: string }[] = [
  { id: 'system', label: '跟随系统', description: '自动匹配设备外观' },
  { id: 'light', label: '浅色', description: '始终使用浅色界面' },
  { id: 'dark', label: '深色', description: '始终使用深色界面' },
]

const paletteById = new Map(appearancePalettes.map((option) => [option.id, option]))
const paletteStorageKey = 'workfollow-appearance-palette'
const modeStorageKey = 'workfollow-appearance-mode'
const legacyStorageKey = 'workfollow-appearance-theme'

export function isAppearancePalette(value: string | null): value is AppearancePalette {
  return Boolean(value && paletteById.has(value as AppearancePalette))
}

export function isAppearanceMode(value: string | null): value is AppearanceMode {
  return value === 'system' || value === 'light' || value === 'dark'
}

export function getAppearancePalette(id: AppearancePalette): AppearancePaletteOption {
  return paletteById.get(id) ?? paletteById.get('default')!
}

export function getStoredAppearance(): { palette: AppearancePalette; mode: AppearanceMode } {
  if (typeof window === 'undefined') return { palette: 'default', mode: 'system' }
  try {
    const storedPalette = window.localStorage.getItem(paletteStorageKey)
    const storedMode = window.localStorage.getItem(modeStorageKey)
    if (isAppearancePalette(storedPalette) || isAppearanceMode(storedMode)) {
      return {
        palette: isAppearancePalette(storedPalette) ? storedPalette : 'default',
        mode: isAppearanceMode(storedMode) ? storedMode : 'system',
      }
    }

    const legacy = window.localStorage.getItem(legacyStorageKey)
    if (legacy === 'night') return { palette: 'default', mode: 'dark' }
    if (isAppearancePalette(legacy)) return { palette: legacy, mode: 'light' }
  } catch {
    // Appearance preferences are optional and can fall back safely.
  }
  return { palette: 'default', mode: 'system' }
}

export function persistAppearance(paletteId: AppearancePalette, mode: AppearanceMode) {
  try {
    window.localStorage.setItem(paletteStorageKey, paletteId)
    window.localStorage.setItem(modeStorageKey, mode)
  } catch {
    // Appearance preferences are optional and can fall back safely.
  }
}

export function resolveAppearanceMode(mode: AppearanceMode, systemDark: boolean): ResolvedAppearanceMode {
  return mode === 'system' ? (systemDark ? 'dark' : 'light') : mode
}

function themeVariables(option: AppearancePaletteOption, mode: ResolvedAppearanceMode): Record<string, string> {
  const isDark = mode === 'dark'
  const accent = isDark ? option.darkPrimary : option.primary
  const surfaces = isDark
    ? {
        '--theme-bg-page': '#111318',
        '--theme-bg-sidebar': '#16191F',
        '--theme-bg-panel': '#191C23',
        '--theme-bg-hover': '#222630',
        '--theme-bg-muted': '#1D2028',
        '--theme-text-primary': '#F3F4F6',
        '--theme-text-secondary': '#B3B8C2',
        '--theme-text-tertiary': '#8A919E',
        '--theme-border-light': '#272C35',
        '--theme-border-normal': '#343A46',
        '--theme-code-bg': '#0B0D11',
        '--theme-code-fg': '#F3F4F6',
        '--theme-highlight': '#5B4A14',
      }
    : {
        '--theme-bg-page': '#F7F8FA',
        '--theme-bg-sidebar': '#F1F3F6',
        '--theme-bg-panel': '#FFFFFF',
        '--theme-bg-hover': '#F1F3F6',
        '--theme-bg-muted': '#FAFBFC',
        '--theme-text-primary': '#171A21',
        '--theme-text-secondary': '#5F6672',
        '--theme-text-tertiary': '#6B7280',
        '--theme-border-light': '#EAECF0',
        '--theme-border-normal': '#DDE1E7',
        '--theme-code-bg': '#171A21',
        '--theme-code-fg': '#F9FAFB',
        '--theme-highlight': '#FEF3C7',
      }

  return {
    ...surfaces,
    '--palette-primary': accent,
    '--palette-primary-hover': isDark ? option.darkPrimary : option.primaryHover,
    '--palette-primary-active': isDark ? option.darkPrimary : option.primaryPressed,
    '--palette-primary-soft': isDark ? option.darkSoft : option.soft,
    '--palette-on-primary': isDark ? '#111318' : '#FFFFFF',
  }
}

export function applyAppearance(paletteId: AppearancePalette, mode: ResolvedAppearanceMode) {
  if (typeof document === 'undefined') return
  const root = document.documentElement
  // Remove values written by the pre-token theme system during HMR or migration.
  for (const legacy of [
    '--bg-page', '--bg-sidebar', '--bg-panel', '--bg-hover', '--bg-muted', '--bg-selected',
    '--text-primary', '--text-secondary', '--text-tertiary', '--border-light', '--border-normal',
    '--primary', '--primary-hover', '--primary-dark', '--primary-soft', '--text-on-primary',
    '--sidebar-rail-bg', '--sidebar-rail-text', '--sidebar-rail-hover', '--sidebar-rail-active',
    '--sidebar-rail-active-text', '--sidebar-rail-active-bg', '--sidebar-rail-active-on',
    '--color-bg-page', '--color-bg-surface', '--color-bg-subtle', '--color-text-primary',
    '--color-text-secondary', '--color-border', '--color-accent', '--color-accent-soft',
  ]) root.style.removeProperty(legacy)
  const variables = themeVariables(getAppearancePalette(paletteId), mode)
  for (const [name, value] of Object.entries(variables)) root.style.setProperty(name, value)
  root.dataset.palette = paletteId
  root.dataset.mode = mode
  root.style.colorScheme = mode
}

export function createNaiveThemeOverrides(
  paletteId: AppearancePalette,
  mode: ResolvedAppearanceMode,
): GlobalThemeOverrides {
  const option = getAppearancePalette(paletteId)
  const variables = themeVariables(option, mode)
  const accent = variables['--palette-primary']
  return {
    common: {
      primaryColor: accent,
      primaryColorHover: accent,
      primaryColorPressed: accent,
      primaryColorSuppl: accent,
      bodyColor: variables['--theme-bg-page'],
      cardColor: variables['--theme-bg-panel'],
      modalColor: variables['--theme-bg-panel'],
      popoverColor: variables['--theme-bg-panel'],
      textColorBase: variables['--theme-text-primary'],
      textColor1: variables['--theme-text-primary'],
      textColor2: variables['--theme-text-secondary'],
      textColor3: variables['--theme-text-tertiary'],
      borderColor: variables['--theme-border-normal'],
      dividerColor: variables['--theme-border-light'],
      hoverColor: variables['--theme-bg-hover'],
      inputColor: variables['--theme-bg-panel'],
      actionColor: variables['--theme-bg-muted'],
      borderRadius: '8px',
      borderRadiusSmall: '6px',
      fontFamily: 'var(--type-family-ui)',
      fontSize: 'var(--type-body-size)',
    },
    Button: mode === 'dark' ? {
      textColorPrimary: '#111318',
      textColorHoverPrimary: '#111318',
      textColorPressedPrimary: '#111318',
      textColorFocusPrimary: '#111318',
    } : undefined,
  }
}
