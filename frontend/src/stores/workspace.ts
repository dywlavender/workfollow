import { defineStore } from 'pinia'

import { fetchTeams, type Team } from '@/services/api'

const STORAGE_KEY = 'workfollow.workspace'

export const useWorkspaceStore = defineStore('workspace', {
  state: () => ({
    teams: [] as Team[],
    initialized: false,
    currentTeamId: null as string | null,
    kind: 'PERSONAL' as 'PERSONAL' | 'TEAM',
  }),
  getters: {
    currentTeam: (state) => state.teams.find((team) => team.id === state.currentTeamId) ?? null,
  },
  actions: {
    async initialize() {
      if (this.initialized) return this.teams
      try {
        this.teams = await fetchTeams()
        const saved = window.localStorage.getItem(STORAGE_KEY)
        if (saved && this.teams.some((team) => team.id === saved)) {
          this.currentTeamId = saved
          this.kind = 'TEAM'
        } else if (this.teams[0]) {
          this.selectTeam(this.teams[0].id)
        }
      } catch {
        this.teams = []
        this.selectPersonal()
      } finally {
        this.initialized = true
      }
      return this.teams
    },
    selectPersonal() {
      this.kind = 'PERSONAL'
      this.currentTeamId = null
      window.localStorage.removeItem(STORAGE_KEY)
    },
    selectTeam(teamId: string) {
      if (!this.teams.some((team) => team.id === teamId)) return
      this.kind = 'TEAM'
      this.currentTeamId = teamId
      window.localStorage.setItem(STORAGE_KEY, teamId)
    },
    addTeam(team: Team) {
      this.teams = [team, ...this.teams.filter((item) => item.id !== team.id)]
      this.selectTeam(team.id)
    },
    removeTeam(teamId: string) {
      this.teams = this.teams.filter((team) => team.id !== teamId)
      if (this.currentTeamId !== teamId) return
      if (this.teams[0]) this.selectTeam(this.teams[0].id)
      else this.selectPersonal()
    },
    reset() {
      this.teams = []
      this.initialized = false
      this.selectPersonal()
    },
  },
})
