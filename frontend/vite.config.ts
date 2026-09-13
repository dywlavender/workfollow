import { fileURLToPath, URL } from 'node:url'

import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'

export default defineConfig(() => {
  const backendPort = process.env.WORKFOLLOW_BACKEND_PORT ?? '8123'
  const collaborationPort = process.env.WORKFOLLOW_COLLABORATION_PORT ?? '8124'

  return {
    plugins: [vue()],
    // xlsx 只在 excelImport.worker 里使用；不预声明的话，dev 下首次创建
    // Worker 会触发运行时依赖发现 → 重新预优化 → 整页刷新，丢失编辑状态。
    optimizeDeps: {
      include: ['xlsx'],
    },
    build: {
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (id.includes('/node_modules/@tiptap/') || id.includes('/node_modules/@tiptap/pm/') || id.includes('/node_modules/prosemirror-')) return 'tiptap-vendor'
            if (id.includes('/node_modules/naive-ui/')
              || id.includes('/node_modules/vueuc/')
              || id.includes('/node_modules/vooks/')
              || id.includes('/node_modules/vdirs/')
              || id.includes('/node_modules/@css-render/')) return 'naive-ui-vendor'
            if (id.includes('/node_modules/vue/')
              || id.includes('/node_modules/vue-router/')
              || id.includes('/node_modules/pinia/')
              || id.includes('/node_modules/@vue/')) return 'vue-vendor'
            return undefined
          },
        },
      },
    },
    resolve: {
      alias: {
        '@': fileURLToPath(new URL('./src', import.meta.url)),
      },
    },
    server: {
      host: '127.0.0.1',
      port: 5173,
      proxy: {
        '/api': `http://127.0.0.1:${backendPort}`,
        '/collaboration': {
          target: `ws://127.0.0.1:${collaborationPort}`,
          ws: true,
        },
      },
    },
  }
})
