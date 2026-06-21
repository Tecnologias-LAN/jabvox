<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

// Renders the current dynamic filter chips and lets the user add/remove simple
// key=value chips. Emits update:modelValue with the full dynamic map.
const props = defineProps({
  modelValue: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const newKey = ref('');
const newValue = ref('');

const addChip = () => {
  const key = newKey.value.trim();
  if (!key) return;
  emit('update:modelValue', { ...props.modelValue, [key]: newValue.value });
  newKey.value = '';
  newValue.value = '';
};

const removeChip = key => {
  const next = { ...props.modelValue };
  delete next[key];
  emit('update:modelValue', next);
};

const inputClass =
  'rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <span
      v-for="(value, key) in modelValue"
      :key="key"
      class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs text-n-slate-12"
    >
      {{ t('JABVOX_ANALYTICS.FILTERS.CHIP', { key, value }) }}
      <button
        type="button"
        class="text-n-slate-11 hover:text-n-slate-12"
        @click="removeChip(key)"
      >
        <span class="i-lucide-x size-3" />
      </button>
    </span>
    <input
      v-model="newKey"
      type="text"
      class="w-24"
      :class="inputClass"
      :placeholder="t('JABVOX_ANALYTICS.COMMON.NAME')"
    />
    <input
      v-model="newValue"
      type="text"
      class="w-24"
      :class="inputClass"
      :placeholder="t('JABVOX_ANALYTICS.FILTERS.APPLY')"
      @keyup.enter="addChip"
    />
    <button
      type="button"
      class="rounded-lg bg-n-alpha-2 p-1.5 text-n-slate-12 hover:bg-n-alpha-3"
      @click="addChip"
    >
      <span class="i-lucide-plus size-4" />
    </button>
  </div>
</template>
