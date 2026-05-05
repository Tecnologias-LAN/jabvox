<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();

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
  { key: 'summary', label: 'JABVOX_PRODUCTS.SALES_REPORTS.TABS.SUMMARY' },
  { key: 'quotes', label: 'JABVOX_PRODUCTS.SALES_REPORTS.TABS.QUOTES' },
  { key: 'sales', label: 'JABVOX_PRODUCTS.SALES_REPORTS.TABS.SALES' },
];

const DOC_TYPES = [
  { value: '', label: 'JABVOX_PRODUCTS.SALES_REPORTS.FILTER_ALL' },
  { value: 'QUOTE', label: 'JABVOX_PRODUCTS.SALES_REPORTS.FILTER_QUOTES' },
  { value: 'SALE', label: 'JABVOX_PRODUCTS.SALES_REPORTS.FILTER_SALES' },
];

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
    useAlert(e.message || 'Error al cargar el reporte');
  }
};

const formatCurrency = val => {
  if (!val && val !== 0) return '—';
  return Number(val).toLocaleString('es-CO', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};

const formatDate = val => {
  if (!val) return '—';
  return new Date(val).toLocaleDateString();
};

onMounted(() => {
  store.dispatch('jabvoxProducts/fetchProduct');
  applyFilters();
});
</script>

<template>
  <div class="space-y-5 sm:space-y-6">
    <!-- Filters -->
    <div
      class="flex flex-col gap-3 p-4 sm:p-5 bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-800/60 dark:to-slate-800/40 rounded-xl border border-slate-200 dark:border-slate-700/60 shadow-sm"
    >
      <div class="flex flex-col sm:flex-row sm:flex-wrap items-start gap-3">
        <div class="flex flex-col gap-1">
          <label
            class="text-xs font-medium text-slate-600 dark:text-slate-400"
            >{{ $t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_FROM') }}</label>
          <input
            v-model="filters.date_from"
            type="date"
            class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label
            class="text-xs font-medium text-slate-600 dark:text-slate-400"
            >{{ $t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_TO') }}</label>
          <input
            v-model="filters.date_to"
            type="date"
            class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label
            class="text-xs font-medium text-slate-600 dark:text-slate-400"
            >{{ $t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_PRODUCT') }}</label>
          <select
            v-model="filters.jabvox_product_id"
            class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          >
            <option value="">
              {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_ALL') }}
            </option>
            <option v-for="p in products" :key="p.id" :value="p.id">
              {{ p.name_jabvox }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1">
          <label
            class="text-xs font-medium text-slate-600 dark:text-slate-400"
            >{{ $t('JABVOX_PRODUCTS.SALES_REPORTS.FILTER_TYPE') }}</label>
          <select
            v-model="filters.doc_type"
            class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          >
            <option v-for="dt in DOC_TYPES" :key="dt.value" :value="dt.value">
              {{ $t(dt.label) }}
            </option>
          </select>
        </div>
        <div class="flex items-end">
          <Button
            icon="i-lucide-search"
            :label="$t('JABVOX_PRODUCTS.SALES_REPORTS.APPLY')"
            :is-loading="uiFlags.isFetchingReports"
            @click="applyFilters"
          />
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetchingReports"
      class="text-sm text-slate-400 animate-pulse text-center py-12 sm:py-16"
    >
      {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.LOADING') }}
    </div>

    <template v-else>
      <!-- Inner tabs -->
      <div
        class="flex border-b border-slate-200 dark:border-slate-700 overflow-x-auto bg-white dark:bg-slate-800/30 pb-0"
      >
        <button
          v-for="tab in INNER_TABS"
          :key="tab.key"
          class="px-4 py-3 text-sm font-semibold border-b-2 whitespace-nowrap transition-all duration-200 relative -bottom-px"
          :class="[
            activeTab === tab.key
              ? 'border-woot-600 text-woot-600 dark:text-woot-400'
              : 'border-transparent text-slate-600 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200',
          ]"
          @click="activeTab = tab.key"
        >
          {{ $t(tab.label) }}
        </button>
      </div>

      <div class="mt-5 sm:mt-6">
        <!-- Summary tab -->
        <template v-if="activeTab === 'summary'">
          <!-- Stat cards -->
          <div
            class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 mb-5 sm:mb-6"
          >
            <div
              class="bg-gradient-to-br from-white to-slate-50 dark:from-slate-800 dark:to-slate-800/50 rounded-lg border border-slate-200 dark:border-slate-700 p-4 sm:p-5 space-y-2 shadow-sm hover:shadow-md transition-shadow duration-200"
            >
              <p class="text-xs text-slate-600 dark:text-slate-400 font-medium">
                {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.STATS.TOTAL_QUOTES') }}
              </p>
              <p
                class="text-3xl sm:text-3xl font-bold text-slate-900 dark:text-slate-50 tracking-tight"
              >
                {{ summary.total_quotes ?? '—' }}
              </p>
            </div>
            <div
              class="bg-gradient-to-br from-white to-slate-50 dark:from-slate-800 dark:to-slate-800/50 rounded-lg border border-slate-200 dark:border-slate-700 p-4 sm:p-5 space-y-2 shadow-sm hover:shadow-md transition-shadow duration-200"
            >
              <p class="text-xs text-slate-600 dark:text-slate-400 font-medium">
                {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.STATS.TOTAL_SALES') }}
              </p>
              <p
                class="text-3xl sm:text-3xl font-bold text-slate-900 dark:text-slate-50 tracking-tight"
              >
                {{ summary.total_sales ?? '—' }}
              </p>
            </div>
            <div
              class="bg-gradient-to-br from-white to-slate-50 dark:from-slate-800 dark:to-slate-800/50 rounded-lg border border-slate-200 dark:border-slate-700 p-4 sm:p-5 space-y-2 shadow-sm hover:shadow-md transition-shadow duration-200"
            >
              <p class="text-xs text-slate-600 dark:text-slate-400 font-medium">
                {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.STATS.TOTAL_REVENUE') }}
              </p>
              <p
                class="text-3xl sm:text-3xl font-bold text-slate-900 dark:text-slate-50 tracking-tight"
              >
                {{ formatCurrency(summary.total_revenue) }}
              </p>
            </div>
            <div
              class="bg-gradient-to-br from-white to-slate-50 dark:from-slate-800 dark:to-slate-800/50 rounded-lg border border-slate-200 dark:border-slate-700 p-4 sm:p-5 space-y-2 shadow-sm hover:shadow-md transition-shadow duration-200"
            >
              <p class="text-xs text-slate-600 dark:text-slate-400 font-medium">
                {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.STATS.CONVERSION') }}
              </p>
              <p
                class="text-3xl sm:text-3xl font-bold text-slate-900 dark:text-slate-50 tracking-tight"
              >
                {{
                  summary.conversion_rate != null
                    ? `${summary.conversion_rate}%`
                    : '—'
                }}
              </p>
            </div>
          </div>

          <!-- By Product -->
          <div
            v-if="byProduct.length"
            class="space-y-2 sm:space-y-3 mb-6 sm:mb-8"
          >
            <h3
              class="text-sm sm:text-base font-bold text-slate-900 dark:text-slate-50"
            >
              {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.BY_PRODUCT') }}
            </h3>
            <div
              class="overflow-x-auto rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800/50"
            >
              <table
                class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-xs sm:text-sm"
              >
                <thead class="bg-slate-50 dark:bg-slate-800/80">
                  <tr
                    class="text-left text-slate-600 dark:text-slate-300 font-semibold"
                  >
                    <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                      {{ $t('JABVOX_PRODUCTS.PRODUCTS.COLS.NAME') }}
                    </th>
                    <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                      {{
                        $t('JABVOX_PRODUCTS.SALES_REPORTS.STATS.TOTAL_SALES')
                      }}
                    </th>
                    <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                      {{
                        $t('JABVOX_PRODUCTS.SALES_REPORTS.STATS.TOTAL_REVENUE')
                      }}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
                  <tr
                    v-for="row in byProduct"
                    :key="row.product_id"
                    class="hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors duration-150"
                  >
                    <td
                      class="py-2 sm:py-3 px-4 sm:px-5 text-slate-900 dark:text-slate-50 font-medium"
                    >
                      {{ row.name }}
                    </td>
                    <td
                      class="py-2 sm:py-3 px-4 sm:px-5 text-slate-600 dark:text-slate-400"
                    >
                      {{ row.quantity }}
                    </td>
                    <td
                      class="py-2 sm:py-3 px-4 sm:px-5 text-slate-600 dark:text-slate-400 font-semibold"
                    >
                      {{ formatCurrency(row.revenue) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <!-- By Agent -->
          <div
            v-if="byAgent.length"
            class="space-y-2 sm:space-y-3 mb-6 sm:mb-8"
          >
            <h3
              class="text-sm sm:text-base font-bold text-slate-900 dark:text-slate-50"
            >
              {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.BY_AGENT') }}
            </h3>
            <div
              class="overflow-x-auto rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800/50"
            >
              <table
                class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-xs sm:text-sm"
              >
                <thead class="bg-slate-50 dark:bg-slate-800/80">
                  <tr
                    class="text-left text-slate-600 dark:text-slate-300 font-semibold"
                  >
                    <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                      {{ $t('JABVOX_PRODUCTS.REPORTS.COLS.AGENT') }}
                    </th>
                    <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                      {{
                        $t('JABVOX_PRODUCTS.SALES_REPORTS.STATS.TOTAL_SALES')
                      }}
                    </th>
                    <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                      {{
                        $t('JABVOX_PRODUCTS.SALES_REPORTS.STATS.TOTAL_REVENUE')
                      }}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
                  <tr
                    v-for="row in byAgent"
                    :key="row.agent_id"
                    class="hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors duration-150"
                  >
                    <td
                      class="py-2 sm:py-3 px-4 sm:px-5 text-slate-900 dark:text-slate-50 font-medium"
                    >
                      {{ row.name }}
                    </td>
                    <td
                      class="py-2 sm:py-3 px-4 sm:px-5 text-slate-600 dark:text-slate-400"
                    >
                      {{ row.count }}
                    </td>
                    <td
                      class="py-2 sm:py-3 px-4 sm:px-5 text-slate-600 dark:text-slate-400 font-semibold"
                    >
                      {{ formatCurrency(row.revenue) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <!-- By Status -->
          <div
            v-if="byStatus.length"
            class="space-y-2 sm:space-y-3 mb-6 sm:mb-8"
          >
            <h3
              class="text-sm sm:text-base font-bold text-slate-900 dark:text-slate-50"
            >
              {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.BY_STATUS') }}
            </h3>
            <div class="flex flex-wrap gap-2">
              <span
                v-for="row in byStatus"
                :key="row.status"
                class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-semibold bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-200 hover:bg-slate-200 dark:hover:bg-slate-600 transition-colors duration-150"
              >
                {{ row.label || row.status }}
                <span class="font-bold text-slate-900 dark:text-slate-50">{{
                  row.count
                }}</span>
              </span>
            </div>
          </div>

          <div
            v-if="!byProduct.length && !byAgent.length && !byStatus.length"
            class="text-sm text-slate-400 text-center py-8 sm:py-10"
          >
            {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.EMPTY') }}
          </div>
        </template>

        <!-- Quotes tab -->
        <template v-else-if="activeTab === 'quotes'">
          <div
            v-if="!quotes.length"
            class="text-sm text-slate-400 text-center py-8 sm:py-10"
          >
            {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.EMPTY') }}
          </div>
          <div
            v-else
            class="overflow-x-auto rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800/50"
          >
            <table
              class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-xs sm:text-sm"
            >
              <thead class="bg-slate-50 dark:bg-slate-800/80">
                <tr
                  class="text-left text-slate-600 dark:text-slate-300 font-semibold"
                >
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.ID') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.DATE') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.CONTACT') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.AGENT') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.STATUS') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.TOTAL') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
                <tr
                  v-for="order in quotes"
                  :key="order.id"
                  class="hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors duration-150"
                >
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-500 dark:text-slate-400 font-mono text-xs"
                  >
                    #{{ order.id }}
                  </td>
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-600 dark:text-slate-400"
                  >
                    {{ formatDate(order.date) }}
                  </td>
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-900 dark:text-slate-50"
                  >
                    {{ order.contact_name || '—' }}
                  </td>
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-600 dark:text-slate-400"
                  >
                    {{ order.agent_name || '—' }}
                  </td>
                  <td class="py-2 sm:py-3 px-4 sm:px-5">
                    <span
                      class="text-xs px-2 py-1 rounded-full font-semibold bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-300"
                    >
                      {{ order.status || '—' }}
                    </span>
                  </td>
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-900 dark:text-slate-50 font-semibold"
                  >
                    {{ formatCurrency(order.total) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>

        <!-- Sales tab -->
        <template v-else-if="activeTab === 'sales'">
          <div
            v-if="!sales.length"
            class="text-sm text-slate-400 text-center py-8 sm:py-10"
          >
            {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.EMPTY') }}
          </div>
          <div
            v-else
            class="overflow-x-auto rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800/50"
          >
            <table
              class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-xs sm:text-sm"
            >
              <thead class="bg-slate-50 dark:bg-slate-800/80">
                <tr
                  class="text-left text-slate-600 dark:text-slate-300 font-semibold"
                >
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.ID') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.DATE') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.CONTACT') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.AGENT') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.STATUS') }}
                  </th>
                  <th class="py-2 sm:py-3 px-4 sm:px-5 font-semibold">
                    {{ $t('JABVOX_PRODUCTS.SALES_REPORTS.COLS.TOTAL') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
                <tr
                  v-for="order in sales"
                  :key="order.id"
                  class="hover:bg-slate-50 dark:hover:bg-slate-800/50 transition-colors duration-150"
                >
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-500 dark:text-slate-400 font-mono text-xs"
                  >
                    #{{ order.id }}
                  </td>
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-600 dark:text-slate-400"
                  >
                    {{ formatDate(order.date) }}
                  </td>
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-900 dark:text-slate-50"
                  >
                    {{ order.contact_name || '—' }}
                  </td>
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-600 dark:text-slate-400"
                  >
                    {{ order.agent_name || '—' }}
                  </td>
                  <td class="py-2 sm:py-3 px-4 sm:px-5">
                    <span
                      class="text-xs px-2 py-1 rounded-full font-semibold bg-green-100/70 dark:bg-green-900/30 text-green-700 dark:text-green-300"
                    >
                      {{ order.status || '—' }}
                    </span>
                  </td>
                  <td
                    class="py-2 sm:py-3 px-4 sm:px-5 text-slate-900 dark:text-slate-50 font-semibold"
                  >
                    {{ formatCurrency(order.total) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
      </div>
    </template>
  </div>
</template>
