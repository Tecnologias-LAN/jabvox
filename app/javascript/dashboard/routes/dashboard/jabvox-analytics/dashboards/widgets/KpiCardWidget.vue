<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  data: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

// KPI takes the single value from the first row. If two columns are present we
// assume [label, value]; otherwise the only cell is the value.
const value = computed(() => {
  const row = props.data?.rows?.[0];
  if (!row) return null;
  return row.length > 1 ? row[row.length - 1] : row[0];
});

const label = computed(() => {
  const cols = props.data?.columns || [];
  return cols.length > 1 ? cols[cols.length - 1] : cols[0] || '';
});

const formatted = computed(() => {
  if (value.value === null || value.value === undefined) return '—';
  const num = Number(value.value);
  return Number.isNaN(num) ? value.value : num.toLocaleString();
});
</script>

<template>
  <div class="flex size-full flex-col items-center justify-center gap-1 p-2">
    <span class="text-3xl font-semibold text-n-slate-12">{{ formatted }}</span>
    <span v-if="label" class="text-xs text-n-slate-11">{{ label }}</span>
    <span v-if="value === null" class="text-xs text-n-slate-10">
      {{ t('JABVOX_ANALYTICS.WIDGETS.NO_DATA') }}
    </span>
  </div>
</template>
