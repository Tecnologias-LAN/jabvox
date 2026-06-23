<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], default: '' },
  tone: { type: String, default: 'slate' },
});

const TONE_CLASS = {
  slate: 'text-n-slate-12',
  teal: 'text-n-teal-11',
  amber: 'text-n-amber-11',
  brand: 'text-n-brand',
  ruby: 'text-n-ruby-11',
};
</script>

<template>
  <div
    class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm flex flex-col gap-1"
  >
    <p class="text-xs font-medium text-n-slate-11">{{ label }}</p>
    <p
      class="text-2xl font-semibold"
      :class="TONE_CLASS[tone] || TONE_CLASS.slate"
    >
      <slot>{{ value }}</slot>
    </p>
  </div>
</template>
