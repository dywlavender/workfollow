import { defineStore } from 'pinia'

export type FeedbackTone = 'success' | 'error'

export interface FeedbackMessage {
  id: number
  tone: FeedbackTone
  text: string
}

// 反馈规则(全局唯一):成功 2.6s 自动关闭,错误 6s 自动关闭,均可手动关闭;
// 同屏最多 3 条;连续触发相同消息时只重置计时,不重复堆叠。
const SUCCESS_DURATION = 2600
const ERROR_DURATION = 6000
const COMPLETION_DURATION = 2200
const MAX_TOASTS = 3

let nextMessageId = 1
let completionTimer: number | undefined
const messageTimers = new Map<number, number>()

export const useFeedbackStore = defineStore('feedback', {
  state: () => ({
    messages: [] as FeedbackMessage[],
    completionText: '',
  }),
  getters: {
    completionVisible: (state) => state.completionText !== '',
  },
  actions: {
    success(text: string) {
      this.push('success', text)
    },
    error(text: string) {
      this.push('error', text)
    },
    // 完成类反馈:底部居中的仪式感提示,与右上角操作反馈分开。
    completed(text = '任务已完成') {
      this.completionText = text
      window.clearTimeout(completionTimer)
      completionTimer = window.setTimeout(() => {
        this.completionText = ''
      }, COMPLETION_DURATION)
    },
    push(tone: FeedbackTone, text: string) {
      const latest = this.messages[this.messages.length - 1]
      if (latest && latest.tone === tone && latest.text === text) {
        this.restartTimer(latest.id, tone)
        return
      }
      const id = nextMessageId++
      this.messages.push({ id, tone, text })
      if (this.messages.length > MAX_TOASTS) {
        for (const dropped of this.messages.splice(0, this.messages.length - MAX_TOASTS)) {
          this.clearTimer(dropped.id)
        }
      }
      this.restartTimer(id, tone)
    },
    dismiss(id: number) {
      this.clearTimer(id)
      this.messages = this.messages.filter((message) => message.id !== id)
    },
    restartTimer(id: number, tone: FeedbackTone) {
      this.clearTimer(id)
      const timer = window.setTimeout(() => this.dismiss(id), tone === 'error' ? ERROR_DURATION : SUCCESS_DURATION)
      messageTimers.set(id, timer)
    },
    clearTimer(id: number) {
      const timer = messageTimers.get(id)
      if (timer !== undefined) {
        window.clearTimeout(timer)
        messageTimers.delete(id)
      }
    },
  },
})
