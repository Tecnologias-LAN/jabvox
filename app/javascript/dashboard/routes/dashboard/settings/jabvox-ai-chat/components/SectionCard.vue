<script setup>
// Premium settings card: header (icon + title + description + actions) on top,
// hairline separator, body slot, optional footer slot.
defineProps({
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  icon: { type: String, default: '' },
});
</script>

<template>
  <div
    class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
  >
    <div
      v-if="title || $slots.actions"
      class="flex flex-col gap-3 border-b border-n-weak px-5 py-4 sm:px-6 sm:py-5 sm:flex-row sm:items-center sm:justify-between"
    >
      <div class="flex items-start gap-3 min-w-0">
        <span
          v-if="icon"
          :class="icon"
          class="size-5 text-n-slate-11 shrink-0 mt-0.5"
        />
        <div class="min-w-0">
          <h2 v-if="title" class="text-base font-semibold text-n-slate-12">
            {{ title }}
          </h2>
          <p
            v-if="description"
            class="mt-0.5 text-sm leading-relaxed text-n-slate-11"
          >
            {{ description }}
          </p>
        </div>
      </div>
      <div class="shrink-0">
        <slot name="actions" />
      </div>
    </div>
    <div class="px-5 py-5 sm:px-6 sm:py-6">
      <slot />
    </div>
    <div
      v-if="$slots.footer"
      class="border-t border-n-weak bg-n-alpha-1 px-5 py-3 sm:px-6"
    >
      <slot name="footer" />
    </div>
  </div>
</template>
