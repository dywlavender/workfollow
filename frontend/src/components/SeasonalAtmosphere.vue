<script setup lang="ts">
import { computed } from 'vue'

import { getAppearancePalette, resolveAppearanceMode } from '@/modules/theme'
import { useAppStore } from '@/stores/app'

const appStore = useAppStore()

// 所有配置了 atmosphere 的配色(四季 + 山水)在"随主题配色"背景下启用场景
const scene = computed(() => {
  const palette = appStore.appearancePalette
  return appStore.appearanceBackground === 'theme' && getAppearancePalette(palette).atmosphere ? palette : null
})
const mode = computed(() => resolveAppearanceMode(appStore.appearanceMode, appStore.systemDark))
</script>

<template>
  <!-- 氛围底层(天空/极光/颗粒/场景):压在工作台壳层之下 -->
  <div v-if="scene" class="seasonal-atmosphere" :data-scene="scene" :data-mode="mode" aria-hidden="true">
    <div class="seasonal-sky" />
    <div class="seasonal-aurora" />
    <div class="seasonal-grain" />

    <div class="seasonal-scene">
      <svg v-if="scene === 'spring'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
        <g stroke="var(--season-bird)" stroke-width="3" fill="none" stroke-linecap="round">
          <path d="M600 96 q9 -9 18 0 q9 -9 18 0" />
          <path d="M668 74 q7 -7 14 0 q7 -7 14 0" />
          <path d="M560 66 q6 -6 12 0 q6 -6 12 0" />
        </g>
        <path fill="var(--season-hillA)" d="M0 208 Q180 150 360 186 T720 176 Q900 148 1080 184 T1440 170 V320 H0 Z" />
        <path fill="var(--season-hillB)" d="M0 262 Q240 214 480 246 T960 238 Q1200 216 1440 250 V320 H0 Z" />
        <g transform="translate(300 118)">
          <path fill="var(--season-trunk)" d="M-7 130 C-5 84 -9 52 -16 22 L-4 30 C-2 60 2 92 7 130 Z" />
          <circle cx="-38" cy="10" r="34" fill="var(--season-blossom2)" />
          <circle cx="14" cy="-18" r="42" fill="var(--season-blossom1)" />
          <circle cx="58" cy="18" r="30" fill="var(--season-blossom2)" />
          <circle cx="-8" cy="26" r="40" fill="var(--season-blossom3)" />
          <circle cx="36" cy="44" r="24" fill="var(--season-blossom1)" />
        </g>
      </svg>

      <svg v-else-if="scene === 'summer'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
        <circle cx="1140" cy="86" r="58" fill="var(--season-sunRing)" opacity=".55" />
        <rect y="124" width="1440" height="196" fill="var(--season-seaTop)" />
        <path fill="var(--season-seaBottom)" d="M0 196 Q200 182 420 194 T880 192 T1340 198 L1440 194 V320 H0 Z" />
        <path fill="var(--season-island)" d="M150 126 C186 88 232 78 268 96 C288 104 306 118 318 126 Z" />
        <g stroke="var(--season-foam)" stroke-width="4" fill="none" stroke-linecap="round">
          <path d="M120 252 h56" /><path d="M260 276 h44" /><path d="M520 246 h60" />
          <path d="M700 282 h48" /><path d="M1020 250 h56" /><path d="M1240 278 h44" />
        </g>
        <g transform="translate(430 138)">
          <path fill="var(--season-sail)" d="M0 -44 L0 6 L-30 6 Z" />
          <path fill="var(--season-sail)" d="M6 -34 L6 6 L30 6 Z" opacity=".82" />
          <path fill="var(--season-hull)" d="M-36 10 L36 10 L24 26 L-24 26 Z" />
        </g>
      </svg>

      <svg v-else-if="scene === 'autumn'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
        <path fill="var(--season-backHill)" d="M0 168 Q200 116 400 152 T820 142 Q1040 110 1240 150 T1440 140 V320 H0 Z" />
        <path fill="var(--season-midHill)" d="M0 214 Q260 168 520 200 T1060 192 Q1250 172 1440 202 V320 H0 Z" />
        <rect y="238" width="1440" height="82" fill="var(--season-field)" />
        <g stroke="var(--season-row)" stroke-width="7" stroke-linecap="round">
          <path d="M-20 322 L340 240" /><path d="M220 322 L500 244" /><path d="M470 322 L672 246" />
          <path d="M740 322 L868 248" /><path d="M1010 322 L1076 250" /><path d="M1270 322 L1292 252" />
        </g>
        <g transform="translate(300 150)">
          <path fill="var(--season-trunk)" d="M-6 90 C-4 58 -8 34 -13 14 L-3 20 C0 46 3 68 6 90 Z" />
          <circle cx="-26" cy="-2" r="26" fill="var(--season-tree2)" />
          <circle cx="12" cy="-20" r="32" fill="var(--season-tree1)" />
          <circle cx="40" cy="6" r="22" fill="var(--season-tree3)" />
          <circle cx="2" cy="14" r="24" fill="var(--season-tree1)" />
        </g>
      </svg>

      <svg v-else-if="scene === 'winter'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
        <g fill="var(--season-moonFill)" :style="{ opacity: 'var(--season-starsOpacity)' }">
          <circle cx="180" cy="60" r="2" /><circle cx="300" cy="34" r="1.6" />
          <circle cx="420" cy="76" r="1.4" /><circle cx="520" cy="30" r="2" />
          <circle cx="700" cy="58" r="1.5" /><circle cx="860" cy="36" r="1.8" />
          <circle cx="1010" cy="70" r="1.4" /><circle cx="1330" cy="44" r="1.8" />
        </g>
        <g :style="{ opacity: 'var(--season-moonOpacity)' }">
          <circle cx="1210" cy="62" r="46" fill="var(--season-moonHalo)" />
          <circle cx="1210" cy="62" r="26" fill="var(--season-moonFill)" />
        </g>
        <path fill="var(--season-backMountain)" d="M0 190 L210 84 L420 190 Z M420 190 L560 108 L760 190 Z M760 190 L940 96 L1160 190 Z M1160 190 L1310 122 L1440 190 Z" />
        <g fill="var(--season-cap)">
          <path d="M210 84 L164 108 L184 104 L204 118 L226 102 L248 110 Z" />
          <path d="M560 108 L524 128 L542 124 L560 136 L580 124 L600 130 Z" />
          <path d="M940 96 L898 120 L918 116 L938 130 L962 112 L982 122 Z" />
          <path d="M1310 122 L1278 140 L1296 136 L1312 146 L1330 136 L1346 142 Z" />
        </g>
        <path fill="var(--season-midMountain)" d="M0 236 L150 178 L300 230 L470 186 L640 238 L820 196 L1000 240 L1200 200 L1380 238 L1440 226 V320 H0 Z" />
        <rect y="258" width="1440" height="62" fill="var(--season-snowField)" />
        <path fill="var(--season-shade)" d="M0 282 Q300 266 640 282 T1440 278 V320 H0 Z" />
        <g transform="translate(300 196)">
          <g>
            <rect x="-3" y="58" width="6" height="14" fill="var(--season-trunk)" />
            <path fill="var(--season-pine)" d="M0 -6 L15 22 H-15 Z M0 12 L19 42 H-19 Z M0 30 L23 62 H-23 Z" />
            <path fill="var(--season-pineCap)" d="M0 -6 L9 11 L4 9 L0 13 L-4 9 L-9 11 Z" />
          </g>
          <g transform="translate(64 22) scale(.72)">
            <rect x="-3" y="58" width="6" height="14" fill="var(--season-trunk)" />
            <path fill="var(--season-pine)" d="M0 -6 L15 22 H-15 Z M0 12 L19 42 H-19 Z M0 30 L23 62 H-23 Z" />
            <path fill="var(--season-pineCap)" d="M0 -6 L9 11 L4 9 L0 13 L-4 9 L-9 11 Z" />
          </g>
          <g transform="translate(-58 34) scale(.55)">
            <rect x="-3" y="58" width="6" height="14" fill="var(--season-trunk)" />
            <path fill="var(--season-pine)" d="M0 -6 L15 22 H-15 Z M0 12 L19 42 H-19 Z M0 30 L23 62 H-23 Z" />
            <path fill="var(--season-pineCap)" d="M0 -6 L9 11 L4 9 L0 13 L-4 9 L-9 11 Z" />
          </g>
        </g>
      </svg>

      <svg v-else-if="scene === 'qianshan'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
        <g stroke="var(--season-bird)" stroke-width="3" fill="none" stroke-linecap="round">
          <path d="M520 84 q9 -9 18 0 q9 -9 18 0" />
          <path d="M596 60 q7 -7 14 0 q7 -7 14 0" />
          <path d="M470 52 q6 -6 12 0 q6 -6 12 0" />
        </g>
        <path fill="var(--season-farMountain)" d="M0 172 Q240 122 480 156 T960 146 Q1200 118 1440 152 V320 H0 Z" />
        <path fill="var(--season-mist)" d="M0 176 Q240 160 480 172 T960 166 Q1200 152 1440 168 V198 H0 Z" />
        <path fill="var(--season-midMountain)" d="M0 224 Q260 176 520 208 T1040 200 Q1240 178 1440 208 V320 H0 Z" />
        <path fill="var(--season-mist)" d="M0 228 Q300 212 600 222 T1200 216 Q1320 210 1440 220 V248 H0 Z" />
        <path fill="var(--season-nearMountain)" d="M0 268 Q300 228 640 256 T1440 250 V320 H0 Z" />
        <path fill="var(--season-frontHill)" d="M0 296 Q360 268 720 286 T1440 282 V320 H0 Z" />
        <g fill="var(--season-pine)">
          <path d="M176 296 l11 20 h-22 Z M176 288 l13 24 h-26 Z" />
          <path d="M1214 288 l10 18 h-20 Z M1214 281 l12 22 h-24 Z" />
          <path d="M688 298 l9 16 h-18 Z" />
        </g>
      </svg>

      <svg v-else-if="scene === 'jiangnan'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
        <g>
          <path fill="var(--season-wallShade)" d="M90 210 V158 h110 V210 Z" />
          <path fill="var(--season-roofTile)" d="M82 158 L208 158 L198 144 L92 144 Z" />
          <path fill="var(--season-wallShade)" d="M260 210 V170 h90 V210 Z" />
          <path fill="var(--season-roofTile)" d="M252 170 L358 170 L349 158 L261 158 Z" />
          <path fill="var(--season-wallShade)" d="M410 210 V162 h120 V210 Z" />
          <path fill="var(--season-roofTile)" d="M402 162 L538 162 L528 147 L412 147 Z" />
        </g>
        <g>
          <path fill="var(--season-wallFace)" d="M560 214 V168 h16 v-14 h16 v-14 h20 v14 h16 v14 h16 V214 Z" />
          <path d="M560 168 h16 v-14 h16 v-14 h20" stroke="var(--season-roofCap)" stroke-width="5" fill="none" />
          <rect x="556" y="208" width="148" height="6" fill="var(--season-roofCap)" />
          <path fill="var(--season-wallFace)" d="M730 214 V176 h100 V214 Z" />
          <path fill="var(--season-roofTile)" d="M722 176 L838 176 L829 163 L731 163 Z" />
        </g>
        <g fill="var(--season-windowLight)">
          <rect x="120" y="176" width="10" height="12" />
          <rect x="300" y="182" width="9" height="11" />
          <rect x="600" y="190" width="10" height="12" />
          <rect x="760" y="186" width="9" height="11" />
        </g>
        <path fill="var(--season-bridge)" d="M866 256 Q980 196 1094 256 Q980 218 866 256 Z" />
        <rect y="254" width="1440" height="66" fill="var(--season-water)" />
        <path fill="var(--season-waterShade)" d="M0 268 Q220 258 460 266 T940 262 T1440 268 V320 H0 Z" />
        <g stroke="var(--season-ripple)" stroke-width="3" stroke-linecap="round" fill="none">
          <path d="M140 284 h56" /><path d="M340 300 h44" /><path d="M620 282 h60" />
          <path d="M920 296 h48" /><path d="M1180 278 h56" /><path d="M1330 302 h40" />
        </g>
      </svg>

      <svg v-else-if="scene === 'damo'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
        <circle cx="1140" cy="84" r="62" fill="var(--season-sunHalo)" />
        <circle cx="1140" cy="84" r="38" fill="var(--season-sun)" />
        <path fill="var(--season-smoke)" d="M696 182 C692 150 702 124 697 94 C694 74 699 56 703 42 L712 43 C708 60 712 78 709 98 C705 126 714 152 710 182 Z" />
        <path fill="var(--season-duneBack)" d="M0 192 Q360 152 720 180 T1440 170 V320 H0 Z" />
        <path fill="var(--season-duneMid)" d="M0 244 Q400 204 800 232 T1440 224 V320 H0 Z" />
        <path fill="var(--season-duneFront)" d="M0 292 Q480 258 960 280 T1440 274 V320 H0 Z" />
        <g fill="var(--season-poplar)">
          <path d="M170 196 C180 216 182 244 177 266 L164 266 C159 242 161 214 170 196 Z" />
          <rect x="167" y="264" width="6" height="24" />
        </g>
        <g fill="var(--season-camel)">
          <g transform="translate(498 228)">
            <path d="M0 8 q4 -9 10 -10 q2 -5 7 -5 q5 0 7 5 q6 1 10 10 q1 4 -3 4 l-28 0 q-4 0 -3 -4 Z" />
            <path d="M1 4 l-8 9 l4 3 l7 -7 Z" />
            <rect x="6" y="10" width="2.6" height="9" /><rect x="14" y="10" width="2.6" height="9" />
            <rect x="23" y="10" width="2.6" height="9" /><rect x="30" y="10" width="2.6" height="9" />
          </g>
          <g transform="translate(566 224)">
            <path d="M0 8 q4 -9 10 -10 q2 -5 7 -5 q5 0 7 5 q6 1 10 10 q1 4 -3 4 l-28 0 q-4 0 -3 -4 Z" />
            <path d="M1 4 l-8 9 l4 3 l7 -7 Z" />
            <rect x="6" y="10" width="2.6" height="9" /><rect x="14" y="10" width="2.6" height="9" />
            <rect x="23" y="10" width="2.6" height="9" /><rect x="30" y="10" width="2.6" height="9" />
          </g>
          <g transform="translate(634 229)">
            <path d="M0 8 q4 -9 10 -10 q2 -5 7 -5 q5 0 7 5 q6 1 10 10 q1 4 -3 4 l-28 0 q-4 0 -3 -4 Z" />
            <path d="M1 4 l-8 9 l4 3 l7 -7 Z" />
            <rect x="6" y="10" width="2.6" height="9" /><rect x="14" y="10" width="2.6" height="9" />
            <rect x="23" y="10" width="2.6" height="9" /><rect x="30" y="10" width="2.6" height="9" />
          </g>
        </g>
        <circle cx="560" cy="250" r="10" fill="var(--season-ember)" opacity=".55" />
        <circle cx="560" cy="250" r="4.5" fill="var(--season-ember)" />
      </svg>

      <svg v-else-if="scene === 'pinghu'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
        <g fill="var(--season-moonFill)" :style="{ opacity: 'var(--season-starsOpacity)' }">
          <circle cx="180" cy="54" r="2" /><circle cx="320" cy="36" r="1.6" />
          <circle cx="460" cy="70" r="1.4" /><circle cx="620" cy="40" r="2" />
          <circle cx="780" cy="64" r="1.5" /><circle cx="900" cy="34" r="1.8" />
          <circle cx="1040" cy="58" r="1.4" /><circle cx="1340" cy="48" r="1.8" />
        </g>
        <g :style="{ opacity: 'var(--season-moonOpacity)' }">
          <circle cx="1210" cy="62" r="46" fill="var(--season-moonHalo)" />
          <circle cx="1210" cy="62" r="26" fill="var(--season-moonFill)" />
        </g>
        <path fill="var(--season-farHill)" d="M0 186 Q240 156 480 174 T960 168 Q1200 152 1440 172 V320 H0 Z" />
        <path fill="var(--season-nearHill)" d="M0 204 Q320 182 640 196 T1440 190 V320 H0 Z" />
        <rect y="212" width="1440" height="108" fill="var(--season-lake)" />
        <path fill="var(--season-lakeShade)" d="M0 236 Q300 224 640 232 T1440 228 V320 H0 Z" opacity=".55" />
        <rect x="1178" y="212" width="64" height="108" fill="var(--season-moonPath)" />
        <g stroke="var(--season-ripple)" stroke-width="3" stroke-linecap="round" fill="none">
          <path d="M180 252 h64" /><path d="M420 276 h52" /><path d="M700 246 h60" />
          <path d="M920 286 h48" /><path d="M1120 258 h56" /><path d="M1320 292 h40" />
          <path d="M540 300 h44" /><path d="M260 296 h36" />
        </g>
        <g stroke="var(--season-reed)" stroke-width="3.5" stroke-linecap="round" fill="none">
          <path d="M60 320 C64 296 58 278 66 258" />
          <path d="M84 320 C86 300 80 286 88 268" />
          <path d="M108 320 C108 302 104 292 110 278" />
        </g>
        <g fill="var(--season-reed)">
          <ellipse cx="67" cy="252" rx="3.5" ry="10" transform="rotate(12 67 252)" />
          <ellipse cx="89" cy="262" rx="3" ry="9" transform="rotate(10 89 262)" />
          <ellipse cx="111" cy="272" rx="2.6" ry="8" transform="rotate(8 111 272)" />
        </g>
        <g fill="var(--season-boat)">
          <path d="M390 236 Q424 248 458 236 L447 243 Q424 249 401 243 Z" />
          <circle cx="428" cy="227" r="4" />
        </g>
        <path d="M428 231 L444 214" stroke="var(--season-boat)" stroke-width="2.4" stroke-linecap="round" fill="none" />
      </svg>
    </div>
  </div>

  <!-- 飘落粒子层:独立于氛围容器,浮在工作台壳层之上(对齐设计稿 season-themes.html),
       仍低于随手记悬浮层、菜单与弹窗;沉浸编辑时被编辑器覆盖,不打扰写作。 -->
  <div v-if="scene" class="seasonal-overlay" :data-scene="scene" aria-hidden="true">
    <template v-if="scene === 'spring'">
      <svg v-for="item in [
        { left: '7%', dur: '15s', delay: '0s', fill: 'var(--season-particle1)' },
        { left: '19%', dur: '20s', delay: '-6s', fill: 'var(--season-particle2)' },
        { left: '41%', dur: '17s', delay: '-11s', fill: 'var(--season-particle3)' },
        { left: '58%', dur: '23s', delay: '-3s', fill: 'var(--season-particle1)' },
        { left: '74%', dur: '18s', delay: '-14s', fill: 'var(--season-particle2)' },
        { left: '88%', dur: '22s', delay: '-9s', fill: 'var(--season-particle3)' },
      ]" :key="item.left" class="seasonal-fall-item seasonal-petal" :style="{ left: item.left, '--dur': item.dur, '--delay': item.delay }" viewBox="0 0 24 24">
        <path d="M12 1 C18 5 20 12 12 23 C4 12 6 5 12 1Z" :fill="item.fill" />
      </svg>
    </template>

    <template v-else-if="scene === 'autumn'">
      <svg v-for="item in [
        { left: '8%', dur: '16s', delay: '0s', fill: 'var(--season-particle1)' },
        { left: '26%', dur: '21s', delay: '-8s', fill: 'var(--season-particle2)' },
        { left: '52%', dur: '18s', delay: '-13s', fill: 'var(--season-particle3)' },
        { left: '71%', dur: '24s', delay: '-4s', fill: 'var(--season-particle2)' },
        { left: '87%', dur: '20s', delay: '-16s', fill: 'var(--season-particle1)' },
      ]" :key="item.left" class="seasonal-fall-item seasonal-leaf" :style="{ left: item.left, '--dur': item.dur, '--delay': item.delay }" viewBox="0 0 24 24">
        <path d="M12 2l2.2 3.6 3.8-1.2-.9 3.9 3.9.9-2.6 3 2.6 3-3.9.9.9 3.9-3.8-1.2L12 22l-2.2-3.2-3.8 1.2.9-3.9-3.9-.9 2.6-3-2.6-3 3.9-.9-.9-3.9 3.8 1.2z" :fill="item.fill" />
      </svg>
    </template>

    <template v-else-if="scene === 'winter'">
      <svg v-for="item in [
        { left: '6%', dur: '18s', delay: '0s', stroke: 'var(--season-particle1)' },
        { left: '22%', dur: '23s', delay: '-9s', stroke: 'var(--season-particle2)' },
        { left: '45%', dur: '20s', delay: '-15s', stroke: 'var(--season-particle1)' },
        { left: '63%', dur: '25s', delay: '-5s', stroke: 'var(--season-particle3)' },
        { left: '81%', dur: '21s', delay: '-18s', stroke: 'var(--season-particle1)' },
        { left: '93%', dur: '27s', delay: '-12s', stroke: 'var(--season-particle2)' },
      ]" :key="item.left" class="seasonal-fall-item seasonal-flake" :style="{ left: item.left, '--dur': item.dur, '--delay': item.delay }" viewBox="0 0 24 24" stroke-width="1.8" stroke-linecap="round">
        <path d="M12 2v20M4 6l16 12M20 6L4 18" fill="none" :stroke="item.stroke" />
      </svg>
    </template>

    <template v-else-if="scene === 'qianshan'">
      <span v-for="item in [
        { left: '6%', top: '14%', w: '140px', h: '22px', dur: '30s', delay: '0s', bg: 'var(--season-particle1)' },
        { left: '30%', top: '30%', w: '110px', h: '18px', dur: '26s', delay: '-9s', bg: 'var(--season-particle2)' },
        { left: '52%', top: '22%', w: '150px', h: '26px', dur: '34s', delay: '-17s', bg: 'var(--season-particle3)' },
        { left: '68%', top: '44%', w: '96px', h: '16px', dur: '28s', delay: '-5s', bg: 'var(--season-particle1)' },
        { left: '84%', top: '10%', w: '120px', h: '20px', dur: '32s', delay: '-23s', bg: 'var(--season-particle2)' },
      ]" :key="item.left" class="seasonal-fall-item seasonal-wisp" :style="{ left: item.left, top: item.top, width: item.w, height: item.h, background: item.bg, '--dur': item.dur, '--delay': item.delay }" />
    </template>

    <template v-else-if="scene === 'jiangnan'">
      <span v-for="item in [
        { left: '4%', dur: '1.1s', delay: '0s' },
        { left: '12%', dur: '1.3s', delay: '-0.6s' },
        { left: '21%', dur: '0.9s', delay: '-0.3s' },
        { left: '29%', dur: '1.2s', delay: '-0.9s' },
        { left: '37%', dur: '1s', delay: '-0.2s' },
        { left: '46%', dur: '1.4s', delay: '-0.7s' },
        { left: '54%', dur: '0.95s', delay: '-0.4s' },
        { left: '63%', dur: '1.25s', delay: '-1s' },
        { left: '71%', dur: '1.05s', delay: '-0.15s' },
        { left: '79%', dur: '1.35s', delay: '-0.8s' },
        { left: '88%', dur: '1s', delay: '-0.5s' },
        { left: '95%', dur: '1.15s', delay: '-0.25s' },
      ]" :key="item.left" class="seasonal-fall-item seasonal-rain" :style="{ left: item.left, '--dur': item.dur, '--delay': item.delay }" />
    </template>

    <template v-else-if="scene === 'damo'">
      <span v-for="item in [
        { left: '8%', top: '18%', w: '7px', h: '7px', dur: '9s', delay: '0s', bg: 'var(--season-particle1)' },
        { left: '22%', top: '36%', w: '5px', h: '5px', dur: '7.5s', delay: '-3s', bg: 'var(--season-particle2)' },
        { left: '38%', top: '12%', w: '9px', h: '9px', dur: '10.5s', delay: '-6s', bg: 'var(--season-particle3)' },
        { left: '55%', top: '44%', w: '6px', h: '6px', dur: '8s', delay: '-1.5s', bg: 'var(--season-particle1)' },
        { left: '68%', top: '24%', w: '8px', h: '8px', dur: '9.5s', delay: '-4.5s', bg: 'var(--season-particle2)' },
        { left: '82%', top: '52%', w: '5px', h: '5px', dur: '7s', delay: '-2s', bg: 'var(--season-particle3)' },
        { left: '92%', top: '32%', w: '7px', h: '7px', dur: '11s', delay: '-7.5s', bg: 'var(--season-particle1)' },
      ]" :key="item.left" class="seasonal-fall-item seasonal-sand" :style="{ left: item.left, top: item.top, width: item.w, height: item.h, background: item.bg, '--dur': item.dur, '--delay': item.delay }" />
    </template>

    <template v-else-if="scene === 'pinghu'">
      <span v-for="item in [
        { left: '12%', top: '62%', w: '8px', h: '8px', dur: '14s', delay: '0s', bg: 'var(--season-particle1)' },
        { left: '30%', top: '78%', w: '6px', h: '6px', dur: '17s', delay: '-5s', bg: 'var(--season-particle2)' },
        { left: '48%', top: '86%', w: '10px', h: '10px', dur: '13s', delay: '-9s', bg: 'var(--season-particle3)' },
        { left: '64%', top: '70%', w: '7px', h: '7px', dur: '18s', delay: '-3s', bg: 'var(--season-particle1)' },
        { left: '78%', top: '58%', w: '6px', h: '6px', dur: '15s', delay: '-11s', bg: 'var(--season-particle2)' },
        { left: '90%', top: '82%', w: '9px', h: '9px', dur: '16s', delay: '-7s', bg: 'var(--season-particle3)' },
      ]" :key="item.left" class="seasonal-fall-item seasonal-glint" :style="{ left: item.left, top: item.top, width: item.w, height: item.h, background: item.bg, '--dur': item.dur, '--delay': item.delay }" />
    </template>
  </div>
</template>

<style>
.seasonal-atmosphere {
  position: fixed;
  inset: 0;
  z-index: var(--layer-atmosphere, 0);
  overflow: hidden;
  pointer-events: none;
}

.seasonal-sky {
  position: absolute;
  inset: 0;
  background: var(--theme-atmosphere, none);
}

.seasonal-aurora {
  position: absolute;
  z-index: 2;
  width: 720px;
  height: 160px;
  top: 5%;
  left: 26%;
  border-radius: var(--radius-full);
  background: linear-gradient(90deg, transparent, color-mix(in srgb, var(--season-auroraA) 45%, transparent), color-mix(in srgb, var(--season-auroraB) 35%, transparent), transparent);
  filter: blur(56px);
  opacity: 0;
  transform: rotate(-9deg);
}

.seasonal-atmosphere[data-mode="dark"][data-scene="spring"] .seasonal-aurora,
.seasonal-atmosphere[data-mode="dark"][data-scene="winter"] .seasonal-aurora,
.seasonal-atmosphere[data-mode="dark"][data-scene="qianshan"] .seasonal-aurora,
.seasonal-atmosphere[data-mode="dark"][data-scene="pinghu"] .seasonal-aurora,
.seasonal-atmosphere[data-mode="dark"][data-scene="damo"] .seasonal-aurora {
  opacity: .7;
  animation: seasonal-aurora-drift 15s ease-in-out infinite alternate;
}

.seasonal-grain {
  position: absolute;
  inset: 0;
  z-index: 3;
  opacity: 0;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='140' height='140'%3E%3Cfilter id='seasonal-noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='2'/%3E%3C/filter%3E%3Crect width='140' height='140' filter='url(%23seasonal-noise)' opacity='.5'/%3E%3C/svg%3E");
}

.seasonal-atmosphere[data-scene="autumn"] .seasonal-grain,
.seasonal-atmosphere[data-scene="damo"] .seasonal-grain {
  opacity: .05;
  mix-blend-mode: multiply;
}

.seasonal-atmosphere[data-scene="autumn"][data-mode="dark"] .seasonal-grain,
.seasonal-atmosphere[data-scene="damo"][data-mode="dark"] .seasonal-grain {
  opacity: .07;
  mix-blend-mode: overlay;
}

.seasonal-scene {
  position: absolute;
  right: 0;
  bottom: 0;
  left: 0;
  z-index: 1;
  height: 32vh;
  opacity: .94;
}

.seasonal-scene-svg {
  display: block;
  width: 100%;
  height: 100%;
}

.seasonal-overlay {
  position: fixed;
  inset: 0;
  z-index: var(--layer-season-fall);
  overflow: hidden;
  pointer-events: none;
}

.seasonal-fall-item {
  position: absolute;
  top: -50px;
  will-change: transform;
}

.seasonal-petal { width: 19px; height: 19px; opacity: .8; animation: seasonal-petal-fall var(--dur, 17s) linear infinite; animation-delay: var(--delay, 0s); }
.seasonal-leaf { width: 25px; height: 25px; opacity: .8; animation: seasonal-leaf-fall var(--dur, 19s) linear infinite; animation-delay: var(--delay, 0s); }
.seasonal-flake { width: 16px; height: 16px; opacity: .85; animation: seasonal-flake-fall var(--dur, 21s) linear infinite; animation-delay: var(--delay, 0s); }

.seasonal-wisp { border-radius: var(--radius-full); filter: blur(7px); opacity: 0; animation: seasonal-wisp-drift var(--dur, 30s) linear infinite; animation-delay: var(--delay, 0s); }
.seasonal-rain { width: 1.5px; height: 26px; background: linear-gradient(to bottom, transparent, var(--season-rain)); opacity: .9; animation: seasonal-rain-fall var(--dur, 1.1s) linear infinite; animation-delay: var(--delay, 0s); }
.seasonal-sand { border-radius: var(--radius-full); opacity: 0; animation: seasonal-sand-blow var(--dur, 9s) linear infinite; animation-delay: var(--delay, 0s); }
.seasonal-glint { border-radius: var(--radius-full); box-shadow: 0 0 9px var(--season-particle2); opacity: 0; animation: seasonal-glint-rise var(--dur, 14s) ease-in-out infinite; animation-delay: var(--delay, 0s); }

@keyframes seasonal-aurora-drift {
  from { transform: rotate(-9deg) translateX(-50px) scaleY(1); opacity: .45; }
  to { transform: rotate(-6deg) translateX(60px) scaleY(1.3); opacity: .78; }
}

@keyframes seasonal-petal-fall {
  0% { transform: translate(0, -5vh) rotate(0deg); opacity: 0; }
  6% { opacity: .85; }
  25% { transform: translate(5vw, 24vh) rotate(95deg); }
  50% { transform: translate(-3vw, 50vh) rotate(190deg); }
  75% { transform: translate(4vw, 76vh) rotate(280deg); }
  94% { opacity: .85; }
  100% { transform: translate(-2vw, 110vh) rotate(370deg); opacity: 0; }
}

@keyframes seasonal-leaf-fall {
  0% { transform: translate(0, -5vh) rotate(0deg); opacity: 0; }
  6% { opacity: .82; }
  22% { transform: translate(4vw, 22vh) rotate(120deg); }
  50% { transform: translate(-4vw, 52vh) rotate(230deg); }
  78% { transform: translate(3vw, 80vh) rotate(330deg); }
  100% { transform: translate(-2vw, 110vh) rotate(430deg); opacity: 0; }
}

@keyframes seasonal-flake-fall {
  0% { transform: translate(0, -5vh); opacity: 0; }
  8% { opacity: .88; }
  50% { transform: translate(2vw, 52vh) rotate(160deg); }
  92% { opacity: .88; }
  100% { transform: translate(-1vw, 110vh) rotate(320deg); opacity: 0; }
}

@keyframes seasonal-wisp-drift {
  0% { transform: translateX(-18vw) translateY(0); opacity: 0; }
  12% { opacity: .7; }
  50% { transform: translateX(4vw) translateY(3vh); }
  88% { opacity: .7; }
  100% { transform: translateX(22vw) translateY(-2vh); opacity: 0; }
}

@keyframes seasonal-rain-fall {
  0% { transform: rotate(13deg) translateY(-12vh); }
  100% { transform: rotate(13deg) translateY(114vh); }
}

@keyframes seasonal-sand-blow {
  0% { transform: translate(-10vw, -6vh) rotate(0deg); opacity: 0; }
  12% { opacity: .7; }
  85% { opacity: .55; }
  100% { transform: translate(20vw, 14vh) rotate(220deg); opacity: 0; }
}

@keyframes seasonal-glint-rise {
  0% { transform: translateY(4vh) scale(.8); opacity: 0; }
  25% { opacity: .8; }
  75% { opacity: .55; }
  100% { transform: translateY(-9vh) scale(1.15); opacity: 0; }
}

@media (prefers-reduced-motion: reduce) {
  .seasonal-fall-item,
  .seasonal-aurora { animation: none !important; }
}
</style>
