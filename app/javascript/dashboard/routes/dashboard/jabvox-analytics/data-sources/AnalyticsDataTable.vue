<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  rows: {
    type: Array,
    default: () => [],
  },
  columns: {
    type: Array,
    default: () => [],
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['sort']);

const { t } = useI18n();

const columnNames = computed(() =>
  props.columns.map(col => (typeof col === 'string' ? col : col.name))
);

const cellValue = value => {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'object') return JSON.stringify(value);
  return value;
};
</script>

<template>
  <div class="overflow-x-auto rounded-lg border border-n-weak">
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-n-weak text-left text-n-slate-11">
          <th
            v-for="name in columnNames"
            :key="name"
            class="cursor-pointer whitespace-nowrap px-4 py-2.5 font-medium hover:text-n-slate-12"
            @click="emit('sort', name)"
          >
            {{ name }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-if="loading">
          <td
            :colspan="columnNames.length || 1"
            class="px-4 py-8 text-center text-n-slate-11"
          >
            <span
              class="i-lucide-loader-circle mr-2 inline-block size-4 animate-spin"
            />
            {{ t('JABVOX_ANALYTICS.COMMON.LOADING') }}
          </td>
        </tr>
        <tr v-else-if="!rows.length">
          <td
            :colspan="columnNames.length || 1"
            class="px-4 py-8 text-center text-n-slate-11"
          >
            {{ t('JABVOX_ANALYTICS.VIEWER.NO_ROWS') }}
          </td>
        </tr>
        <template v-else>
          <tr
            v-for="(row, index) in rows"
            :key="index"
            class="border-b border-n-weak last:border-b-0"
          >
            <td
              v-for="name in columnNames"
              :key="name"
              class="whitespace-nowrap px-4 py-2.5 text-n-slate-12"
            >
              {{ cellValue(row[name]) }}
            </td>
          </tr>
        </template>
      </tbody>
    </table>
  </div>
</template>
