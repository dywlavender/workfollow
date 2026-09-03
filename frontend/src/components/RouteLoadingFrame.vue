<script setup lang="ts">
import type { RouteLoadingKind } from '@/stores/app'

defineProps<{
  kind: RouteLoadingKind
}>()
</script>

<template>
  <div class="route-loading-frame" role="status" aria-live="polite" aria-label="正在打开页面">
    <div class="route-loading-header">
      <span class="route-loading-block route-loading-title" />
      <span class="route-loading-block route-loading-action" />
    </div>

    <div v-if="kind === 'dashboard'" class="route-loading-dashboard">
      <span class="route-loading-block route-loading-panel route-loading-panel-wide" />
      <span class="route-loading-block route-loading-panel route-loading-panel-medium" />
      <span class="route-loading-block route-loading-panel" />
      <span class="route-loading-block route-loading-panel" />
      <span class="route-loading-block route-loading-panel" />
      <span class="route-loading-block route-loading-panel route-loading-panel-wide" />
    </div>

    <div v-else-if="kind === 'workspace'" class="route-loading-workspace">
      <span class="route-loading-block route-loading-navigation" />
      <span class="route-loading-block route-loading-list" />
      <span class="route-loading-block route-loading-detail" />
    </div>

    <div v-else class="route-loading-list-page">
      <span v-for="index in 6" :key="index" class="route-loading-block route-loading-row" />
    </div>
  </div>
</template>

<style>
.route-loading-frame {
  position: absolute;
  inset: 0;
  z-index: var(--layer-local-overlay);
  overflow: hidden;
  padding: var(--space-6) var(--app-page-gutter) var(--app-page-bottom-space);
  background: var(--color-bg-page);
  color: var(--color-text-primary);
  pointer-events: none;
}

.route-loading-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-4);
  min-height: var(--app-header-height);
  margin-bottom: var(--space-5);
}

.route-loading-block {
  display: block;
  border: 1px solid var(--color-border-subtle);
  border-radius: var(--radius-md);
  background: linear-gradient(
    100deg,
    var(--loading-skeleton-from) 25%,
    var(--loading-skeleton-to) 45%,
    var(--loading-skeleton-from) 65%
  );
  background-size: 220% 100%;
  animation: route-loading-shimmer var(--loading-skeleton-duration) var(--loading-skeleton-ease) infinite;
}

/* Route transitions already compete with the page being mounted. In an
   atmosphere theme use a static skeleton instead of repeatedly repainting
   large background gradients; the loading structure remains visible. */
html[data-atmosphere="on"] .route-loading-block {
  animation: none;
  background: var(--loading-skeleton-from);
}

.route-loading-title { width: min(240px, 42%); height: 28px; }
.route-loading-action { width: 104px; height: 36px; }

.route-loading-dashboard {
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  gap: var(--space-4);
}

.route-loading-panel { grid-column: span 4; min-height: 190px; }
.route-loading-panel-wide { grid-column: span 7; min-height: 300px; }
.route-loading-panel-medium { grid-column: span 5; min-height: 300px; }

.route-loading-workspace {
  display: grid;
  grid-template-columns: minmax(180px, 220px) minmax(240px, 300px) minmax(0, 1fr);
  gap: 1px;
  height: calc(100% - var(--app-header-height) - var(--space-5));
  min-height: 420px;
  overflow: hidden;
  border: 1px solid var(--color-border-subtle);
  border-radius: var(--radius-lg);
  background: var(--color-border-subtle);
}

.route-loading-navigation,
.route-loading-list,
.route-loading-detail { min-width: 0; height: 100%; border-radius: var(--radius-none); }

.route-loading-list-page {
  width: min(920px, 100%);
  margin-inline: auto;
  overflow: hidden;
  border: 1px solid var(--color-border-subtle);
  border-radius: var(--radius-lg);
}

.route-loading-row {
  width: 100%;
  height: 72px;
  border-width: 0 0 1px;
  border-radius: var(--radius-none);
}

@keyframes route-loading-shimmer {
  to { background-position: -220% 0; }
}

@media (max-width: 900px) {
  .route-loading-dashboard { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .route-loading-panel,
  .route-loading-panel-wide,
  .route-loading-panel-medium { grid-column: span 1; min-height: 180px; }
  .route-loading-workspace { grid-template-columns: 180px minmax(220px, 1fr); }
  .route-loading-detail { display: none; }
}

@media (prefers-reduced-motion: reduce) {
  .route-loading-block { animation: none; }
}
</style>
