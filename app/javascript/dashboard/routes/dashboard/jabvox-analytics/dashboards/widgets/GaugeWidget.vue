<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseChart from './BaseChart.vue';
import { useWidgetData } from './useWidgetData';

const props = defineProps({
  widget: { type: Object, required: true },
  data: { type: Object, default: null },
});

const { t } = useI18n();
const { hasData, rows, columns } = useWidgetData(toRef(props, 'data'));

// Gauge shows a single measure. config_jabvox.max sets the scale if present.
const value = computed(() =>
  Number(rows.value?.[0]?.[1] ?? rows.value?.[0]?.[0] ?? 0)
);
const max = computed(() => Number(props.widget?.configJabvox?.max ?? 100));
const name = computed(() => columns.value[1] || columns.value[0] || '');

const option = computed(() => ({
  tooltip: { show: false },
  series: [
    {
      type: 'gauge',
      max: max.value,
      progress: { show: true },
      detail: { valueAnimation: true, formatter: '{value}' },
      data: [{ value: value.value, name: name.value }],
    },
  ],
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
