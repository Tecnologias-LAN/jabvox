<script setup>
import { computed } from 'vue';

// Tarjeta KPI del dashboard de métricas: ícono, número grande, etiqueta y tooltip
// explicativo. Acento por tono (brand/teal/amber/ruby/slate) con degradado suave.
const props = defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  icon: { type: String, default: 'i-lucide-activity' },
  tone: { type: String, default: 'brand' }, // brand | teal | amber | ruby | slate
  hint: { type: String, default: '' }, // tooltip
});

const TONES = {
  brand: { icon: 'text-n-brand bg-n-brand/10', value: 'text-n-slate-12' },
  blue: { icon: 'text-n-blue-11 bg-n-blue-3', value: 'text-n-slate-12' },
  teal: { icon: 'text-n-teal-11 bg-n-teal-3', value: 'text-n-teal-11' },
  amber: { icon: 'text-n-amber-11 bg-n-amber-3', value: 'text-n-slate-12' },
  ruby: { icon: 'text-n-ruby-11 bg-n-ruby-3', value: 'text-n-ruby-11' },
  slate: { icon: 'text-n-slate-11 bg-n-alpha-2', value: 'text-n-slate-12' },
};

const tone = computed(() => TONES[props.tone] || TONES.brand);
</script>

<template>
  <div
    class="relative flex flex-col gap-3 p-4 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm transition-shadow hover:shadow-md"
    :title="hint || undefined"
  >
    <div class="flex items-center justify-between">
      <span
        class="flex items-center justify-center w-9 h-9 rounded-xl"
        :class="tone.icon"
        aria-hidden="true"
      >
        <span :class="`${icon} w-4.5 h-4.5`" />
      </span>
      <span
        v-if="hint"
        class="i-lucide-info w-3.5 h-3.5 text-n-slate-9"
        aria-hidden="true"
      />
    </div>
    <div>
      <p class="text-2xl font-bold tabular-nums" :class="tone.value">
        {{ value }}
      </p>
      <p class="text-xs text-n-slate-11 mt-0.5">{{ label }}</p>
    </div>
  </div>
</template>
