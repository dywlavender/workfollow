import { createPinia } from 'pinia'
import { createApp } from 'vue'

import App from './App.vue'
import router from './router'
import './design-tokens.css'
import './styles.css'
import './redesign.css'
import './layout.css'

const pinia = createPinia()
createApp(App).use(pinia).use(router).mount('#app')
