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

// Stacked bar supports [category, series1, series2, ...]; each measure column
// after the first becomes a stacked series. Falls back to a single series.
const categories = computed(() => rows.value.map(row => row[0]));
const measureCols = computed(() => columns.value.slice(1));

const option = computed(() => ({
  tooltip: { trigger: 'axis' },
  legend: {},
  grid: { left: 48, right: 16, top: 32, bottom: 32 },
  xAxis: { type: 'category', data: categories.value },
  yAxis: { type: 'value' },
  series: measureCols.value.map((name, index) => ({
    name,
    type: 'bar',
    stack: 'total',
    data: rows.value.map(row => Number(row[index + 1] ?? 0)),
  })),
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
