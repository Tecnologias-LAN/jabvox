<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: [Number, String], default: 0 },
  icon: { type: String, default: '' },
  tone: {
    type: String,
    default: 'slate',
    validator: v => ['slate', 'teal', 'amber', 'iris'].includes(v),
  },
});

const TONE = {
  slate: 'bg-n-alpha-2 text-n-slate-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
};
</script>

<template>
  <div
    class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm transition-shadow hover:shadow-md"
  >
    <span
      class="flex size-10 shrink-0 items-center justify-center rounded-xl"
      :class="TONE[tone]"
    >
      <span :class="icon" class="size-5" />
    </span>
    <div class="min-w-0">
      <p class="text-xl font-semibold tabular-nums text-n-slate-12">
        {{ value }}
      </p>
      <p class="text-xs text-n-slate-11 truncate">{{ label }}</p>
    </div>
  </div>
</template>
