<script setup lang="ts">
import { IconBook, IconFileText, IconUsers } from '@tabler/icons-vue'

import type { SearchItem } from '@/services/api'

defineProps<{
  items: SearchItem[]
  query: string
  loading?: boolean
}>()

const emit = defineEmits<{ select: [item: SearchItem] }>()

const sourceLabel: Record<SearchItem['source'], string> = {
  personal: '个人笔记',
  shared: '分享给我的',
  knowledge: '团队知识库',
}
</script>

<template>
  <section class="search-results-panel" aria-live="polite">
    <header class="search-results-header"><strong>搜索结果</strong><span v-if="loading">搜索中…</span><span v-else-if="query.trim()">{{ items.length ? `${items.length} 条` : '没有找到匹配内容' }}</span><span v-else>输入关键词</span></header>
    <div v-if="items.length" class="search-results-list">
      <button v-for="item in items" :key="`${item.source}-${item.id}`" type="button" class="search-result-item" @click="emit('select', item)">
        <span class="search-result-icon"><IconFileText v-if="item.source === 'personal'" :size="16" /><IconUsers v-else-if="item.source === 'shared'" :size="16" /><IconBook v-else :size="16" /></span>
        <span class="search-result-copy">
          <strong>{{ item.title }}</strong>
          <span class="search-result-excerpt"><template v-for="(part, index) in item.excerpt" :key="`${index}-${part.text}`"><mark v-if="part.matched">{{ part.text }}</mark><span v-else>{{ part.text }}</span></template></span>
          <small>{{ sourceLabel[item.source] }} · {{ new Date(item.updatedAt).toLocaleDateString('zh-CN') }}</small>
        </span>
      </button>
    </div>
    <p v-else-if="!loading && query.trim()" class="search-results-empty">没有找到“{{ query }}”，可以换一个关键词，或先用“随手记”保存想法。</p>
    <p v-else-if="!loading" class="search-results-empty">输入标题、正文或标签开始搜索。</p>
  </section>
</template>
