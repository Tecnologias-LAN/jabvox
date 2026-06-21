<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useWidgetData } from './useWidgetData';

const props = defineProps({
  data: { type: Object, default: null },
});

const { t } = useI18n();
const { hasData, rows } = useWidgetData(toRef(props, 'data'));

// Ranking: [label, value] rows sorted descending by value.
const ranked = computed(() =>
  [...rows.value]
    .map(row => ({ label: String(row[0]), value: Number(row[1] ?? 0) }))
    .sort((a, b) => b.value - a.value)
);

const maxValue = computed(() =>
  Math.max(1, ...ranked.value.map(item => item.value))
);
</script>

<template>
  <div v-if="hasData" class="flex size-full flex-col gap-2 overflow-y-auto p-1">
    <div
      v-for="(item, index) in ranked"
      :key="index"
      class="flex flex-col gap-1"
    >
      <div class="flex items-center justify-between text-sm">
        <span class="truncate text-n-slate-12">
          <span class="mr-1 text-n-slate-10">{{ `${index + 1}.` }}</span>
          {{ item.label }}
        </span>
        <span class="ml-2 shrink-0 font-medium text-n-slate-11">
          {{ item.value.toLocaleString() }}
        </span>
      </div>
      <div class="h-1.5 w-full overflow-hidden rounded-full bg-n-alpha-2">
        <div
          class="h-full rounded-full bg-n-brand"
          :style="{ width: `${(item.value / maxValue) * 100}%` }"
        />
      </div>
    </div>
  </div>
  <div
    v-else
    class="flex size-full items-center justify-center text-sm text-n-slate-11"
  >
    {{ t('JABVOX_ANALYTICS.WIDGETS.NO_DATA') }}
  </div>
</template>
