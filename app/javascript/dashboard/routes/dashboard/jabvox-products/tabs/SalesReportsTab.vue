<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const { t } = useI18n();

const salesReports = useMapGetter('jabvoxProducts/getSalesReports');
const products = useMapGetter('jabvoxProducts/getProducts');
const uiFlags = useMapGetter('jabvoxProducts/getUIFlags');

const activeTab = ref('summary');

const today = new Date().toISOString().slice(0, 10);
const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000)
  .toISOString()
  .slice(0, 10);

const filters = ref({
  date_from: thirtyDaysAgo,
  date_to: today,
  jabvox_product_id: '',
  doc_type: '',
});

const INNER_TABS = [
  {
    key: 'summary',
    label: 'JABVOX_PRODUCTS.SALES_REPORTS.TABS.SUMMARY',
    icon: 'i-lucide-layout-dashboard',
  },
  {
    key: 'quotes',
    label: 'JABVOX_PRODUCTS.SALES_REPORTS.TABS.QUOTES',
    icon: 'i-lucide-file-text',
  },
  {
    key: 'sales',
    label: 'JABVOX_PRODUCTS.SALES_REPORTS.TABS.SALES',
    icon: 'i-lucide-receipt',
  },
];

const productOptions = computed(() => [
  { value: '', label: t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_PRODUCT') },
  ...products.value.map(p => ({ value: p.id, label: p.name_jabvox })),
]);
const docTypeOptions = computed(() => [
  { value: '', label: t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_ALL') },
  { value: 'QUOTE', label: t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_QUOTES') },
  { value: 'SALE', label: t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_SALES') },
]);

const summary = computed(() => salesReports.value?.summary || {});
const orders = computed(() => salesReports.value?.orders || []);
const byProduct = computed(() => salesReports.value?.by_product || []);
const byAgent = computed(() => salesReports.value?.by_agent || []);
const byStatus = computed(() => salesReports.value?.by_status || []);

const quotes = computed(() => orders.value.filter(o => o.doc_type === 'QUOTE'));
const sales = computed(() => orders.value.filter(o => o.doc_type === 'SALE'));

const applyFilters = async () => {
  try {
    await store.dispatch('jabvoxProducts/fetchSalesReports', {
      ...filters.value,
    });
  } catch (e) {
    useAlert(e.message || t('JABVOX_PRODUCTS.ERROR'));
  }
};

const formatCurrency = val => {
  if (!val && val !== 0) return '—';
  return Number(val).toLocaleString('es-CO', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};
const formatDate = val => (val ? new Date(val).toLocaleDateString() : '—');

onMounted(() => {
  store.dispatch('jabvoxProducts/fetchProduct');
  applyFilters();
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- Filters -->
    <div
      class="flex flex-wrap items-end gap-3 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm p-4"
    >
      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_FROM') }}
        </label>
        <input
          v-model="filters.date_from"
          type="date"
          class="rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        />
      </div>
      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_TO') }}
        </label>
        <input
          v-model="filters.date_to"
          type="date"
          class="rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        />
      </div>
      <div class="flex flex-col gap-1.5 w-44">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_PRODUCT') }}
        </label>
        <Select v-model="filters.jabvox_product_id" :options="productOptions" />
      </div>
      <div class="flex flex-col gap-1.5 w-36">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_TYPE') }}
        </label>
        <Select v-model="filters.doc_type" :options="docTypeOptions" />
      </div>
      <Button
        :label="t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_APPLY')"
        icon="i-lucide-search"
        :is-loading="uiFlags.isFetchingReports"
        @click="applyFilters"
      />
    </div>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetchingReports"
      class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <template v-else>
      <!-- Inner tabs -->
      <div
        class="flex items-center gap-1 p-1 rounded-xl bg-n-alpha-1 border border-n-weak w-full sm:w-fit overflow-x-auto"
      >
        <button
          v-for="tab in INNER_TABS"
          :key="tab.key"
          class="flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition-colors flex-1 sm:flex-none"
          :class="
            activeTab === tab.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          <span :class="tab.icon" class="size-4 shrink-0" />
          {{ t(tab.label) }}
        </button>
      </div>

      <!-- ── SUMMARY ── -->
      <div v-if="activeTab === 'summary'" class="flex flex-col gap-6">
        <!-- KPIs -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
          <div
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <p class="text-2xl font-bold tabular-nums text-n-slate-12">
              {{ summary.total_quotes ?? 0 }}
            </p>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{ t('JABVOX_PRODUCTS.SALES_REPORTS.TOTAL_QUOTES') }}
            </p>
          </div>
          <div
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <p class="text-2xl font-bold tabular-nums text-n-teal-11">
              {{ summary.total_sales ?? 0 }}
            </p>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{ t('JABVOX_PRODUCTS.SALES_REPORTS.TOTAL_SALES') }}
            </p>
          </div>
          <div
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <p class="text-2xl font-bold tabular-nums text-n-brand">
              {{ formatCurrency(summary.total_revenue) }}
            </p>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{ t('JABVOX_PRODUCTS.SALES_REPORTS.TOTAL_REVENUE') }}
            </p>
          </div>
          <div
            class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <p class="text-2xl font-bold tabular-nums text-n-slate-12">
              {{ summary.conversion_rate ?? 0 }}%
            </p>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{ t('JABVOX_PRODUCTS.SALES_REPORTS.CONVERSION') }}
            </p>
          </div>
        </div>

        <!-- By product -->
        <div
          v-if="byProduct.length"
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden overflow-x-auto"
        >
          <table class="min-w-full text-sm">
            <thead
              class="bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
            >
              <tr>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.BY_PRODUCT') }}
                </th>
                <th class="text-right px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.QUANTITY') }}
                </th>
                <th class="text-right px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.REVENUE') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="row in byProduct"
                :key="row.product_id"
                class="hover:bg-n-alpha-1"
              >
                <td class="px-4 py-2.5 text-n-slate-12">{{ row.name }}</td>
                <td class="px-4 py-2.5 text-right tabular-nums text-n-slate-11">
                  {{ row.quantity }}
                </td>
                <td
                  class="px-4 py-2.5 text-right tabular-nums font-medium text-n-slate-12"
                >
                  {{ formatCurrency(row.revenue) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- By agent -->
        <div
          v-if="byAgent.length"
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden overflow-x-auto"
        >
          <table class="min-w-full text-sm">
            <thead
              class="bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
            >
              <tr>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.BY_AGENT') }}
                </th>
                <th class="text-right px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.QUANTITY') }}
                </th>
                <th class="text-right px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.REVENUE') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="row in byAgent"
                :key="row.agent_id"
                class="hover:bg-n-alpha-1"
              >
                <td class="px-4 py-2.5 text-n-slate-12">{{ row.name }}</td>
                <td class="px-4 py-2.5 text-right tabular-nums text-n-slate-11">
                  {{ row.count }}
                </td>
                <td
                  class="px-4 py-2.5 text-right tabular-nums font-medium text-n-slate-12"
                >
                  {{ formatCurrency(row.revenue) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- By status -->
        <div v-if="byStatus.length" class="flex flex-wrap gap-2">
          <Label
            v-for="row in byStatus"
            :key="row.status"
            :label="`${row.status}: ${row.count}`"
            color="slate"
          />
        </div>
      </div>

      <!-- ── QUOTES / SALES tables ── -->
      <div v-else>
        <div
          v-if="(activeTab === 'quotes' ? quotes : sales).length"
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden overflow-x-auto"
        >
          <table class="min-w-full text-sm">
            <thead
              class="bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
            >
              <tr>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.ID') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.DATE') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.CONTACT') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.AGENT') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.STATUS') }}
                </th>
                <th class="text-right px-4 py-2.5">
                  {{ t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.TOTAL') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="o in activeTab === 'quotes' ? quotes : sales"
                :key="o.id"
                class="hover:bg-n-alpha-1"
              >
                <td class="px-4 py-2.5 font-mono text-xs text-n-slate-11">
                  {{ o.id }}
                </td>
                <td class="px-4 py-2.5 text-n-slate-11 whitespace-nowrap">
                  {{ formatDate(o.created_at) }}
                </td>
                <td class="px-4 py-2.5 text-n-slate-12">
                  {{ o.contact_name }}
                </td>
                <td class="px-4 py-2.5 text-n-slate-11">{{ o.agent_name }}</td>
                <td class="px-4 py-2.5">
                  <Label
                    :label="o.status"
                    :color="activeTab === 'sales' ? 'teal' : 'slate'"
                    compact
                  />
                </td>
                <td
                  class="px-4 py-2.5 text-right tabular-nums font-semibold text-n-slate-12"
                >
                  {{ formatCurrency(o.total) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div
          v-else
          class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_PRODUCTS.SALES_REPORTS.NO_RESULTS') }}
        </div>
      </div>
    </template>
  </div>
</template>
