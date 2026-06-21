<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useWidgetData } from './useWidgetData';

const props = defineProps({
  data: { type: Object, default: null },
});

const { t } = useI18n();
const { hasData, rows, columns } = useWidgetData(toRef(props, 'data'));

// Compares two values. Reads the current and previous from the first row's last
// two columns (e.g. [label, current, previous]) or two rows of a single measure.
const current = computed(() => {
  const row = rows.value[0];
  if (!row) return 0;
  return Number(row[row.length >= 3 ? 1 : row.length - 1] ?? 0);
});

const previous = computed(() => {
  const first = rows.value[0];
  if (first && first.length >= 3) return Number(first[2] ?? 0);
  const second = rows.value[1];
  return second ? Number(second[second.length - 1] ?? 0) : 0;
});

const delta = computed(() => current.value - previous.value);
const deltaPct = computed(() =>
  previous.value === 0 ? null : (delta.value / Math.abs(previous.value)) * 100
);
const isUp = computed(() => delta.value >= 0);
const label = computed(() => columns.value[0] || '');
const deltaDisplay = computed(() =>
  deltaPct.value === null
    ? delta.value.toLocaleString()
    : `${deltaPct.value.toFixed(1)}%`
);
</script>

<template>
  <div
    v-if="hasData"
    class="flex size-full flex-col items-center justify-center gap-1 p-2"
  >
    <span v-if="label" class="text-xs text-n-slate-11">{{ label }}</span>
    <span class="text-3xl font-semibold text-n-slate-12">
      {{ current.toLocaleString() }}
    </span>
    <span
      class="flex items-center gap-1 text-sm font-medium"
      :class="isUp ? 'text-n-teal-11' : 'text-n-ruby-11'"
    >
      <span
        :class="isUp ? 'i-lucide-trending-up' : 'i-lucide-trending-down'"
        class="size-4"
      />
      {{ deltaDisplay }}
    </span>
    <span class="text-xs text-n-slate-10">
      {{
        isUp
          ? t('JABVOX_ANALYTICS.WIDGETS.DELTA_UP')
          : t('JABVOX_ANALYTICS.WIDGETS.DELTA_DOWN')
      }}
    </span>
  </div>
  <div
    v-else
    class="flex size-full items-center justify-center text-sm text-n-slate-11"
  >
    {{ t('JABVOX_ANALYTICS.WIDGETS.NO_DATA') }}
  </div>
</template>
