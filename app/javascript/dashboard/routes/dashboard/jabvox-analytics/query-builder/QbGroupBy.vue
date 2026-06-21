<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  groupBy: {
    type: String,
    default: null,
  },
  dateBucket: {
    type: String,
    default: null,
  },
  columns: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:groupBy', 'update:dateBucket']);

const { t } = useI18n();

const BUCKETS = ['day', 'week', 'month', 'year'];

const controlClass =
  'block w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-strong';
</script>

<template>
  <div class="grid grid-cols-2 gap-3">
    <div>
      <label class="mb-1 block text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.GROUP_BY') }}
      </label>
      <select
        :value="groupBy"
        :class="controlClass"
        @change="emit('update:groupBy', $event.target.value || null)"
      >
        <option :value="null">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
        <option
          v-for="column in columns"
          :key="column.name"
          :value="column.name"
        >
          {{ column.name }}
        </option>
      </select>
    </div>
    <div>
      <label class="mb-1 block text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_ANALYTICS.QUERY_BUILDER.DATE_BUCKET') }}
      </label>
      <select
        :value="dateBucket"
        :class="controlClass"
        @change="emit('update:dateBucket', $event.target.value || null)"
      >
        <option :value="null">{{ t('JABVOX_ANALYTICS.COMMON.NONE') }}</option>
        <option v-for="bucket in BUCKETS" :key="bucket" :value="bucket">
          {{ bucket }}
        </option>
      </select>
    </div>
  </div>
</template>
