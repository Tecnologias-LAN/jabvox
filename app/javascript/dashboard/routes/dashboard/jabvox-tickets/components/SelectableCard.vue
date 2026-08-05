<script setup>
import { computed } from 'vue';

// Tarjeta grande seleccionable (tipo/tema/subtema del wizard). Ícono + título +
// descripción; al seleccionarse se resalta con el color primario y un check. Usa
// tokens n-* (claro/oscuro automático).
const props = defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  icon: { type: String, default: '' }, // clase i-lucide-*
  accent: { type: String, default: '' }, // color hex opcional del tema (borde/punto)
  selected: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['select']);

const onClick = () => {
  if (!props.disabled) emit('select');
};

const onKey = e => {
  if (props.disabled) return;
  if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    emit('select');
  }
};

const accentStyle = computed(() =>
  props.accent ? { '--tk-accent': props.accent } : {}
);
</script>

<template>
  <button
    type="button"
    role="radio"
    :aria-checked="selected"
    :disabled="disabled"
    :style="accentStyle"
    class="group relative flex flex-col items-start gap-2 text-left w-full p-4 rounded-2xl border transition-all duration-200 ease-out focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand disabled:opacity-40 disabled:cursor-not-allowed"
    :class="
      selected
        ? 'border-n-brand bg-n-brand/5 shadow-md shadow-n-brand/10 -translate-y-0.5'
        : 'border-n-weak bg-n-solid-1 hover:border-n-strong hover:-translate-y-0.5 hover:shadow-sm'
    "
    @click="onClick"
    @keydown="onKey"
  >
    <!-- Check al seleccionar -->
    <span
      v-if="selected"
      class="absolute top-3 right-3 flex items-center justify-center w-5 h-5 rounded-full bg-n-brand text-white transition-transform duration-200 scale-100"
      aria-hidden="true"
    >
      <span class="i-lucide-check w-3.5 h-3.5" />
    </span>

    <span
      class="flex items-center justify-center w-11 h-11 rounded-xl transition-colors"
      :class="
        selected
          ? 'bg-n-brand text-white'
          : 'bg-n-alpha-2 text-n-slate-11 group-hover:text-n-slate-12'
      "
      :style="accent && !selected ? { color: 'var(--tk-accent)' } : {}"
    >
      <span v-if="icon" :class="`${icon} w-5 h-5`" />
      <span
        v-else
        class="inline-block w-3 h-3 rounded-full"
        :style="accent ? { backgroundColor: 'var(--tk-accent)' } : {}"
      />
    </span>

    <span class="text-sm font-semibold text-n-slate-12">{{ title }}</span>
    <span v-if="description" class="text-xs text-n-slate-11 leading-relaxed">
      {{ description }}
    </span>
  </button>
</template>
