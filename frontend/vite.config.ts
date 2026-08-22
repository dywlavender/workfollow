import { fileURLToPath, URL } from 'node:url'

import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'

export default defineConfig(() => {
  const backendPort = process.env.WORKFOLLOW_BACKEND_PORT ?? '8123'

  return {
    plugins: [vue()],
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
      },
    },
  }
})
