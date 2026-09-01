<script setup>
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Metric-specific filter bar, rendered from the backend filters_config plus the
// shared date range. Compact, matching the agents report FilterBar look. Each
// select's options come either inline (config.options) or from filter_options
// keyed by config.options_source (management_states / products).
const props = defineProps({
  filtersConfig: { type: Array, default: () => [] },
  filterOptions: { type: Object, default: () => ({}) },
  // Current values (v-model style, controlled by the parent).
  values: { type: Object, required: true },
  dateFrom: { type: String, default: '' },
  dateTo: { type: String, default: '' },
  loading: { type: Boolean, default: false },
});
const emit = defineEmits([
  'update:values',
  'update:dateFrom',
  'update:dateTo',
  'apply',
  'reset',
]);

const optionsFor = config => {
  if (config.options) return config.options;
  if (config.options_source)
    return props.filterOptions[config.options_source] || [];
  return [];
};

const setValue = (key, value) =>
  emit('update:values', { ...props.values, [key]: value });
</script>

<template>
  <div
    class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm flex flex-col gap-4"
  >
    <div class="flex items-center gap-2">
      <span class="i-lucide-sliders-horizontal size-4 text-n-slate-11" />
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('JABVOX_REPORTS.COMMON.FILTERS') }}
      </span>
    </div>
    <div class="flex flex-wrap items-end gap-3">
      <!-- Date range (always present) -->
      <div class="flex flex-col gap-1.5 w-40">
        <label class="text-xs font-medium text-n-slate-11">
          {{ $t('JABVOX_REPORTS.COMMON.FILTER_FROM') }}
        </label>
        <Input
          :model-value="dateFrom"
          type="date"
          size="sm"
          @update:model-value="emit('update:dateFrom', $event)"
        />
      </div>
      <div class="flex flex-col gap-1.5 w-40">
        <label class="text-xs font-medium text-n-slate-11">
          {{ $t('JABVOX_REPORTS.COMMON.FILTER_TO') }}
        </label>
        <Input
          :model-value="dateTo"
          type="date"
          size="sm"
          @update:model-value="emit('update:dateTo', $event)"
        />
      </div>

      <!-- Metric-specific selects -->
      <div
        v-for="config in filtersConfig"
        :key="config.key"
        class="flex flex-col gap-1.5 w-44"
      >
        <label class="text-xs font-medium text-n-slate-11">{{
          config.label
        }}</label>
        <select
          :value="values[config.key] || ''"
          class="h-9 rounded-lg border border-n-weak bg-n-solid-1 px-2.5 text-sm text-n-slate-12"
          @change="setValue(config.key, $event.target.value)"
        >
          <option value="">
            {{ $t('JABVOX_REPORTS.PRODUCTS.FILTER_ALL') }}
          </option>
          <option
            v-for="opt in optionsFor(config)"
            :key="opt.value"
            :value="opt.value"
          >
            {{ opt.label }}
          </option>
        </select>
      </div>

      <div class="flex items-center gap-2 ml-auto">
        <Button
          :label="$t('JABVOX_REPORTS.COMMON.APPLY')"
          icon="i-lucide-search"
          size="sm"
          :is-loading="loading"
          @click="emit('apply')"
        />
        <Button
          :label="$t('JABVOX_REPORTS.COMMON.RESET')"
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="sm"
          @click="emit('reset')"
        />
      </div>
    </div>
  </div>
</template>
