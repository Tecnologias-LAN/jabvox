<script setup>
defineProps({
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  icon: { type: String, default: '' },
});
</script>

<template>
  <section
    class="rounded-2xl bg-n-solid-2 outline outline-1 outline-n-weak shadow-sm transition-shadow duration-200 hover:shadow-md"
  >
    <header
      v-if="title || $slots.actions"
      class="flex items-start justify-between gap-4 px-6 pt-5 pb-4"
    >
      <div class="flex items-start gap-3 min-w-0">
        <span
          v-if="icon"
          class="flex items-center justify-center size-9 rounded-xl bg-n-brand/10 text-n-brand shrink-0"
        >
          <span :class="icon" class="size-5" />
        </span>
        <div class="min-w-0">
          <h3 class="text-sm font-semibold text-n-slate-12 leading-6">
            {{ title }}
          </h3>
          <p v-if="description" class="text-sm text-n-slate-11 mt-0.5">
            {{ description }}
          </p>
        </div>
      </div>
      <div v-if="$slots.actions" class="shrink-0">
        <slot name="actions" />
      </div>
    </header>
    <div class="px-6 pb-6" :class="{ 'pt-1': title }">
      <slot />
    </div>
  </section>
</template>
