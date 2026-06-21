<script setup>
import { computed, onMounted } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  contact: { type: Object, default: null },
  lead: { type: Object, default: null },
  size: { type: String, default: 'md' }, // 'sm' | 'md'
});

const store = useStore();

const buttons = computed(() => {
  try {
    return store.getters['jabvoxCustomization/getActiveButtons'] || [];
  } catch {
    return [];
  }
});

const resolveUrl = url => {
  if (!url) return '#';
  const contact = props.contact || props.lead?.contact || {};
  const lead = props.lead || {};
  return url
    .replace(/\{id\}/g, lead.id || contact.id || '')
    .replace(/\{phone\}/g, contact.phone_number || '')
    .replace(/\{email\}/g, contact.email || '')
    .replace(/\{firstName\}/g, (contact.name || '').split(' ')[0] || '');
};

onMounted(() => {
  try {
    if (!buttons.value.length) {
      store.dispatch('jabvoxCustomization/fetchButtons');
    }
  } catch {
    // store not ready yet
  }
});
</script>

<template>
  <div v-if="buttons.length" class="flex flex-wrap gap-1.5">
    <a
      v-for="btn in buttons"
      :key="btn.id"
      :href="resolveUrl(btn.url_jabvox)"
      target="_blank"
      rel="noopener noreferrer"
      class="inline-flex items-center gap-1 rounded-lg border text-white font-medium no-underline transition-opacity hover:opacity-80"
      :class="size === 'sm' ? 'px-2 py-0.5 text-xs' : 'px-3 py-1 text-xs'"
      :style="{ backgroundColor: btn.color_jabvox, borderColor: btn.color_jabvox }"
      :title="btn.url_jabvox"
    >
      <span class="i-lucide-external-link" :class="size === 'sm' ? 'size-3' : 'size-3.5'" />
      {{ btn.name_jabvox }}
    </a>
  </div>
</template>
