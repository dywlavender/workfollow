<script setup lang="ts">
import { computed } from 'vue'
import { getAppearancePalette, type AppearancePalette } from '@/modules/theme'

const props = defineProps<{ season: string }>()

// 迷你场景的形状与配色取自对应季节的氛围场景层(浅色值),
// 颜色统一来自 theme.ts 的场景定义,底色由外层色板的天空渐变提供。
const c = computed(() => getAppearancePalette(props.season as AppearancePalette).scene?.light ?? {})
</script>

<template>
  <svg
    v-if="season === 'spring'"
    viewBox="0 0 76 76"
    preserveAspectRatio="xMidYMax slice"
    aria-hidden="true"
  >
    <path :fill="c.hillA" d="M0 54 Q19 45 38 51 T76 48 V76 H0 Z" />
    <path :fill="c.hillB" d="M0 63 Q25 56 46 61 T76 60 V76 H0 Z" />
    <g transform="translate(38 29) scale(.3)">
      <path :fill="c.trunk" d="M-7 130 C-5 84 -9 52 -16 22 L-4 30 C-2 60 2 92 7 130 Z" />
      <circle cx="-38" cy="10" r="34" :fill="c.blossom2" />
      <circle cx="14" cy="-18" r="42" :fill="c.blossom1" />
      <circle cx="58" cy="18" r="30" :fill="c.blossom2" />
      <circle cx="-8" cy="26" r="40" :fill="c.blossom3" />
      <circle cx="36" cy="44" r="24" :fill="c.blossom1" />
    </g>
  </svg>

  <svg
    v-else-if="season === 'summer'"
    viewBox="0 0 76 76"
    preserveAspectRatio="xMidYMax slice"
    aria-hidden="true"
  >
    <circle cx="54" cy="18" r="11" :fill="c.sunRing" opacity=".55" />
    <rect y="32" width="76" height="44" :fill="c.seaTop" />
    <path :fill="c.seaBottom" d="M0 42 Q19 38 38 41 T76 40 V76 H0 Z" />
    <path :fill="c.island" d="M10 32 C15 22 25 20 31 32 Z" />
    <g transform="translate(46 50) scale(.5)">
      <path :fill="c.sail" d="M0 -44 L0 6 L-30 6 Z" />
      <path :fill="c.sail" d="M6 -34 L6 6 L30 6 Z" opacity=".82" />
      <path :fill="c.hull" d="M-36 10 L36 10 L24 26 L-24 26 Z" />
    </g>
    <g :stroke="c.foam" stroke-width="2.5" stroke-linecap="round">
      <path d="M14 64 h9" /><path d="M40 68 h8" /><path d="M60 62 h7" />
    </g>
  </svg>

  <svg
    v-else-if="season === 'autumn'"
    viewBox="0 0 76 76"
    preserveAspectRatio="xMidYMax slice"
    aria-hidden="true"
  >
    <path :fill="c.backHill" d="M0 42 Q19 30 38 37 T76 34 V76 H0 Z" />
    <path :fill="c.midHill" d="M0 52 Q19 44 38 49 T76 47 V76 H0 Z" />
    <rect y="58" width="76" height="18" :fill="c.field" />
    <g :stroke="c.row" stroke-width="2.5" stroke-linecap="round">
      <path d="M6 76 L22 61" /><path d="M32 76 L42 62" /><path d="M56 76 L60 63" />
    </g>
    <g transform="translate(38 30) scale(.3)">
      <path :fill="c.trunk" d="M-6 90 C-4 58 -8 34 -13 14 L-3 20 C0 46 3 68 6 90 Z" />
      <circle cx="-26" cy="-2" r="26" :fill="c.tree2" />
      <circle cx="12" cy="-20" r="32" :fill="c.tree1" />
      <circle cx="40" cy="6" r="22" :fill="c.tree3" />
      <circle cx="2" cy="14" r="24" :fill="c.tree1" />
    </g>
  </svg>

  <svg
    v-else-if="season === 'winter'"
    viewBox="0 0 76 76"
    preserveAspectRatio="xMidYMax slice"
    aria-hidden="true"
  >
    <path :fill="c.backMountain" d="M2 56 L26 24 L50 56 Z" />
    <path :fill="c.cap" d="M26 24 L18 33 L22 31 L26 35 L30 31 L34 33 Z" />
    <path :fill="c.midMountain" d="M38 56 L58 32 L76 56 Z" />
    <path :fill="c.cap" d="M58 32 L51 40 L54 38 L58 42 L62 38 L64 40 Z" opacity=".85" />
    <rect y="54" width="76" height="22" :fill="c.snowField" />
    <path :fill="c.shade" d="M0 64 Q19 58 38 63 T76 61 V76 H0 Z" />
    <g transform="translate(58 56) scale(.3)">
      <rect x="-3" y="58" width="6" height="14" :fill="c.trunk" />
      <path :fill="c.pine" d="M0 -6 L15 22 H-15 Z M0 12 L19 42 H-19 Z M0 30 L23 62 H-23 Z" />
      <path :fill="c.pineCap" d="M0 -6 L9 11 L4 9 L0 13 L-4 9 L-9 11 Z" />
    </g>
  </svg>

  <svg
    v-else-if="season === 'qianshan'"
    viewBox="0 0 76 76"
    preserveAspectRatio="xMidYMax slice"
    aria-hidden="true"
  >
    <g :stroke="c.bird" stroke-width="1.6" fill="none" stroke-linecap="round">
      <path d="M28 18 q2.5 -2.5 5 0 q2.5 -2.5 5 0" />
      <path d="M44 12 q2 -2 4 0 q2 -2 4 0" />
    </g>
    <path :fill="c.farMountain" d="M0 38 Q19 26 34 34 T76 30 V76 H0 Z" />
    <path :fill="c.mist" d="M0 40 Q22 35 44 39 T76 36 V46 H0 Z" />
    <path :fill="c.midMountain" d="M0 52 Q25 40 48 49 T76 46 V76 H0 Z" />
    <path :fill="c.nearMountain" d="M0 64 Q30 52 62 60 T76 58 V76 H0 Z" />
    <g :fill="c.pine">
      <path d="M16 66 l3.4 6 h-6.8 Z M16 63 l4 7.5 h-8 Z" />
      <path d="M60 64 l3 5.5 h-6 Z" />
    </g>
  </svg>

  <svg
    v-else-if="season === 'jiangnan'"
    viewBox="0 0 76 76"
    preserveAspectRatio="xMidYMax slice"
    aria-hidden="true"
  >
    <g>
      <rect x="10" y="24" width="20" height="20" :fill="c.wallShade" />
      <path :fill="c.roofTile" d="M8 24 L32 24 L29 19 L11 19 Z" />
      <path :fill="c.wallFace" d="M34 44 V30 h14 V44 Z" />
      <path d="M34 30 l4 -6 h6" :stroke="c.roofCap" stroke-width="2.4" fill="none" />
      <rect x="33" y="42" width="16" height="2.6" :fill="c.roofCap" />
    </g>
    <circle cx="21" cy="31" r="1.9" :fill="c.windowLight" />
    <path :fill="c.bridge" d="M50 44 Q61 30 72 44 Q61 35 50 44 Z" />
    <rect y="46" width="76" height="30" :fill="c.water" />
    <path :fill="c.waterShade" d="M0 54 Q19 51 38 53 T76 52 V76 H0 Z" />
    <g :stroke="c.ripple" stroke-width="1.6" stroke-linecap="round" fill="none">
      <path d="M12 62 h10" /><path d="M40 68 h8" /><path d="M60 60 h9" />
    </g>
  </svg>

  <svg
    v-else-if="season === 'damo'"
    viewBox="0 0 76 76"
    preserveAspectRatio="xMidYMax slice"
    aria-hidden="true"
  >
    <circle cx="54" cy="17" r="10" :fill="c.sunHalo" />
    <circle cx="54" cy="17" r="6.2" :fill="c.sun" />
    <path :fill="c.smoke" d="M37 44 C36 36 38 28 37 20 L39.4 20 C38.6 28 40.4 36 39.4 44 Z" />
    <path :fill="c.duneBack" d="M0 42 Q19 34 38 40 T76 38 V76 H0 Z" />
    <path :fill="c.duneMid" d="M0 56 Q25 47 50 53 T76 51 V76 H0 Z" />
    <path :fill="c.duneFront" d="M0 68 Q25 62 50 66 T76 65 V76 H0 Z" />
    <g transform="translate(30 47)" :fill="c.camel">
      <path d="M0 2 q1.2 -2.6 3 -2.9 q.6 -1.4 2 -1.4 q1.4 0 2 1.4 q1.8 .3 2.9 2.9 q.3 1.1 -.8 1.1 h-8.3 q-1.1 0 -.8 -1.1 Z" />
      <path d="M.3 1 l-2.2 2.5 l1.1 .9 l2 -2 Z" />
      <rect x="1.7" y="2.9" width=".8" height="2.6" /><rect x="4" y="2.9" width=".8" height="2.6" /><rect x="6.3" y="2.9" width=".8" height="2.6" />
    </g>
  </svg>

  <svg
    v-else-if="season === 'pinghu'"
    viewBox="0 0 76 76"
    preserveAspectRatio="xMidYMax slice"
    aria-hidden="true"
  >
    <path :fill="c.farHill" d="M0 42 Q19 34 38 39 T76 36 V76 H0 Z" />
    <path :fill="c.nearHill" d="M0 50 Q25 43 50 48 T76 46 V76 H0 Z" />
    <rect y="52" width="76" height="24" :fill="c.lake" />
    <path :fill="c.lakeShade" d="M0 60 Q19 57 38 59 T76 58 V76 H0 Z" opacity=".55" />
    <g :stroke="c.ripple" stroke-width="1.6" stroke-linecap="round" fill="none">
      <path d="M14 62 h11" /><path d="M44 70 h9" /><path d="M62 60 h8" />
    </g>
    <g :stroke="c.reed" stroke-width="1.4" stroke-linecap="round" fill="none">
      <path d="M10 76 C11 69 9 65 11 60" />
      <path d="M15 76 C15.5 71 14 67 16 63" />
    </g>
    <ellipse cx="11.4" cy="58" rx="1.5" ry="3.6" :fill="c.reed" transform="rotate(10 11.4 58)" />
    <g :fill="c.boat">
      <path d="M30 62 Q37 65.5 44 62 L41 64 Q37 65.4 33 64 Z" />
      <circle cx="37.6" cy="59.6" r="1.4" />
    </g>
    <path d="M37.6 60.4 L41.6 55" :stroke="c.boat" stroke-width="1" stroke-linecap="round" fill="none" />
  </svg>
</template>
