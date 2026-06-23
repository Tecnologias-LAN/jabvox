<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], default: '' },
  // 'ok' | 'warn' | 'idle' — drives the status dot color.
  tone: { type: String, default: 'idle' },
  dot: { type: Boolean, default: false },
});

const TONE_DOT = {
  ok: 'bg-n-teal-9',
  warn: 'bg-n-amber-9',
  idle: 'bg-n-slate-8',
};
</script>

<template>
  <div class="flex items-center justify-between gap-3 py-2">
    <span class="text-sm text-n-slate-11">{{ label }}</span>
    <span class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12">
      <span
        v-if="dot"
        class="size-1.5 rounded-full shrink-0"
        :class="TONE_DOT[tone]"
      />
      {{ value }}
    </span>
  </div>
</template>
