<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseChart from './BaseChart.vue';
import { useWidgetData } from './useWidgetData';

const props = defineProps({
  data: { type: Object, default: null },
});

const { t } = useI18n();
const { hasData, categories, series } = useWidgetData(toRef(props, 'data'));

const option = computed(() => ({
  tooltip: { trigger: 'axis' },
  legend: series.value.length > 1 ? { top: 0 } : undefined,
  grid: {
    left: 48,
    right: 16,
    top: series.value.length > 1 ? 32 : 24,
    bottom: 32,
  },
  xAxis: { type: 'category', data: categories.value, boundaryGap: false },
  yAxis: { type: 'value' },
  series: series.value.map(s => ({
    name: s.name,
    type: 'line',
    smooth: true,
    data: s.data,
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
