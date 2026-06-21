<script setup>
import { computed } from 'vue';
import { useAnalyticsWidgetsStore } from 'dashboard/stores/jabvox/analytics/widgets';

import TableWidget from '../widgets/TableWidget.vue';
import PivotTableWidget from '../widgets/PivotTableWidget.vue';
import KpiCardWidget from '../widgets/KpiCardWidget.vue';
import IndicatorWidget from '../widgets/IndicatorWidget.vue';
import RankingWidget from '../widgets/RankingWidget.vue';
import ComparativeWidget from '../widgets/ComparativeWidget.vue';
import LineWidget from '../widgets/LineWidget.vue';
import AreaWidget from '../widgets/AreaWidget.vue';
import TimeSeriesWidget from '../widgets/TimeSeriesWidget.vue';
import BarWidget from '../widgets/BarWidget.vue';
import StackedBarWidget from '../widgets/StackedBarWidget.vue';
import PieWidget from '../widgets/PieWidget.vue';
import DonutWidget from '../widgets/DonutWidget.vue';
import ScatterWidget from '../widgets/ScatterWidget.vue';
import GaugeWidget from '../widgets/GaugeWidget.vue';
import HeatmapWidget from '../widgets/HeatmapWidget.vue';
import TreemapWidget from '../widgets/TreemapWidget.vue';
import FunnelWidget from '../widgets/FunnelWidget.vue';
import MapWidget from '../widgets/MapWidget.vue';
import TextMarkdownWidget from '../widgets/TextMarkdownWidget.vue';

const props = defineProps({
  widget: {
    type: Object,
    required: true,
  },
});

const widgetsStore = useAnalyticsWidgetsStore();

// Maps each widget_type_jabvox value to its renderer component.
const TYPE_MAP = {
  table: TableWidget,
  pivot_table: PivotTableWidget,
  number: KpiCardWidget,
  indicator: IndicatorWidget,
  ranking: RankingWidget,
  comparative: ComparativeWidget,
  line: LineWidget,
  area: AreaWidget,
  time_series: TimeSeriesWidget,
  bar: BarWidget,
  stacked_bar: StackedBarWidget,
  pie: PieWidget,
  donut: DonutWidget,
  scatter: ScatterWidget,
  gauge: GaugeWidget,
  heatmap: HeatmapWidget,
  treemap: TreemapWidget,
  funnel: FunnelWidget,
  map: MapWidget,
  text_markdown: TextMarkdownWidget,
};

const component = computed(
  () => TYPE_MAP[props.widget.widgetTypeJabvox] || TableWidget
);

const data = computed(() => widgetsStore.dataFor(props.widget.id));
</script>

<template>
  <component :is="component" :widget="widget" :data="data" />
</template>
