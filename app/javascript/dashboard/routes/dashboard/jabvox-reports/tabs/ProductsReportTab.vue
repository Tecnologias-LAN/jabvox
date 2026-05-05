<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import reportsAPI from 'dashboard/api/jabvox/reports';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const orderStatusConfigs = useMapGetter('jabvoxProducts/getOrderStatusConfigs');

const loading = ref(false);
const orders = ref([]);

const filters = ref({
  date_from: '',
  date_to: '',
  doc_type: '',
  status: '',
});

const totalOrders = computed(() => orders.value.length);
const totalQuotes = computed(
  () => orders.value.filter(o => o.doc_type === 'QUOTE').length
);
const totalSales = computed(
  () => orders.value.filter(o => o.doc_type === 'SALE').length
);
const totalRevenue = computed(() =>
  orders.value.reduce((s, o) => s + parseFloat(o.total || 0), 0)
);

const fetch = async () => {
  loading.value = true;
  try {
    const { data } = await reportsAPI.getProducts(filters.value);
    orders.value = data.orders || [];
  } catch {
    orders.value = [];
  } finally {
    loading.value = false;
  }
};

const formatCurrency = val =>
  Number(val || 0).toLocaleString('es-CO', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

const formatDate = val => {
  if (!val) return '—';
  return new Date(val).toISOString().slice(0, 10);
};

const goToLead = order => {
  if (order.lead_id) {
    router.push({
      name: 'jabvox_lead_detail',
      params: { accountId: route.params.accountId, leadId: order.lead_id },
      query: { tab: 'products' },
    });
  } else if (order.conversation_id) {
    router.push({
      name: 'inbox_conversation',
      params: {
        accountId: route.params.accountId,
        conversation_id: order.conversation_id,
      },
    });
  }
};

onMounted(async () => {
  store.dispatch('jabvoxProducts/fetchStatus');
  await fetch();
});
</script>

<template>
  <div class="space-y-5">
    <!-- Filters -->
    <div
      class="flex flex-wrap gap-3 p-4 bg-slate-50 dark:bg-slate-800/60 rounded-xl border border-slate-200 dark:border-slate-700"
    >
      <div class="flex flex-col gap-1">
        <label class="text-xs font-medium text-slate-600 dark:text-slate-400">{{
          t('JABVOX_REPORTS.COMMON.FILTER_FROM')
        }}</label>
        <input
          v-model="filters.date_from"
          type="date"
          class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs font-medium text-slate-600 dark:text-slate-400">{{
          t('JABVOX_REPORTS.COMMON.FILTER_TO')
        }}</label>
        <input
          v-model="filters.date_to"
          type="date"
          class="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs font-medium text-slate-600 dark:text-slate-400">{{
          t('JABVOX_REPORTS.PRODUCTS.FILTER_TYPE')
        }}</label>
        <div class="relative">
          <select
            v-model="filters.doc_type"
            class="appearance-none w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm pl-3 pr-8 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
          >
            <option value="">
              {{ t('JABVOX_REPORTS.PRODUCTS.FILTER_ALL') }}
            </option>
            <option value="QUOTE">
              {{ t('JABVOX_REPORTS.PRODUCTS.FILTER_QUOTES') }}
            </option>
            <option value="SALE">
              {{ t('JABVOX_REPORTS.PRODUCTS.FILTER_SALES') }}
            </option>
          </select>
          <span
            class="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 i-lucide-chevron-down w-4 h-4 text-slate-400"
          />
        </div>
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs font-medium text-slate-600 dark:text-slate-400">{{
          t('JABVOX_REPORTS.PRODUCTS.FILTER_STATUS')
        }}</label>
        <div class="relative">
          <select
            v-model="filters.status"
            class="appearance-none w-full rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm pl-3 pr-8 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 text-slate-700 dark:text-slate-200"
          >
            <option value="">
              {{ t('JABVOX_REPORTS.PRODUCTS.FILTER_ALL') }}
            </option>
            <option
              v-for="s in orderStatusConfigs"
              :key="s.key_jabvox"
              :value="s.key_jabvox"
            >
              {{ s.label_jabvox }}
            </option>
          </select>
          <span
            class="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 i-lucide-chevron-down w-4 h-4 text-slate-400"
          />
        </div>
      </div>
      <div class="flex items-end">
        <button
          :disabled="loading"
          class="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium disabled:opacity-50 transition-colors"
          @click="fetch"
        >
          <span class="i-lucide-search w-4 h-4" />
          {{ t('JABVOX_REPORTS.COMMON.APPLY') }}
        </button>
      </div>
    </div>

    <!-- Summary cards -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-1 shadow-sm"
      >
        <p class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          {{ t('JABVOX_REPORTS.PRODUCTS.STATS.TOTAL_ORDERS') }}
        </p>
        <p class="text-2xl font-bold text-slate-900 dark:text-slate-50">
          {{ totalOrders }}
        </p>
      </div>
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-1 shadow-sm"
      >
        <p class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          {{ t('JABVOX_REPORTS.PRODUCTS.STATS.TOTAL_QUOTES') }}
        </p>
        <p class="text-2xl font-bold text-amber-600 dark:text-amber-400">
          {{ totalQuotes }}
        </p>
      </div>
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-1 shadow-sm"
      >
        <p class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          {{ t('JABVOX_REPORTS.PRODUCTS.STATS.TOTAL_SALES') }}
        </p>
        <p class="text-2xl font-bold text-green-600 dark:text-green-400">
          {{ totalSales }}
        </p>
      </div>
      <div
        class="bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4 space-y-1 shadow-sm"
      >
        <p class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          {{ t('JABVOX_REPORTS.PRODUCTS.STATS.TOTAL_REVENUE') }}
        </p>
        <p class="text-xl font-bold text-woot-600 dark:text-woot-400">
          {{ formatCurrency(totalRevenue) }}
        </p>
      </div>
    </div>

    <!-- Loading -->
    <div
      v-if="loading"
      class="text-sm text-slate-400 animate-pulse text-center py-16"
    >
      {{ t('JABVOX_REPORTS.COMMON.LOADING') }}
    </div>

    <!-- Table -->
    <div
      v-else-if="orders.length"
      class="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800/50 shadow-sm"
    >
      <table
        class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
      >
        <thead class="bg-slate-50 dark:bg-slate-800/80">
          <tr
            class="text-left text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wide"
          >
            <th class="py-3 px-4">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.ID') }}
            </th>
            <th class="py-3 px-4">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.DATE') }}
            </th>
            <th class="py-3 px-4">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.TYPE') }}
            </th>
            <th class="py-3 px-4">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.CONTACT') }}
            </th>
            <th class="py-3 px-4">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.PHONE') }}
            </th>
            <th class="py-3 px-4">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.ASSIGNEE') }}
            </th>
            <th class="py-3 px-4">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.STATUS') }}
            </th>
            <th class="py-3 px-4 text-right">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.SUBTOTAL') }}
            </th>
            <th class="py-3 px-4 text-right">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.TAX') }}
            </th>
            <th class="py-3 px-4 text-right">
              {{ t('JABVOX_REPORTS.PRODUCTS.COLS.TOTAL') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100 dark:divide-slate-800">
          <tr
            v-for="order in orders"
            :key="order.id"
            class="transition-colors"
            :class="
              order.lead_id || order.conversation_id
                ? 'cursor-pointer hover:bg-woot-50 dark:hover:bg-woot-900/20'
                : 'hover:bg-slate-50 dark:hover:bg-slate-800/50'
            "
            @click="goToLead(order)"
          >
            <td class="py-3 px-4 font-mono text-xs text-slate-400">
              #{{ order.id }}
            </td>
            <td
              class="py-3 px-4 text-slate-600 dark:text-slate-400 whitespace-nowrap"
            >
              {{ formatDate(order.created_at) }}
            </td>
            <td class="py-3 px-4">
              <span
                class="text-xs px-2 py-0.5 rounded-full font-semibold"
                :class="
                  order.doc_type === 'SALE'
                    ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300'
                    : 'bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300'
                "
              >
                {{
                  order.doc_type === 'SALE'
                    ? t('JABVOX_REPORTS.PRODUCTS.BADGE.SALE')
                    : t('JABVOX_REPORTS.PRODUCTS.BADGE.QUOTE')
                }}
              </span>
            </td>
            <td class="py-3 px-4 text-slate-900 dark:text-slate-50 font-medium">
              {{ order.contact_name || '—' }}
            </td>
            <td
              class="py-3 px-4 text-slate-500 dark:text-slate-400 font-mono text-xs"
            >
              {{ order.contact_phone || '—' }}
            </td>
            <td class="py-3 px-4 text-slate-700 dark:text-slate-300">
              {{ order.assignee_name || '—' }}
            </td>
            <td class="py-3 px-4">
              <span
                class="text-xs px-2 py-0.5 rounded-full bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 font-medium"
              >
                {{ order.status }}
              </span>
            </td>
            <td class="py-3 px-4 text-right text-slate-600 dark:text-slate-400">
              {{ formatCurrency(order.subtotal) }}
            </td>
            <td class="py-3 px-4 text-right text-slate-600 dark:text-slate-400">
              {{ formatCurrency(order.tax_total) }}
            </td>
            <td
              class="py-3 px-4 text-right font-semibold text-slate-900 dark:text-slate-50"
            >
              {{ formatCurrency(order.total) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Empty -->
    <div v-else class="text-sm text-slate-400 text-center py-16">
      {{ t('JABVOX_REPORTS.COMMON.EMPTY') }}
    </div>
  </div>
</template>
