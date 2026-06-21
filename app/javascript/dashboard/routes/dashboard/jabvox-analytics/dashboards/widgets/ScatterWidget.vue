<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseChart from './BaseChart.vue';
import { useWidgetData } from './useWidgetData';

const props = defineProps({
  data: { type: Object, default: null },
});

const { t } = useI18n();
const { hasData, columns, rows } = useWidgetData(toRef(props, 'data'));

// Scatter uses the first two numeric columns as [x, y].
const points = computed(() =>
  rows.value.map(row => [Number(row[0] ?? 0), Number(row[1] ?? 0)])
);

const option = computed(() => ({
  tooltip: { trigger: 'item' },
  grid: { left: 48, right: 16, top: 24, bottom: 32 },
  xAxis: { type: 'value', name: columns.value[0] || '' },
  yAxis: { type: 'value', name: columns.value[1] || '' },
  series: [{ type: 'scatter', data: points.value, symbolSize: 8 }],
}));
</script>

<template>
  <BaseChart v-if="hasData" :option="option" />
  <div
    v-else
    class="flex size-full items-center justify-center text-sm text-n-slate-11"
  >
    {{ t('JABVOX_ANALYTICS.WIDGETS.NO_DATA') }}
  </div>
</template>
