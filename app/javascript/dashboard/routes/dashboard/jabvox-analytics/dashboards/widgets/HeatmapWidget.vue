<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseChart from './BaseChart.vue';
import { useWidgetData } from './useWidgetData';

const props = defineProps({
  data: { type: Object, default: null },
});

const { t } = useI18n();
const { hasData, rows, columns } = useWidgetData(toRef(props, 'data'));

// Heatmap expects rows of [xCategory, yCategory, value].
const xCats = computed(() => [...new Set(rows.value.map(r => String(r[0])))]);
const yCats = computed(() => [...new Set(rows.value.map(r => String(r[1])))]);

const points = computed(() =>
  rows.value.map(r => [
    xCats.value.indexOf(String(r[0])),
    yCats.value.indexOf(String(r[1])),
    Number(r[2] ?? 0),
  ])
);

const maxValue = computed(() =>
  Math.max(1, ...rows.value.map(r => Number(r[2] ?? 0)))
);

const option = computed(() => ({
  tooltip: { position: 'top' },
  grid: { left: 60, right: 16, top: 16, bottom: 48 },
  xAxis: { type: 'category', data: xCats.value, name: columns.value[0] || '' },
  yAxis: { type: 'category', data: yCats.value, name: columns.value[1] || '' },
  visualMap: {
    min: 0,
    max: maxValue.value,
    calculable: true,
    orient: 'horizontal',
    left: 'center',
    bottom: 0,
  },
  series: [{ type: 'heatmap', data: points.value }],
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
