<script setup lang="ts">
import { computed } from 'vue'

import { resolveAppearanceMode, type AppearancePalette } from '@/modules/theme'
import { useAppStore } from '@/stores/app'

const appStore = useAppStore()
const seasonalPalettes: readonly AppearancePalette[] = ['spring', 'summer', 'autumn', 'winter']

const season = computed(() => {
  const palette = appStore.appearancePalette
  return appStore.appearanceBackground === 'theme' && seasonalPalettes.includes(palette) ? palette : null
})
const mode = computed(() => resolveAppearanceMode(appStore.appearanceMode, appStore.systemDark))
</script>

<template>
  <div v-if="season" class="seasonal-atmosphere" :data-season="season" :data-mode="mode" aria-hidden="true">
    <div class="seasonal-sky" />
    <div class="seasonal-aurora" />
    <div class="seasonal-grain" />

    <div class="seasonal-scene">
      <svg v-if="season === 'spring'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
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

      <svg v-else-if="season === 'summer'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
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

      <svg v-else-if="season === 'autumn'" class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
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

      <svg v-else class="seasonal-scene-svg" viewBox="0 0 1440 320" preserveAspectRatio="xMidYMax slice">
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
    </div>

    <div class="seasonal-overlay">
      <template v-if="season === 'spring'">
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

      <template v-else-if="season === 'autumn'">
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

      <template v-else-if="season === 'winter'">
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
    </div>
  </div>
</template>

<style>
.seasonal-atmosphere {
  position: fixed;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  pointer-events: none;
}

.app-shell.task-app-shell,
.guest-shell {
  position: relative;
  z-index: 10;
  isolation: isolate;
}

html[data-atmosphere="on"] .app-shell.task-app-shell,
html[data-atmosphere="on"] .guest-shell {
  background: transparent;
}

/* Keep the shell from stacking several translucent canvas layers on top of
   the scene. Page surfaces still provide their own themed glass/panel layer. */
.app-shell.task-app-shell > .main-area {
  position: relative;
  z-index: 1;
}

html[data-atmosphere="on"] .app-shell.task-app-shell > .main-area {
  background: transparent;
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

.seasonal-atmosphere[data-mode="dark"][data-season="spring"] .seasonal-aurora,
.seasonal-atmosphere[data-mode="dark"][data-season="winter"] .seasonal-aurora {
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

.seasonal-atmosphere[data-season="autumn"] .seasonal-grain {
  opacity: .05;
  mix-blend-mode: multiply;
}

.seasonal-atmosphere[data-season="autumn"][data-mode="dark"] .seasonal-grain {
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
  position: absolute;
  inset: 0;
  z-index: 4;
  overflow: hidden;
}

.seasonal-fall-item {
  position: absolute;
  top: -50px;
  will-change: transform;
}

.seasonal-petal { width: 19px; height: 19px; opacity: .8; animation: seasonal-petal-fall var(--dur, 17s) linear infinite; animation-delay: var(--delay, 0s); }
.seasonal-leaf { width: 25px; height: 25px; opacity: .8; animation: seasonal-leaf-fall var(--dur, 19s) linear infinite; animation-delay: var(--delay, 0s); }
.seasonal-flake { width: 16px; height: 16px; opacity: .85; animation: seasonal-flake-fall var(--dur, 21s) linear infinite; animation-delay: var(--delay, 0s); }

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

@media (prefers-reduced-motion: reduce) {
  .seasonal-fall-item,
  .seasonal-aurora { animation: none !important; }
}
</style>
