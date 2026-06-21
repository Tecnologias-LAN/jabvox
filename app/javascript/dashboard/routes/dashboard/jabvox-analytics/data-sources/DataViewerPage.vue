<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useDebounceFn } from '@vueuse/core';
import { useAnalyticsQueryStore } from 'dashboard/stores/jabvox/analytics/query';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsDataTable from './AnalyticsDataTable.vue';

const { t } = useI18n();
const route = useRoute();
const store = useAnalyticsQueryStore();
const { showError } = useAnalyticsError();

const PER_PAGE_OPTIONS = [25, 50, 100, 250];

const dataSourceId = computed(() => route.params.dataSourceId);
const table = computed(() => route.query.table);

const search = ref('');
const perPage = ref(100);
const page = ref(1);
const sort = ref(null);

const rows = computed(() => store.result.rows);
const columns = computed(() => store.result.columns);
const total = computed(() => store.result.total);
const loading = computed(() => store.uiFlags.previewing);

const totalPages = computed(() =>
  perPage.value ? Math.max(1, Math.ceil(total.value / perPage.value)) : 1
);

const load = async () => {
  try {
    await store.previewTable(dataSourceId.value, {
      table: table.value,
      page: page.value,
      perPage: perPage.value,
      sort: sort.value,
      search: search.value,
    });
  } catch (error) {
    showError(error);
  }
};

const debouncedSearch = useDebounceFn(() => {
  page.value = 1;
  load();
}, 400);

const onSearchInput = () => {
  debouncedSearch();
};

const onPerPageChange = value => {
  perPage.value = Number(value);
  page.value = 1;
  load();
};

const onSort = column => {
  sort.value = sort.value === column ? `-${column}` : column;
  page.value = 1;
  load();
};

const changePage = delta => {
  const next = page.value + delta;
  if (next < 1 || next > totalPages.value) return;
  page.value = next;
  load();
};

onMounted(load);
</script>

<template>
  <div>
    <AnalyticsPageHeader :title="table || t('JABVOX_ANALYTICS.VIEWER.TITLE')" />

    <!-- Toolbar -->
    <div class="mb-4 flex flex-wrap items-center gap-3">
      <div class="relative min-w-0 flex-1">
        <span
          class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
        />
        <input
          v-model="search"
          type="text"
          class="block w-full rounded-lg border border-n-weak bg-n-alpha-1 py-2 pl-9 pr-3 text-sm text-n-slate-12 outline-none focus:border-n-strong"
          :placeholder="t('JABVOX_ANALYTICS.COMMON.SEARCH')"
          @input="onSearchInput"
        />
      </div>
      <label class="flex items-center gap-2 text-sm text-n-slate-11">
        {{ t('JABVOX_ANALYTICS.VIEWER.ROWS_PER_PAGE') }}
        <select
          :value="perPage"
          class="rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-1.5 text-sm text-n-slate-12 outline-none"
          @change="onPerPageChange($event.target.value)"
        >
          <option v-for="opt in PER_PAGE_OPTIONS" :key="opt" :value="opt">
            {{ opt }}
          </option>
        </select>
      </label>
    </div>

    <AnalyticsDataTable
      :rows="rows"
      :columns="columns"
      :loading="loading"
      @sort="onSort"
    />

    <!-- Pagination -->
    <div
      class="mt-4 flex items-center justify-center gap-4 text-sm text-n-slate-11"
    >
      <button
        type="button"
        class="rounded-lg bg-n-alpha-2 px-3 py-1.5 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="page <= 1 || loading"
        @click="changePage(-1)"
      >
        <span class="i-lucide-chevron-left size-4" />
      </button>
      <span>{{
        t('JABVOX_ANALYTICS.VIEWER.PAGE_OF', { page, total: totalPages })
      }}</span>
      <button
        type="button"
        class="rounded-lg bg-n-alpha-2 px-3 py-1.5 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="page >= totalPages || loading"
        @click="changePage(1)"
      >
        <span class="i-lucide-chevron-right size-4" />
      </button>
    </div>
  </div>
</template>
