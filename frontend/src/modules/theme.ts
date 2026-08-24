import type { GlobalThemeOverrides } from 'naive-ui'

export type AppearancePalette =
  | 'default'
  | 'sky'
  | 'teal'
  | 'amber'
  | 'purple'
  | 'spring'
  | 'summer'
  | 'autumn'
  | 'winter'

export type AppearanceMode = 'system' | 'light' | 'dark'
export type ResolvedAppearanceMode = Exclude<AppearanceMode, 'system'>
export type AppearanceBackground = 'theme' | 'neutral' | 'mist' | 'warm'

export interface AppearanceSurfaceSet {
  page: string
  rail: string
  navigation: string
  list: string
  detail: string
  input: string
  hover: string
  muted: string
  borderLight: string
  borderNormal: string
}

export interface AppearanceAtmosphere {
  light: string
  dark: string
}

export interface AppearanceScene {
  light: Record<string, string>
  dark: Record<string, string>
}

export interface AppearancePaletteOption {
  id: AppearancePalette
  label: string
  swatch: string
  group?: 'classic' | 'season'
  atmosphere?: AppearanceAtmosphere
  scene?: AppearanceScene
  primary: string
  primaryHover: string
  primaryPressed: string
  soft: string
  darkSoft: string
  darkPrimary: string
  darkPrimaryHover: string
  darkPrimaryPressed: string
  light: AppearanceSurfaceSet
  dark: AppearanceSurfaceSet
}

export interface AppearanceBackgroundOption {
  id: AppearanceBackground
  label: string
  description: string
  swatch: string
  light?: AppearanceSurfaceSet
  dark?: AppearanceSurfaceSet
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
  darkPrimaryHover: string,
  darkPrimaryPressed: string,
  light: AppearanceSurfaceSet,
  dark: AppearanceSurfaceSet,
  extra?: { group?: 'classic' | 'season'; atmosphere?: AppearanceAtmosphere; scene?: AppearanceScene },
): AppearancePaletteOption => ({
  id,
  label,
  swatch,
  primary,
  primaryHover,
  primaryPressed,
  soft,
  darkSoft,
  darkPrimary,
  darkPrimaryHover,
  darkPrimaryPressed,
  light,
  dark,
  ...extra,
})

const surfaces = (
  page: string,
  rail: string,
  navigation: string,
  list: string,
  detail: string,
  input: string,
  hover: string,
  muted: string,
  borderLight: string,
  borderNormal: string,
): AppearanceSurfaceSet => ({
  page,
  rail,
  navigation,
  list,
  detail,
  input,
  hover,
  muted,
  borderLight,
  borderNormal,
})

const scene = (light: Record<string, string>, dark: Record<string, string>): AppearanceScene => ({ light, dark })

export const appearancePalettes: readonly AppearancePaletteOption[] = [
  palette(
    'default',
    '靛蓝',
    'linear-gradient(145deg, #818CF8, #4F46E5)',
    '#4F46E5', '#4338CA', '#3730A3', '#EEF2FF', '#292752', '#818CF8', '#A5B4FC', '#6366F1',
    surfaces('#F7F8FC', '#EEF0FB', '#F2F4FC', '#FFFFFF', '#FEFEFF', '#F8F9FE', '#EEF1FA', '#F9FAFD', '#E4E7F0', '#D8DDE8'),
    surfaces('#111318', '#151725', '#181B29', '#191C23', '#1C2029', '#202430', '#252A38', '#1E222C', '#292F3D', '#384153'),
  ),
  palette(
    'sky',
    '晴蓝',
    'linear-gradient(145deg, #60A5FA, #2563EB)',
    '#2563EB', '#1D4ED8', '#1E40AF', '#EFF6FF', '#1D3154', '#60A5FA', '#93C5FD', '#3B82F6',
    surfaces('#F4F8FD', '#EAF3FC', '#EFF6FC', '#FFFFFF', '#FEFFFF', '#F7FAFE', '#EAF2FC', '#F8FBFE', '#DCE7F2', '#CBD9E7'),
    surfaces('#111923', '#142231', '#172936', '#1A2732', '#1D2C38', '#22333F', '#263C49', '#202F3A', '#2D414D', '#3B5564'),
  ),
  palette(
    'teal',
    '松石',
    'linear-gradient(145deg, #5EEAD4, #0F766E)',
    '#0F766E', '#115E59', '#134E4A', '#F0FDFA', '#163F3C', '#5EEAD4', '#99F6E4', '#2DD4BF',
    surfaces('#F4FAF9', '#E6F5F2', '#EDF8F6', '#FFFFFF', '#FCFEFE', '#F6FBFA', '#E7F5F2', '#F8FCFB', '#D8EAE6', '#C7DDD8'),
    surfaces('#101B1B', '#122523', '#142C2A', '#182926', '#1B302E', '#203A36', '#264541', '#1E3431', '#2A4843', '#3C5D56'),
  ),
  palette(
    'amber',
    '杏黄',
    'linear-gradient(145deg, #FBBF24, #B45309)',
    '#B45309', '#92400E', '#78350F', '#FFFBEB', '#49321B', '#FBBF24', '#FCD34D', '#F59E0B',
    surfaces('#FBF7EF', '#F6E5C4', '#FAF0E0', '#FFFCF8', '#FFFDFC', '#FCF6ED', '#F5E9D7', '#FCF8F1', '#E9DDCD', '#DCCBB8'),
    surfaces('#1B1714', '#261D16', '#2D2119', '#2A231E', '#302721', '#372B21', '#443226', '#32271F', '#4E3C2F', '#624B3A'),
  ),
  palette(
    'purple',
    '暮山紫',
    'linear-gradient(145deg, #C4B5FD, #7E22CE)',
    '#7E22CE', '#6B21A8', '#581C87', '#FAF5FF', '#39234B', '#C4B5FD', '#DDD6FE', '#A78BFA',
    surfaces('#FAF7FE', '#F1EAFE', '#F6F0FC', '#FFFFFF', '#FEFDFF', '#FAF7FE', '#F1EAFB', '#FBF9FD', '#E8DFF1', '#D9CEE4'),
    surfaces('#17131C', '#22192B', '#291E34', '#211A27', '#261F2D', '#30253A', '#3A2B45', '#2C2235', '#493650', '#5E4568'),
  ),
  palette(
    'spring',
    '春 · 樱语',
    'linear-gradient(145deg, #FDA4CA, #DB3F83)',
    '#DB3F83', '#C23377', '#A82A66', '#FCE7F1', '#4A2038', '#FB9EC6', '#FDC6DD', '#F472B6',
    surfaces(
      'rgb(255 241 247 / .68)', 'rgb(255 236 244 / .55)', 'rgb(255 238 246 / .6)',
      'rgb(255 250 252 / .86)', 'rgb(255 252 253 / .9)', 'rgb(255 247 250 / .85)',
      'rgb(219 63 131 / .08)', 'rgb(255 244 249 / .8)', 'rgb(219 63 131 / .14)', 'rgb(219 63 131 / .22)',
    ),
    surfaces(
      'rgb(23 12 19 / .72)', 'rgb(28 15 24 / .6)', 'rgb(26 14 22 / .64)',
      'rgb(30 17 26 / .88)', 'rgb(33 19 29 / .92)', 'rgb(36 21 32 / .88)',
      'rgb(251 158 198 / .1)', 'rgb(32 18 28 / .85)', 'rgb(251 158 198 / .12)', 'rgb(251 158 198 / .2)',
    ),
    {
      group: 'season',
      atmosphere: {
        light: [
          'radial-gradient(1100px 720px at 12% -8%, rgb(255 214 232 / .9), transparent 60%)',
          'radial-gradient(900px 640px at 88% 18%, rgb(248 180 213 / .55), transparent 62%)',
          'radial-gradient(1000px 800px at 70% 108%, rgb(255 190 216 / .5), transparent 64%)',
          'linear-gradient(168deg, #FFF3F8 0%, #FFE4F0 46%, #FFD9EA 100%)',
        ].join(', '),
        dark: [
          'radial-gradient(1100px 720px at 14% -10%, rgb(120 38 84 / .5), transparent 60%)',
          'radial-gradient(820px 560px at 86% 24%, rgb(219 63 131 / .28), transparent 62%)',
          'radial-gradient(900px 700px at 24% 110%, rgb(90 26 66 / .5), transparent 64%)',
          'linear-gradient(168deg, #241220 0%, #190C15 52%, #120710 100%)',
        ].join(', '),
      },
      scene: scene(
        {
          hillA: '#b2dca6', hillB: '#93c98e', trunk: '#7a5546', blossom1: '#ffb0d2', blossom2: '#f787ba', blossom3: '#ffd1e3', bird: '#8a5a72',
          particle1: '#f472a8', particle2: '#ec5f97', particle3: '#f9a8c9', auroraA: '#f472b6', auroraB: '#67e8f9',
        },
        {
          hillA: '#2e3d3a', hillB: '#243230', trunk: '#503a4a', blossom1: '#c76a9d', blossom2: '#a84d80', blossom3: '#e39cc2', bird: '#b08aa0',
          particle1: '#f472b6', particle2: '#db3f83', particle3: '#f9a8c9', auroraA: '#f472b6', auroraB: '#67e8f9',
        },
      ),
    },
  ),
  palette(
    'summer',
    '夏 · 青屿',
    'linear-gradient(145deg, #67E8F9, #0284C7)',
    '#0288C0', '#0273A3', '#025E85', '#E0F2FE', '#123B4F', '#67E8F9', '#A5F3FC', '#22D3EE',
    surfaces(
      'rgb(238 249 253 / .66)', 'rgb(230 246 252 / .55)', 'rgb(234 248 253 / .6)',
      'rgb(250 253 255 / .86)', 'rgb(252 254 255 / .9)', 'rgb(245 251 254 / .85)',
      'rgb(2 136 192 / .08)', 'rgb(243 250 253 / .8)', 'rgb(2 136 192 / .13)', 'rgb(2 136 192 / .2)',
    ),
    surfaces(
      'rgb(8 20 31 / .72)', 'rgb(10 25 38 / .6)', 'rgb(9 23 36 / .64)',
      'rgb(11 28 42 / .88)', 'rgb(13 31 46 / .92)', 'rgb(14 34 50 / .88)',
      'rgb(103 232 249 / .1)', 'rgb(12 29 43 / .85)', 'rgb(103 232 249 / .11)', 'rgb(103 232 249 / .18)',
    ),
    {
      group: 'season',
      atmosphere: {
        light: [
          'radial-gradient(1000px 640px at 18% 12%, rgb(255 255 255 / .85), rgb(186 230 253 / .4) 46%, transparent 68%)',
          'radial-gradient(1200px 760px at 84% 96%, rgb(56 189 248 / .4), transparent 62%)',
          'linear-gradient(176deg, #CFF0FC 0%, #A8E2F8 48%, #8AD6F4 100%)',
        ].join(', '),
        dark: [
          'radial-gradient(900px 600px at 20% 8%, rgb(125 211 252 / .16), transparent 60%)',
          'radial-gradient(1100px 720px at 82% 104%, rgb(8 145 178 / .42), transparent 62%)',
          'linear-gradient(176deg, #0D2136 0%, #091A2B 52%, #061220 100%)',
        ].join(', '),
      },
      scene: scene(
        {
          seaTop: '#5fc2e8', seaBottom: '#2f9fd8', foam: 'rgb(255 255 255 / .8)', island: '#4db3d6', sail: '#ffffff', hull: '#e8734a', sunRing: 'rgb(255 255 255 / .6)',
          auroraA: '#67e8f9', auroraB: '#ffffff',
        },
        {
          seaTop: '#0d2c44', seaBottom: '#081e30', foam: 'rgb(125 211 252 / .3)', island: '#123248', sail: '#d8e8f2', hull: '#7a4a3a', sunRing: 'rgb(191 219 254 / .25)',
          auroraA: '#67e8f9', auroraB: '#0ea5e9',
        },
      ),
    },
  ),
  palette(
    'autumn',
    '秋 · 柿染',
    'linear-gradient(145deg, #FDBA74, #C2410C)',
    '#C6520F', '#A8450B', '#8A3809', '#FFEDD5', '#46250F', '#FBB36A', '#FDCAA0', '#F59E0B',
    surfaces(
      'rgb(253 246 235 / .66)', 'rgb(251 241 226 / .55)', 'rgb(252 243 229 / .6)',
      'rgb(255 252 247 / .87)', 'rgb(255 253 250 / .9)', 'rgb(254 249 241 / .85)',
      'rgb(198 82 15 / .08)', 'rgb(253 247 237 / .8)', 'rgb(198 82 15 / .14)', 'rgb(198 82 15 / .21)',
    ),
    surfaces(
      'rgb(23 14 8 / .72)', 'rgb(29 18 10 / .6)', 'rgb(27 16 9 / .64)',
      'rgb(32 20 11 / .88)', 'rgb(35 22 13 / .92)', 'rgb(38 24 14 / .88)',
      'rgb(251 146 60 / .1)', 'rgb(33 21 12 / .85)', 'rgb(251 146 60 / .12)', 'rgb(251 146 60 / .19)',
    ),
    {
      group: 'season',
      atmosphere: {
        light: [
          'radial-gradient(1000px 680px at 84% 38%, rgb(253 186 116 / .6), rgb(249 115 22 / .22) 48%, transparent 70%)',
          'radial-gradient(900px 620px at 12% 100%, rgb(224 145 63 / .35), transparent 64%)',
          'linear-gradient(170deg, #FDEECD 0%, #FBDFAC 50%, #F7D093 100%)',
        ].join(', '),
        dark: [
          'radial-gradient(960px 640px at 84% 40%, rgb(217 72 15 / .4), transparent 62%)',
          'radial-gradient(860px 600px at 14% 106%, rgb(180 83 9 / .32), transparent 64%)',
          'linear-gradient(170deg, #241509 0%, #1A0F07 52%, #120905 100%)',
        ].join(', '),
      },
      scene: scene(
        {
          backHill: '#d19a6a', midHill: '#b0713a', field: '#e0b06a', row: '#c08c47', tree1: '#d96b2a', tree2: '#c2410c', tree3: '#e0913f', trunk: '#6b4423',
          particle1: '#d96a2a', particle2: '#c2410c', particle3: '#e0913f', auroraA: '#fb923c', auroraB: '#facc15',
        },
        {
          backHill: '#4a2c1c', midHill: '#38200f', field: '#59331b', row: '#462612', tree1: '#b45309', tree2: '#92400e', tree3: '#c2711c', trunk: '#3a2513',
          particle1: '#b45309', particle2: '#92400e', particle3: '#c2711c', auroraA: '#f97316', auroraB: '#f59e0b',
        },
      ),
    },
  ),
  palette(
    'winter',
    '冬 · 霜松',
    'linear-gradient(145deg, #BFDBFE, #3567A8)',
    '#3567A8', '#2C578E', '#244774', '#E8F0FB', '#1B2C45', '#93C5FD', '#BFDCFE', '#60A5FA',
    surfaces(
      'rgb(240 246 252 / .66)', 'rgb(233 242 250 / .55)', 'rgb(236 244 251 / .6)',
      'rgb(251 253 255 / .86)', 'rgb(253 254 255 / .9)', 'rgb(246 250 254 / .85)',
      'rgb(53 103 168 / .08)', 'rgb(244 249 253 / .8)', 'rgb(53 103 168 / .13)', 'rgb(53 103 168 / .2)',
    ),
    surfaces(
      'rgb(9 14 24 / .72)', 'rgb(12 19 32 / .6)', 'rgb(11 17 29 / .64)',
      'rgb(14 21 36 / .88)', 'rgb(16 24 40 / .92)', 'rgb(18 27 44 / .88)',
      'rgb(147 197 253 / .1)', 'rgb(15 23 38 / .85)', 'rgb(147 197 253 / .11)', 'rgb(147 197 253 / .18)',
    ),
    {
      group: 'season',
      atmosphere: {
        light: [
          'radial-gradient(1100px 700px at 92% -6%, rgb(255 255 255 / .95), transparent 58%)',
          'radial-gradient(900px 600px at 8% 104%, rgb(191 219 254 / .5), transparent 62%)',
          'linear-gradient(172deg, #E2EEFB 0%, #CCE0F6 50%, #B7D3F0 100%)',
        ].join(', '),
        dark: [
          'radial-gradient(760px 520px at 78% 18%, rgb(191 219 254 / .16), transparent 60%)',
          'radial-gradient(1000px 640px at 12% 108%, rgb(53 103 168 / .4), transparent 62%)',
          'linear-gradient(172deg, #0D1730 0%, #0A1222 52%, #060B16 100%)',
        ].join(', '),
      },
      scene: scene(
        {
          backMountain: '#a9c4e2', cap: '#f4faff', midMountain: '#7fa8d0', snowField: '#eaf3fc', shade: '#c2d9ef', pine: '#3e6b63', pineCap: '#ffffff', trunk: '#4a3a30', moonOpacity: '0', starsOpacity: '0', moonFill: '#f1f5f9', moonHalo: 'rgb(191 219 254 / .18)',
          particle1: '#ffffff', particle2: '#dbeafe', particle3: '#eff6ff', auroraA: '#f472b6', auroraB: '#67e8f9',
        },
        {
          backMountain: '#22334d', cap: '#9db8d8', midMountain: '#182741', snowField: '#0f1c30', shade: '#16273f', pine: '#16302e', pineCap: '#9db8d8', trunk: '#0c1a20', moonOpacity: '1', starsOpacity: '1', moonFill: '#f1f5f9', moonHalo: 'rgb(191 219 254 / .18)',
          particle1: '#ffffff', particle2: '#dbeafe', particle3: '#eff6ff', auroraA: '#f472b6', auroraB: '#67e8f9',
        },
      ),
    },
  ),
]

export const appearanceModes: readonly { id: AppearanceMode; label: string; description: string }[] = [
  { id: 'system', label: '跟随系统', description: '自动匹配设备外观' },
  { id: 'light', label: '浅色', description: '始终使用浅色界面' },
  { id: 'dark', label: '深色', description: '始终使用深色界面' },
]

const background = (
  id: AppearanceBackground,
  label: string,
  description: string,
  swatch: string,
  light?: AppearanceSurfaceSet,
  dark?: AppearanceSurfaceSet,
): AppearanceBackgroundOption => ({ id, label, description, swatch, light, dark })

export const appearanceBackgrounds: readonly AppearanceBackgroundOption[] = [
  background(
    'theme',
    '随主题配色',
    '跟随当前主色的区域背景和交互状态',
    'linear-gradient(145deg, #FDE68A, #E0E7FF)',
  ),
  background(
    'neutral',
    '中性',
    '保持干净的灰白层次',
    'linear-gradient(145deg, #ffffff, #e9edf3)',
    surfaces('#F7F8FA', '#F1F3F6', '#F3F5F8', '#FFFFFF', '#FFFFFF', '#FAFBFC', '#F1F3F6', '#FAFBFC', '#EAECF0', '#DDE1E7'),
    surfaces('#111318', '#16191F', '#181B22', '#191C23', '#1C2027', '#20232B', '#222630', '#1D2028', '#272C35', '#343A46'),
  ),
  background(
    'mist',
    '雾蓝',
    '带一点冷色的工作台背景',
    'linear-gradient(145deg, #ffffff, #dce8f4)',
    surfaces('#F4F7FB', '#EAF0F7', '#EEF4FA', '#FFFFFF', '#FEFFFF', '#F8FAFC', '#EAF0F7', '#F8FAFC', '#DCE5EF', '#CCD8E5'),
    surfaces('#111923', '#17212D', '#1A2530', '#1B2632', '#1E2A36', '#222F3B', '#253341', '#202D3A', '#2B3B4B', '#3A4C5E'),
  ),
  background(
    'warm',
    '暖沙',
    '更柔和的米灰色工作台背景',
    'linear-gradient(145deg, #fffdfb, #eadfd3)',
    surfaces('#FAF7F2', '#F3EEE7', '#F7F0E8', '#FFFEFC', '#FFFDFC', '#FBF8F4', '#F1ECE5', '#FBF8F4', '#E8DFD4', '#DCCFC1'),
    surfaces('#1B1714', '#241E19', '#2A211B', '#2A231E', '#2E261F', '#332A23', '#352B24', '#302721', '#44372E', '#59483B'),
  ),
]

const paletteById = new Map(appearancePalettes.map((option) => [option.id, option]))
const backgroundById = new Map(appearanceBackgrounds.map((option) => [option.id, option]))
// This release intentionally starts a clean appearance preference namespace.
// Old palette/background preferences are ignored rather than migrated.
const paletteStorageKey = 'workfollow-appearance-v2-palette'
const modeStorageKey = 'workfollow-appearance-v2-mode'
const backgroundStorageKey = 'workfollow-appearance-v2-background'

export function isAppearancePalette(value: string | null): value is AppearancePalette {
  return Boolean(value && paletteById.has(value as AppearancePalette))
}

export function isAppearanceMode(value: string | null): value is AppearanceMode {
  return value === 'system' || value === 'light' || value === 'dark'
}

export function isAppearanceBackground(value: string | null): value is AppearanceBackground {
  return Boolean(value && backgroundById.has(value as AppearanceBackground))
}

export function getAppearancePalette(id: AppearancePalette): AppearancePaletteOption {
  return paletteById.get(id) ?? paletteById.get('default')!
}

export function getAppearanceBackground(id: AppearanceBackground): AppearanceBackgroundOption {
  return backgroundById.get(id) ?? backgroundById.get('neutral')!
}

export function getStoredAppearance(): {
  palette: AppearancePalette
  mode: AppearanceMode
  background: AppearanceBackground
} {
  if (typeof window === 'undefined') return { palette: 'default', mode: 'system', background: 'neutral' }
  try {
    const storedPalette = window.localStorage.getItem(paletteStorageKey)
    const storedMode = window.localStorage.getItem(modeStorageKey)
    const storedBackground = window.localStorage.getItem(backgroundStorageKey)
    if (isAppearancePalette(storedPalette) || isAppearanceMode(storedMode) || isAppearanceBackground(storedBackground)) {
      return {
        palette: isAppearancePalette(storedPalette) ? storedPalette : 'default',
        mode: isAppearanceMode(storedMode) ? storedMode : 'system',
        background: isAppearanceBackground(storedBackground) ? storedBackground : 'neutral',
      }
    }
  } catch {
    // Appearance preferences are optional and can fall back safely.
  }
  return { palette: 'default', mode: 'system', background: 'neutral' }
}

export function persistAppearance(
  paletteId: AppearancePalette,
  mode: AppearanceMode,
  backgroundId: AppearanceBackground,
) {
  try {
    window.localStorage.setItem(paletteStorageKey, paletteId)
    window.localStorage.setItem(modeStorageKey, mode)
    window.localStorage.setItem(backgroundStorageKey, backgroundId)
  } catch {
    // Appearance preferences are optional and can fall back safely.
  }
}

export function resolveAppearanceMode(mode: AppearanceMode, systemDark: boolean): ResolvedAppearanceMode {
  return mode === 'system' ? (systemDark ? 'dark' : 'light') : mode
}

function getContrastTextColor(color: string): string {
  const normalized = color.replace('#', '')
  const value = normalized.length === 3
    ? normalized.split('').map((channel) => `${channel}${channel}`).join('')
    : normalized
  if (!/^[0-9a-f]{6}$/i.test(value)) return '#FFFFFF'
  const channels = [0, 2, 4].map((offset) => Number.parseInt(value.slice(offset, offset + 2), 16) / 255)
  const linear = channels.map((channel) => channel <= 0.03928
    ? channel / 12.92
    : ((channel + 0.055) / 1.055) ** 2.4)
  const luminance = linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
  const lightContrast = 1.05 / (luminance + 0.05)
  const darkContrast = (luminance + 0.05) / 0.058
  return darkContrast >= lightContrast ? '#111318' : '#FFFFFF'
}

function themeVariables(
  option: AppearancePaletteOption,
  mode: ResolvedAppearanceMode,
  backgroundId: AppearanceBackground,
): Record<string, string> {
  const isDark = mode === 'dark'
  const accent = isDark ? option.darkPrimary : option.primary
  const selectedBackground = getAppearanceBackground(backgroundId)
  const surfaceSet = backgroundId === 'theme'
    ? (isDark ? option.dark : option.light)
    : (isDark ? selectedBackground.dark : selectedBackground.light) ?? (isDark ? option.dark : option.light)
  const primaryHover = isDark ? option.darkPrimaryHover : option.primaryHover
  const primaryActive = isDark ? option.darkPrimaryPressed : option.primaryPressed
  const primarySoft = isDark ? option.darkSoft : option.soft
  const sceneTokens = option.scene
    ? Object.fromEntries(Object.entries(isDark ? option.scene.dark : option.scene.light).map(([name, value]) => [`--season-${name}`, value]))
    : {}
  const surfaces = {
    '--theme-bg-page': surfaceSet.page,
    '--theme-bg-rail': surfaceSet.rail,
    '--theme-bg-navigation': surfaceSet.navigation,
    '--theme-bg-list': surfaceSet.list,
    '--theme-bg-detail': surfaceSet.detail,
    '--theme-bg-input': surfaceSet.input,
    // Compatibility aliases for older component rules.
    '--theme-bg-sidebar': surfaceSet.navigation,
    '--theme-bg-panel': surfaceSet.detail,
    '--theme-bg-hover': surfaceSet.hover,
    '--theme-bg-muted': surfaceSet.muted,
    '--theme-bg-selected': primarySoft,
    '--theme-text-primary': isDark ? '#F3F4F6' : '#171A21',
    '--theme-text-secondary': isDark ? '#B3B8C2' : '#5F6672',
    '--theme-text-tertiary': isDark ? '#8A919E' : '#6B7280',
    '--theme-border-light': surfaceSet.borderLight,
    '--theme-border-normal': surfaceSet.borderNormal,
    '--theme-code-bg': isDark ? '#0B0D11' : '#171A21',
    '--theme-code-fg': isDark ? '#F3F4F6' : '#F9FAFB',
    '--theme-highlight': isDark ? '#5B4A14' : '#FEF3C7',
  }

  return {
    ...surfaces,
    ...sceneTokens,
    '--theme-atmosphere': isDark
      ? option.atmosphere?.dark ?? 'none'
      : option.atmosphere?.light ?? 'none',
    '--palette-primary': accent,
    '--palette-primary-hover': primaryHover,
    '--palette-primary-active': primaryActive,
    '--palette-primary-soft': primarySoft,
    '--palette-primary-soft-hover': `color-mix(in srgb, ${primarySoft} 84%, ${accent})`,
    '--palette-focus-ring': `color-mix(in srgb, ${accent} 20%, transparent)`,
    '--palette-on-primary': getContrastTextColor(accent),
  }
}

export function applyAppearance(
  paletteId: AppearancePalette,
  mode: ResolvedAppearanceMode,
  backgroundId: AppearanceBackground = 'neutral',
) {
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
  const variables = themeVariables(getAppearancePalette(paletteId), mode, backgroundId)
  for (const [name, value] of Object.entries(variables)) root.style.setProperty(name, value)
  root.dataset.palette = paletteId
  root.dataset.mode = mode
  root.dataset.background = backgroundId
  root.dataset.atmosphere = getAppearancePalette(paletteId).atmosphere ? 'on' : 'off'
  root.style.colorScheme = mode
}

export function createNaiveThemeOverrides(
  paletteId: AppearancePalette,
  mode: ResolvedAppearanceMode,
  backgroundId: AppearanceBackground = 'neutral',
): GlobalThemeOverrides {
  const option = getAppearancePalette(paletteId)
  const variables = themeVariables(option, mode, backgroundId)
  const accent = variables['--palette-primary']
  return {
    common: {
      primaryColor: accent,
      primaryColorHover: variables['--palette-primary-hover'],
      primaryColorPressed: variables['--palette-primary-active'],
      primaryColorSuppl: variables['--palette-primary-soft'],
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
      inputColor: variables['--theme-bg-input'],
      actionColor: variables['--theme-bg-muted'],
      borderRadius: '8px',
      borderRadiusSmall: '6px',
      fontFamily: 'var(--type-family-ui)',
      fontSize: 'var(--type-body-size)',
    },
    Button: {
      textColorPrimary: variables['--palette-on-primary'],
      textColorHoverPrimary: variables['--palette-on-primary'],
      textColorPressedPrimary: variables['--palette-on-primary'],
      textColorFocusPrimary: variables['--palette-on-primary'],
    },
  }
}
