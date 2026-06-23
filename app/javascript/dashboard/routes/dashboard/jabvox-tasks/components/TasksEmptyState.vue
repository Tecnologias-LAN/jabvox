<script setup>
defineProps({
  icon: {
    type: String,
    default: 'i-lucide-inbox',
  },
  title: {
    type: String,
    default: '',
  },
  body: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-2 px-6 py-10 text-center"
  >
    <span
      :class="icon"
      class="size-8 text-n-slate-10 mb-2"
      aria-hidden="true"
    />
    <p v-if="title" class="text-sm font-medium text-n-slate-12">
      {{ title }}
    </p>
    <p v-if="body" class="text-sm text-n-slate-10 max-w-sm">
      {{ body }}
    </p>
    <slot />
  </div>
</template>
