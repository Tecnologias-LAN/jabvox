<script setup>
import { computed } from 'vue';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import {
  BarChart,
  LineChart,
  PieChart,
  ScatterChart,
  HeatmapChart,
  TreemapChart,
  FunnelChart,
  GaugeChart,
} from 'echarts/charts';
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  TitleComponent,
  VisualMapComponent,
  DatasetComponent,
} from 'echarts/components';
import VChart from 'vue-echarts';

const props = defineProps({
  option: {
    type: Object,
    required: true,
  },
});

use([
  CanvasRenderer,
  BarChart,
  LineChart,
  PieChart,
  ScatterChart,
  HeatmapChart,
  TreemapChart,
  FunnelChart,
  GaugeChart,
  GridComponent,
  TooltipComponent,
  LegendComponent,
  TitleComponent,
  VisualMapComponent,
  DatasetComponent,
]);

// Detect dark mode once at render time; echarts re-renders when option changes.
const isDark = computed(
  () =>
    typeof document !== 'undefined' &&
    document.documentElement.classList.contains('dark')
);

// A readable palette that works on both light and dark backgrounds.
const palette = [
  '#3b82f6',
  '#14b8a6',
  '#f59e0b',
  '#ec4899',
  '#8b5cf6',
  '#22c55e',
  '#ef4444',
  '#06b6d4',
];

const axisColor = computed(() => (isDark.value ? '#64748b' : '#94a3b8'));
const textColor = computed(() => (isDark.value ? '#cbd5e1' : '#475569'));
const splitLineColor = computed(() =>
  isDark.value ? 'rgba(148,163,184,0.15)' : 'rgba(100,116,139,0.15)'
);

// Merge theme-aware defaults into the option supplied by each widget.
const themedOption = computed(() => {
  const base = {
    color: palette,
    textStyle: { color: textColor.value },
    tooltip: { trigger: 'item', confine: true },
    legend: { textStyle: { color: textColor.value } },
  };
  const merged = { ...base, ...props.option };

  ['xAxis', 'yAxis'].forEach(key => {
    if (merged[key]) {
      const apply = axis => ({
        ...axis,
        axisLine: { lineStyle: { color: axisColor.value } },
        axisLabel: { color: textColor.value },
        splitLine: { lineStyle: { color: splitLineColor.value } },
      });
      merged[key] = Array.isArray(merged[key])
        ? merged[key].map(apply)
        : apply(merged[key]);
    }
  });

  return merged;
});
</script>

<template>
  <VChart :option="themedOption" autoresize class="size-full min-h-[180px]" />
</template>
