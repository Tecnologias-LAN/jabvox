<script setup>
// Barra de progreso superior del asistente: pasos numerados; el completado muestra
// check, el actual se resalta con el primario, los futuros quedan atenuados.
defineProps({
  steps: { type: Array, required: true }, // [{ key, label }]
  current: { type: Number, required: true }, // índice 0-based del paso activo
});
</script>

<template>
  <ol class="flex items-center w-full gap-1 sm:gap-2" role="list">
    <li
      v-for="(step, i) in steps"
      :key="step.key"
      class="flex items-center gap-1 sm:gap-2 flex-1 last:flex-none"
    >
      <div class="flex items-center gap-2 shrink-0">
        <span
          class="flex items-center justify-center w-7 h-7 rounded-full text-xs font-semibold transition-all duration-300"
          :class="[
            i < current
              ? 'bg-n-brand text-white'
              : i === current
                ? 'bg-n-brand text-white ring-4 ring-n-brand/15'
                : 'bg-n-alpha-2 text-n-slate-10',
          ]"
          :aria-current="i === current ? 'step' : undefined"
        >
          <span v-if="i < current" class="i-lucide-check w-4 h-4" />
          <span v-else>{{ i + 1 }}</span>
        </span>
        <span
          class="hidden sm:inline text-xs font-medium transition-colors"
          :class="i <= current ? 'text-n-slate-12' : 'text-n-slate-10'"
        >
          {{ step.label }}
        </span>
      </div>
      <!-- Conector -->
      <span
        v-if="i < steps.length - 1"
        class="flex-1 h-0.5 rounded-full transition-colors duration-300"
        :class="i < current ? 'bg-n-brand' : 'bg-n-weak'"
      />
    </li>
  </ol>
</template>
