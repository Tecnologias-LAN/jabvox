<script setup>
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: {
    type: Object,
    required: true,
  },
  columns: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue', 'remove']);

const { t } = useI18n();

// Aggregation functions are SQL keywords, not translatable copy.
const FUNCTIONS = ['COUNT', 'SUM', 'AVG', 'MIN', 'MAX'];

const update = (key, value) => {
  emit('update:modelValue', { ...props.modelValue, [key]: value });
};

const controlClass =
  'rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div class="flex items-center gap-2">
    <select
      :value="modelValue.fn"
      :class="controlClass"
      @change="update('fn', $event.target.value)"
    >
      <option v-for="fn in FUNCTIONS" :key="fn" :value="fn">{{ fn }}</option>
    </select>
    <select
      :value="modelValue.column"
      class="min-w-0 flex-1"
      :class="controlClass"
      @change="update('column', $event.target.value)"
    >
      <option :value="null" disabled>
        {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.COLUMNS') }}
      </option>
      <option v-for="column in columns" :key="column.name" :value="column.name">
        {{ column.name }}
      </option>
    </select>
    <button
      type="button"
      class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-2"
      @click="emit('remove')"
    >
      <span class="i-lucide-x size-4" />
    </button>
  </div>
</template>
