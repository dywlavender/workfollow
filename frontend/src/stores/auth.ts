import { defineStore } from 'pinia'

import { fetchCurrentUser, login, logout, register, updateCurrentUser, type User } from '@/services/api'
import { useTodoStore } from '@/stores/todos'
import { useWorkspaceStore } from '@/stores/workspace'

function clearAccountScopedState() {
  useTodoStore().reset()
  useWorkspaceStore().reset()
}

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null as User | null,
    initialized: false,
    loading: false,
  }),
  actions: {
    async initialize() {
      if (this.initialized) return this.user
      try {
        this.user = await fetchCurrentUser()
      } catch {
        this.user = null
      } finally {
        this.initialized = true
      }
      return this.user
    },
    async signIn(identifier: string, password: string) {
      this.loading = true
      try {
        clearAccountScopedState()
        const result = await login(identifier, password)
        this.user = result.user
        this.initialized = true
        return result
      } finally {
        this.loading = false
      }
    },
    async signUp(payload: { username: string; password: string }) {
      this.loading = true
      try {
        clearAccountScopedState()
        const result = await register(payload)
        this.user = result.user
        this.initialized = true
        return result
      } finally {
        this.loading = false
      }
    },
    async updateProfile(payload: { nickname: string }) {
      const updated = await updateCurrentUser(payload)
      this.user = updated
      return updated
    },
    async signOut() {
      try {
        await logout()
      } finally {
        this.user = null
        this.initialized = true
        clearAccountScopedState()
      }
    },
  },
})
