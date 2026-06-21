<script setup>
defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
});
</script>

<template>
  <div
    class="flex items-start justify-between gap-4 pb-4 mb-4 border-b border-n-weak"
  >
    <div class="min-w-0">
      <h1 class="text-lg font-semibold text-n-slate-12 truncate">
        {{ title }}
      </h1>
      <p v-if="description" class="mt-1 text-sm text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <div class="flex items-center gap-2 shrink-0">
      <slot name="actions" />
    </div>
  </div>
</template>
