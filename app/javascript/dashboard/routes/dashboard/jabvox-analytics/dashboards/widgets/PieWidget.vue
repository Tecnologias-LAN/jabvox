<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseChart from './BaseChart.vue';
import { useWidgetData } from './useWidgetData';

const props = defineProps({
  data: { type: Object, default: null },
});

const { t } = useI18n();
const { hasData, pairs } = useWidgetData(toRef(props, 'data'));

const option = computed(() => ({
  tooltip: { trigger: 'item' },
  legend: { type: 'scroll', bottom: 0 },
  series: [
    { type: 'pie', radius: '65%', center: ['50%', '45%'], data: pairs.value },
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
