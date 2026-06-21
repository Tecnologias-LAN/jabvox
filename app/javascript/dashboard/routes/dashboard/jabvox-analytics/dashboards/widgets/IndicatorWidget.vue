<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useWidgetData } from './useWidgetData';

const props = defineProps({
  widget: { type: Object, required: true },
  data: { type: Object, default: null },
});

const { t } = useI18n();
const { hasData, rows, columns } = useWidgetData(toRef(props, 'data'));

const value = computed(() => {
  const row = rows.value[0];
  if (!row) return 0;
  return Number(row[row.length - 1] ?? 0);
});

const label = computed(() => columns.value[columns.value.length - 1] || '');

// Status thresholds from config_jabvox: green >= goodAbove, red <= badBelow.
const goodAbove = computed(() => props.widget?.configJabvox?.goodAbove);
const badBelow = computed(() => props.widget?.configJabvox?.badBelow);

const statusColor = computed(() => {
  if (goodAbove.value !== undefined && value.value >= Number(goodAbove.value)) {
    return 'text-n-teal-11';
  }
  if (badBelow.value !== undefined && value.value <= Number(badBelow.value)) {
    return 'text-n-ruby-11';
  }
  return 'text-n-slate-12';
});
</script>

<template>
  <div
    v-if="hasData"
    class="flex size-full flex-col items-center justify-center gap-1 p-2"
  >
    <span
      class="size-2.5 rounded-full"
      :class="statusColor.replace('text-', 'bg-')"
    />
    <span class="text-3xl font-semibold" :class="statusColor">
      {{ value.toLocaleString() }}
    </span>
    <span v-if="label" class="text-xs text-n-slate-11">{{ label }}</span>
  </div>
  <div
    v-else
    class="flex size-full items-center justify-center text-sm text-n-slate-11"
  >
    {{ t('JABVOX_ANALYTICS.WIDGETS.NO_DATA') }}
  </div>
</template>
