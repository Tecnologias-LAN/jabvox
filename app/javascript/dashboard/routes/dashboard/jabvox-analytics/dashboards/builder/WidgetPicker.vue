<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

defineProps({
  open: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'select']);

const { t } = useI18n();

// Each entry maps a widget_type_jabvox value to an illustrative icon. Labels are
// resolved separately via static literal keys (see typeLabels) so the template
// binds plain strings rather than a dynamic key.
const WIDGET_TYPES = [
  { type: 'number', icon: 'i-lucide-hash' },
  { type: 'indicator', icon: 'i-lucide-activity' },
  { type: 'comparative', icon: 'i-lucide-arrow-up-down' },
  { type: 'ranking', icon: 'i-lucide-list-ordered' },
  { type: 'line', icon: 'i-lucide-line-chart' },
  { type: 'area', icon: 'i-lucide-area-chart' },
  { type: 'time_series', icon: 'i-lucide-trending-up' },
  { type: 'bar', icon: 'i-lucide-bar-chart-3' },
  { type: 'stacked_bar', icon: 'i-lucide-bar-chart-big' },
  { type: 'pie', icon: 'i-lucide-pie-chart' },
  { type: 'donut', icon: 'i-lucide-circle-dot' },
  { type: 'scatter', icon: 'i-lucide-scatter-chart' },
  { type: 'gauge', icon: 'i-lucide-gauge' },
  { type: 'heatmap', icon: 'i-lucide-grid-3x3' },
  { type: 'treemap', icon: 'i-lucide-layout-grid' },
  { type: 'funnel', icon: 'i-lucide-filter' },
  { type: 'map', icon: 'i-lucide-map' },
  { type: 'table', icon: 'i-lucide-table' },
  { type: 'pivot_table', icon: 'i-lucide-table-2' },
  { type: 'text_markdown', icon: 'i-lucide-type' },
];

// Labels resolved with static literal keys so the template binds plain strings.
const typeLabels = computed(() => ({
  number: t('JABVOX_ANALYTICS.WIDGETS.TYPES.number'),
  indicator: t('JABVOX_ANALYTICS.WIDGETS.TYPES.indicator'),
  comparative: t('JABVOX_ANALYTICS.WIDGETS.TYPES.comparative'),
  ranking: t('JABVOX_ANALYTICS.WIDGETS.TYPES.ranking'),
  line: t('JABVOX_ANALYTICS.WIDGETS.TYPES.line'),
  area: t('JABVOX_ANALYTICS.WIDGETS.TYPES.area'),
  time_series: t('JABVOX_ANALYTICS.WIDGETS.TYPES.time_series'),
  bar: t('JABVOX_ANALYTICS.WIDGETS.TYPES.bar'),
  stacked_bar: t('JABVOX_ANALYTICS.WIDGETS.TYPES.stacked_bar'),
  pie: t('JABVOX_ANALYTICS.WIDGETS.TYPES.pie'),
  donut: t('JABVOX_ANALYTICS.WIDGETS.TYPES.donut'),
  scatter: t('JABVOX_ANALYTICS.WIDGETS.TYPES.scatter'),
  gauge: t('JABVOX_ANALYTICS.WIDGETS.TYPES.gauge'),
  heatmap: t('JABVOX_ANALYTICS.WIDGETS.TYPES.heatmap'),
  treemap: t('JABVOX_ANALYTICS.WIDGETS.TYPES.treemap'),
  funnel: t('JABVOX_ANALYTICS.WIDGETS.TYPES.funnel'),
  map: t('JABVOX_ANALYTICS.WIDGETS.TYPES.map'),
  table: t('JABVOX_ANALYTICS.WIDGETS.TYPES.table'),
  pivot_table: t('JABVOX_ANALYTICS.WIDGETS.TYPES.pivot_table'),
  text_markdown: t('JABVOX_ANALYTICS.WIDGETS.TYPES.text_markdown'),
}));

// Resolve labels in script so the template binds plain strings (no dynamic keys).
const widgetTypes = computed(() =>
  WIDGET_TYPES.map(item => ({
    ...item,
    resolvedLabel: typeLabels.value[item.type],
  }))
);
</script>

<template>
  <div>
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-16"
    >
      <div
        class="w-full max-w-2xl rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <div class="mb-1 flex items-center justify-between">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.WIDGETS.PICKER.TITLE') }}
          </h3>
          <button
            type="button"
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>
        <p class="mb-4 text-sm text-n-slate-11">
          {{ t('JABVOX_ANALYTICS.WIDGETS.PICKER.SUBTITLE') }}
        </p>

        <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4">
          <button
            v-for="item in widgetTypes"
            :key="item.type"
            type="button"
            class="flex flex-col items-center gap-2 rounded-lg border border-n-weak bg-n-alpha-1 p-4 text-center hover:border-n-strong hover:bg-n-alpha-2"
            @click="emit('select', item.type)"
          >
            <span :class="item.icon" class="size-6 text-n-slate-11" />
            <span class="text-xs font-medium text-n-slate-12">
              {{ item.resolvedLabel }}
            </span>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
