<script setup>
defineProps({
  icon: { type: String, default: 'i-lucide-database' },
  title: { type: String, required: true },
  body: { type: String, default: '' },
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-3 py-16 text-center"
  >
    <span :class="icon" class="size-10 text-n-slate-9" />
    <h3 class="text-base font-medium text-n-slate-12">{{ title }}</h3>
    <p v-if="body" class="max-w-md text-sm text-n-slate-11">
      {{ body }}
    </p>
    <div class="mt-2">
      <slot name="action" />
    </div>
  </div>
</template>
