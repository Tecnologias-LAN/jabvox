<script setup>
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';
import DynamicFilterControl from './DynamicFilterControl.vue';

const emit = defineEmits(['apply']);

const { t } = useI18n();
const store = useAnalyticsDashboardsStore();

// Local working copy of the global filters; committed to the store on Apply.
const local = reactive({
  dateFrom: store.globalFilters.dateFrom || '',
  dateTo: store.globalFilters.dateTo || '',
  dynamic: { ...(store.globalFilters.dynamic || {}) },
});

watch(
  () => store.globalFilters,
  filters => {
    local.dateFrom = filters.dateFrom || '';
    local.dateTo = filters.dateTo || '';
    local.dynamic = { ...(filters.dynamic || {}) };
  }
);

const apply = () => {
  store.setGlobalFilters({
    dateFrom: local.dateFrom || null,
    dateTo: local.dateTo || null,
    dynamic: local.dynamic,
  });
  emit('apply');
};

const clear = () => {
  local.dateFrom = '';
  local.dateTo = '';
  local.dynamic = {};
  apply();
};

const labelClass = 'text-xs font-medium text-n-slate-11';
const inputClass =
  'rounded-lg border border-n-weak bg-n-alpha-1 px-2.5 py-1.5 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div
    class="mb-4 flex flex-wrap items-end gap-3 rounded-lg border border-n-weak bg-n-solid-1 p-3"
  >
    <div class="flex flex-col gap-1">
      <span :class="labelClass">{{
        t('JABVOX_ANALYTICS.FILTERS.DATE_FROM')
      }}</span>
      <input v-model="local.dateFrom" type="date" :class="inputClass" />
    </div>
    <div class="flex flex-col gap-1">
      <span :class="labelClass">{{
        t('JABVOX_ANALYTICS.FILTERS.DATE_TO')
      }}</span>
      <input v-model="local.dateTo" type="date" :class="inputClass" />
    </div>
    <div class="flex min-w-0 flex-1 flex-col gap-1">
      <span :class="labelClass">{{ t('JABVOX_ANALYTICS.COMMON.SEARCH') }}</span>
      <DynamicFilterControl v-model="local.dynamic" />
    </div>
    <div class="flex items-center gap-2">
      <button
        type="button"
        class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
        @click="clear"
      >
        {{ t('JABVOX_ANALYTICS.FILTERS.CLEAR') }}
      </button>
      <button
        type="button"
        class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white"
        @click="apply"
      >
        {{ t('JABVOX_ANALYTICS.FILTERS.APPLY') }}
      </button>
    </div>
  </div>
</template>
