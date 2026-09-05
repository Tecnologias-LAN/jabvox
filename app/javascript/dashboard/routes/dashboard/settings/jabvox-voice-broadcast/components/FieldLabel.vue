<script setup>
// Etiqueta de campo con ícono de ayuda: al pasar el cursor por el ícono (?) muestra un
// tooltip visual inmediato explicando qué hace el campo (para que un usuario que no
// conoce la telefonía entienda cada parámetro). Usa un tooltip propio con CSS (no el
// `title` nativo, que es lento y poco visible), posicionado y con burbuja estilizada.
import { ref } from 'vue';

defineProps({
  text: { type: String, required: true },
  hint: { type: String, default: '' },
});

const show = ref(false);
</script>

<template>
  <span class="flex items-center gap-1.5">
    <span class="text-sm font-medium text-n-slate-12">{{ text }}</span>
    <span
      v-if="hint"
      class="relative inline-flex"
      @mouseenter="show = true"
      @mouseleave="show = false"
      @focusin="show = true"
      @focusout="show = false"
    >
      <span
        tabindex="0"
        class="i-lucide-help-circle size-3.5 text-n-slate-10 hover:text-n-brand cursor-help outline-none"
      />
      <!-- Burbuja del tooltip: aparece al instante al pasar el cursor -->
      <transition
        enter-active-class="transition-opacity duration-100"
        leave-active-class="transition-opacity duration-100"
        enter-from-class="opacity-0"
        leave-to-class="opacity-0"
      >
        <span
          v-if="show"
          class="absolute left-1/2 bottom-full z-50 mb-1.5 w-60 -translate-x-1/2 rounded-lg bg-n-slate-12 px-3 py-2 text-xs leading-snug text-n-solid-1 shadow-lg pointer-events-none"
          role="tooltip"
        >
          {{ hint }}
          <!-- Flechita -->
          <span
            class="absolute left-1/2 top-full -translate-x-1/2 border-4 border-transparent border-t-n-slate-12"
          />
        </span>
      </transition>
    </span>
  </span>
</template>
