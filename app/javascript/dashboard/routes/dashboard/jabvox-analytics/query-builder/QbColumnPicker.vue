<script setup>
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: {
    type: Array,
    default: () => [],
  },
  columns: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const toggle = name => {
  const next = props.modelValue.includes(name)
    ? props.modelValue.filter(item => item !== name)
    : [...props.modelValue, name];
  emit('update:modelValue', next);
};
</script>

<template>
  <div>
    <label class="mb-1 block text-sm font-medium text-n-slate-12">
      {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.COLUMNS') }}
    </label>
    <p v-if="!columns.length" class="text-sm text-n-slate-10">
      {{ t('JABVOX_ANALYTICS.COMMON.NONE') }}
    </p>
    <div v-else class="flex max-h-48 flex-col gap-1.5 overflow-y-auto">
      <label
        v-for="column in columns"
        :key="column.name"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <input
          type="checkbox"
          class="size-4 rounded border-n-weak"
          :checked="modelValue.includes(column.name)"
          @change="toggle(column.name)"
        />
        {{ column.name }}
        <span class="text-xs text-n-slate-10">{{ column.type }}</span>
      </label>
    </div>
  </div>
</template>
