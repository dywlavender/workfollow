import { defineStore } from 'pinia'

import {
  applyAppearance,
  getStoredAppearance,
  persistAppearance,
  resolveAppearanceMode,
  type AppearanceMode,
  type AppearanceBackground,
  type AppearancePalette,
} from '@/modules/theme'
import { fetchHealth, type HealthResponse } from '@/services/api'

type ApiState = 'idle' | 'loading' | 'ready' | 'error'
let completionToastTimer: number | undefined
let appearanceMedia: MediaQueryList | undefined
let appearanceListener: ((event: MediaQueryListEvent) => void) | undefined
const storedAppearance = getStoredAppearance()

export const useAppStore = defineStore('app', {
  state: () => ({
    apiState: 'idle' as ApiState,
    health: null as HealthResponse | null,
    appearancePalette: storedAppearance.palette as AppearancePalette,
    appearanceMode: storedAppearance.mode as AppearanceMode,
    appearanceBackground: storedAppearance.background as AppearanceBackground,
    systemDark: false,
    completionToastVisible: false,
  }),
  actions: {
    initializeAppearance() {
      if (typeof window !== 'undefined') {
        appearanceMedia = window.matchMedia('(prefers-color-scheme: dark)')
        this.systemDark = appearanceMedia.matches
        if (!appearanceListener) {
          appearanceListener = (event) => {
            this.systemDark = event.matches
            this.applyAppearance()
          }
          appearanceMedia.addEventListener('change', appearanceListener)
        }
      }
      this.applyAppearance()
    },
    applyAppearance() {
      applyAppearance(
        this.appearancePalette,
        resolveAppearanceMode(this.appearanceMode, this.systemDark),
        this.appearanceBackground,
      )
    },
    setAppearancePalette(palette: AppearancePalette) {
      this.appearancePalette = palette
      this.applyAppearance()
      persistAppearance(this.appearancePalette, this.appearanceMode, this.appearanceBackground)
    },
    setAppearanceMode(mode: AppearanceMode) {
      this.appearanceMode = mode
      this.applyAppearance()
      persistAppearance(this.appearancePalette, this.appearanceMode, this.appearanceBackground)
    },
    setAppearanceBackground(background: AppearanceBackground) {
      this.appearanceBackground = background
      this.applyAppearance()
      persistAppearance(this.appearancePalette, this.appearanceMode, this.appearanceBackground)
    },
    showCompletionToast() {
      this.completionToastVisible = true
      window.clearTimeout(completionToastTimer)
      completionToastTimer = window.setTimeout(() => {
        this.completionToastVisible = false
      }, 2200)
    },
    async checkApi() {
      this.apiState = 'loading'
      try {
        this.health = await fetchHealth()
        this.apiState = 'ready'
      } catch {
        this.health = null
        this.apiState = 'error'
      }
    },
  },
})
