<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import reportsAPI from 'dashboard/api/jabvox/reports';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import FilterBar from '../components/FilterBar.vue';
import KpiCard from '../components/KpiCard.vue';

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

const resetFilters = () => {
  filters.value = { date_from: '', date_to: '', doc_type: '', status: '' };
  fetch();
};

const docTypeOptions = computed(() => [
  { value: '', label: t('JABVOX_REPORTS.PRODUCTS.FILTER_ALL') },
  { value: 'QUOTE', label: t('JABVOX_REPORTS.PRODUCTS.FILTER_QUOTES') },
  { value: 'SALE', label: t('JABVOX_REPORTS.PRODUCTS.FILTER_SALES') },
]);

const statusOptions = computed(() => [
  { value: '', label: t('JABVOX_REPORTS.PRODUCTS.FILTER_ALL') },
  ...(orderStatusConfigs.value || []).map(s => ({
    value: s.key_jabvox,
    label: s.label_jabvox,
  })),
]);

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
  <div class="flex flex-col gap-5">
    <!-- Filters -->
    <FilterBar :loading="loading" @apply="fetch" @reset="resetFilters">
      <div class="flex flex-col gap-1.5 w-40">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_REPORTS.COMMON.FILTER_FROM') }}
        </label>
        <Input v-model="filters.date_from" type="date" size="sm" />
      </div>
      <div class="flex flex-col gap-1.5 w-40">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_REPORTS.COMMON.FILTER_TO') }}
        </label>
        <Input v-model="filters.date_to" type="date" size="sm" />
      </div>
      <div class="flex flex-col gap-1.5 w-44">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_REPORTS.PRODUCTS.FILTER_TYPE') }}
        </label>
        <Select v-model="filters.doc_type" :options="docTypeOptions" />
      </div>
      <div class="flex flex-col gap-1.5 w-44">
        <label class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_REPORTS.PRODUCTS.FILTER_STATUS') }}
        </label>
        <Select v-model="filters.status" :options="statusOptions" />
      </div>
    </FilterBar>

    <!-- Summary cards -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
      <KpiCard
        :label="t('JABVOX_REPORTS.PRODUCTS.STATS.TOTAL_ORDERS')"
        :value="totalOrders"
      />
      <KpiCard
        :label="t('JABVOX_REPORTS.PRODUCTS.STATS.TOTAL_QUOTES')"
        :value="totalQuotes"
        tone="amber"
      />
      <KpiCard
        :label="t('JABVOX_REPORTS.PRODUCTS.STATS.TOTAL_SALES')"
        :value="totalSales"
        tone="teal"
      />
      <KpiCard
        :label="t('JABVOX_REPORTS.PRODUCTS.STATS.TOTAL_REVENUE')"
        tone="brand"
      >
        {{ formatCurrency(totalRevenue) }}
      </KpiCard>
    </div>

    <!-- Loading -->
    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
      {{ t('JABVOX_REPORTS.COMMON.LOADING') }}
    </div>

    <!-- Table -->
    <div
      v-else-if="orders.length"
      class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
    >
      <div class="overflow-x-auto">
        <table class="min-w-full text-sm">
          <thead>
            <tr
              class="text-left text-xs font-medium uppercase tracking-wide text-n-slate-10 bg-n-alpha-1 border-b border-n-weak"
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
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="order in orders"
              :key="order.id"
              class="transition-colors"
              :class="
                order.lead_id || order.conversation_id
                  ? 'cursor-pointer hover:bg-n-alpha-2'
                  : 'hover:bg-n-alpha-1'
              "
              @click="goToLead(order)"
            >
              <td class="py-3 px-4 font-mono text-xs text-n-slate-10">
                #{{ order.id }}
              </td>
              <td class="py-3 px-4 text-n-slate-11 whitespace-nowrap">
                {{ formatDate(order.created_at) }}
              </td>
              <td class="py-3 px-4">
                <Label
                  :label="
                    order.doc_type === 'SALE'
                      ? t('JABVOX_REPORTS.PRODUCTS.BADGE.SALE')
                      : t('JABVOX_REPORTS.PRODUCTS.BADGE.QUOTE')
                  "
                  :color="order.doc_type === 'SALE' ? 'teal' : 'amber'"
                  compact
                />
              </td>
              <td class="py-3 px-4 text-n-slate-12 font-medium">
                {{ order.contact_name || '—' }}
              </td>
              <td class="py-3 px-4 text-n-slate-10 font-mono text-xs">
                {{ order.contact_phone || '—' }}
              </td>
              <td class="py-3 px-4 text-n-slate-11">
                {{ order.assignee_name || '—' }}
              </td>
              <td class="py-3 px-4">
                <span
                  class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11 font-medium"
                >
                  {{ order.status }}
                </span>
              </td>
              <td class="py-3 px-4 text-right text-n-slate-11">
                {{ formatCurrency(order.subtotal) }}
              </td>
              <td class="py-3 px-4 text-right text-n-slate-11">
                {{ formatCurrency(order.tax_total) }}
              </td>
              <td class="py-3 px-4 text-right font-semibold text-n-slate-12">
                {{ formatCurrency(order.total) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Empty -->
    <EmptyStateLayout
      v-else
      :title="t('JABVOX_REPORTS.COMMON.EMPTY_TITLE')"
      :subtitle="t('JABVOX_REPORTS.COMMON.EMPTY')"
    />
  </div>
</template>
