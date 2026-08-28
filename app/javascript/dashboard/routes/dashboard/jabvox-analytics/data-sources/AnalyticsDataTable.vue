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
  // Muestra una columna "#" que numera cada fila (respeta la paginación con rowOffset).
  showRowNumbers: {
    type: Boolean,
    default: false,
  },
  rowOffset: {
    type: Number,
    default: 0,
  },
});

const { t } = useI18n();

const columnNames = computed(() =>
  props.columns.map(col => (typeof col === 'string' ? col : col.name))
);

// colspan total considerando la columna "#" opcional.
const totalColspan = computed(
  () => columnNames.value.length + (props.showRowNumbers ? 1 : 0) || 1
);

const formatCell = value => {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'object') return JSON.stringify(value);
  return value;
};

// El backend devuelve cada fila como ARRAY de valores (mismo orden que columns). Se accede
// por índice. Si alguna vez viniera como objeto {col: valor}, se accede por nombre.
const cellAt = (row, name, index) => {
  const raw = Array.isArray(row) ? row[index] : row[name];
  return formatCell(raw);
};
</script>

<template>
  <div class="overflow-x-auto rounded-xl border border-n-weak shadow-sm">
    <table class="w-full border-collapse text-sm">
      <thead>
        <tr class="bg-n-alpha-2 text-left">
          <th
            v-if="showRowNumbers"
            class="sticky left-0 z-10 w-14 whitespace-nowrap border-b border-n-weak bg-n-alpha-2 px-3 py-3 text-right text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            :title="t('JABVOX_ANALYTICS.VIEWER.ROW_NUMBER')"
          >
            {{ '#' }}
          </th>
          <th
            v-for="name in columnNames"
            :key="name"
            class="whitespace-nowrap border-b border-n-weak px-4 py-3 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ name }}
          </th>
        </tr>
        <!-- Fila de filtros por columna (opcional, inyectada por el padre vía slot) -->
        <tr v-if="$slots.filters" class="bg-n-solid-1">
          <th
            v-if="showRowNumbers"
            class="sticky left-0 z-10 border-b border-n-weak bg-n-solid-1 px-3 py-2"
          />
          <th
            v-for="(name, colIndex) in columnNames"
            :key="`filter-${name}`"
            class="min-w-36 border-b border-n-weak px-2 py-2 align-top font-normal"
          >
            <slot name="filters" :column="name" :index="colIndex" />
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-if="loading">
          <td
            :colspan="totalColspan"
            class="px-4 py-10 text-center text-n-slate-11"
          >
            <span
              class="i-lucide-loader-circle mr-2 inline-block size-4 animate-spin"
            />
            {{ t('JABVOX_ANALYTICS.COMMON.LOADING') }}
          </td>
        </tr>
        <tr v-else-if="!rows.length">
          <td
            :colspan="totalColspan"
            class="px-4 py-10 text-center text-n-slate-10"
          >
            <span class="i-lucide-inbox mb-1 block text-2xl opacity-60" />
            {{ t('JABVOX_ANALYTICS.VIEWER.NO_ROWS') }}
          </td>
        </tr>
        <template v-else>
          <tr
            v-for="(row, index) in rows"
            :key="index"
            class="border-b border-n-weak/60 transition-colors last:border-b-0 odd:bg-n-alpha-1/40 hover:bg-n-brand/5"
          >
            <td
              v-if="showRowNumbers"
              class="sticky left-0 z-10 whitespace-nowrap bg-n-solid-1 px-3 py-2.5 text-right text-xs tabular-nums text-n-slate-10"
            >
              {{ rowOffset + index + 1 }}
            </td>
            <td
              v-for="(name, colIndex) in columnNames"
              :key="name"
              class="max-w-xs truncate whitespace-nowrap px-4 py-2.5 text-n-slate-12"
              :title="String(cellAt(row, name, colIndex))"
            >
              {{ cellAt(row, name, colIndex) }}
            </td>
          </tr>
        </template>
      </tbody>
    </table>
  </div>
</template>
