<script setup>
import { watch, onBeforeUnmount } from 'vue';

// Right-side drawer: slides in from the right on desktop/tablet, full-screen on
// mobile. Header (title + close) is fixed, body scrolls, footer is pinned.
const props = defineProps({
  title: { type: String, default: '' },
});

defineEmits([]);
const open = defineModel('open', { type: Boolean, default: false });
const close = () => {
  open.value = false;
};

// Lock body scroll while open; close on Escape.
const onKeydown = e => {
  if (e.key === 'Escape') close();
};

watch(
  open,
  isOpen => {
    if (typeof document === 'undefined') return;
    if (isOpen) {
      document.addEventListener('keydown', onKeydown);
      document.body.style.overflow = 'hidden';
    } else {
      document.removeEventListener('keydown', onKeydown);
      document.body.style.overflow = '';
    }
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  document.removeEventListener('keydown', onKeydown);
  document.body.style.overflow = '';
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-200 ease-out"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-150 ease-in"
      leave-to-class="opacity-0"
    >
      <div
        v-if="open"
        class="fixed inset-0 z-50 bg-n-alpha-black2 backdrop-blur-[1px]"
        @click="close"
      />
    </Transition>
    <Transition
      enter-active-class="transition-transform duration-250 ease-out"
      enter-from-class="translate-x-full"
      leave-active-class="transition-transform duration-200 ease-in"
      leave-to-class="translate-x-full"
    >
      <aside
        v-if="open"
        role="dialog"
        aria-modal="true"
        :aria-label="props.title"
        class="fixed inset-y-0 right-0 z-50 flex w-full sm:max-w-[560px] flex-col bg-n-background shadow-2xl border-l border-n-weak"
      >
        <!-- Header -->
        <header
          class="flex items-center justify-between gap-3 border-b border-n-weak px-5 py-4 shrink-0"
        >
          <h2 class="text-base font-semibold text-n-slate-12 truncate">
            {{ title }}
          </h2>
          <button
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            @click="close"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </header>

        <!-- Body -->
        <div class="flex-1 overflow-y-auto px-5 py-5">
          <slot />
        </div>

        <!-- Footer -->
        <footer
          v-if="$slots.footer"
          class="border-t border-n-weak px-5 py-4 shrink-0 bg-n-solid-1"
        >
          <slot name="footer" />
        </footer>
      </aside>
    </Transition>
  </Teleport>
</template>
