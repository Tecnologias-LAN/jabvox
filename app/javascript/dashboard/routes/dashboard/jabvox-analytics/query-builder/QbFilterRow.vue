<script setup>
import { computed } from 'vue';
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

// Operator keys MUST match the backend QueryBuilderService OPERATOR_SQL exactly,
// or the filter is silently dropped server-side. ('in' is not supported;
// 'starts_with' is.)
const OPERATORS = [
  'eq',
  'neq',
  'gt',
  'gte',
  'lt',
  'lte',
  'contains',
  'starts_with',
];

// Operator labels resolved with static literal keys so the template binds plain
// strings (no dynamic i18n key). Unknown operators fall back to the raw value.
const operatorLabels = computed(() => ({
  eq: t('JABVOX_ANALYTICS.QUERY_BUILDER.OPERATORS.eq'),
  neq: t('JABVOX_ANALYTICS.QUERY_BUILDER.OPERATORS.neq'),
  gt: t('JABVOX_ANALYTICS.QUERY_BUILDER.OPERATORS.gt'),
  gte: t('JABVOX_ANALYTICS.QUERY_BUILDER.OPERATORS.gte'),
  lt: t('JABVOX_ANALYTICS.QUERY_BUILDER.OPERATORS.lt'),
  lte: t('JABVOX_ANALYTICS.QUERY_BUILDER.OPERATORS.lte'),
  contains: t('JABVOX_ANALYTICS.QUERY_BUILDER.OPERATORS.contains'),
  starts_with: t('JABVOX_ANALYTICS.QUERY_BUILDER.OPERATORS.starts_with'),
}));
const operatorLabel = op => operatorLabels.value[op] || op;

const update = (key, value) => {
  emit('update:modelValue', { ...props.modelValue, [key]: value });
};

const controlClass =
  'rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div class="flex items-center gap-2">
    <select
      :value="modelValue.field"
      class="min-w-0 flex-1"
      :class="controlClass"
      @change="update('field', $event.target.value)"
    >
      <option :value="null" disabled>
        {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.COLUMNS') }}
      </option>
      <option v-for="column in columns" :key="column.name" :value="column.name">
        {{ column.name }}
      </option>
    </select>
    <select
      :value="modelValue.operator"
      :class="controlClass"
      @change="update('operator', $event.target.value)"
    >
      <option v-for="op in OPERATORS" :key="op" :value="op">
        {{ operatorLabel(op) }}
      </option>
    </select>
    <input
      :value="modelValue.value"
      type="text"
      class="min-w-0 flex-1"
      :class="controlClass"
      @input="update('value', $event.target.value)"
    />
    <button
      type="button"
      class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-2"
      @click="emit('remove')"
    >
      <span class="i-lucide-x size-4" />
    </button>
  </div>
</template>
