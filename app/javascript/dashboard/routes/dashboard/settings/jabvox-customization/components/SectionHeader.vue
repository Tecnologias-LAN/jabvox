<script setup>
// Section heading used at the top of every tab: title + short description on
// the left, an optional action slot (e.g. the "New" button) on the right.
defineProps({
  title: { type: String, default: '' },
  description: { type: String, default: '' },
});
</script>

<template>
  <div
    class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between"
  >
    <div class="min-w-0">
      <h2 v-if="title" class="text-base font-semibold text-n-slate-12">
        {{ title }}
      </h2>
      <p v-if="description" class="mt-1 text-sm text-n-slate-11 max-w-2xl">
        {{ description }}
      </p>
    </div>
    <div class="shrink-0">
      <slot name="action" />
    </div>
  </div>
</template>
