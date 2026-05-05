<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import affiliatePortalAPI from '../../api/jabvox/affiliatePortal';

const { t } = useI18n();

const isLoading = ref(false);
const errorMsg = ref('');
const leads = ref([]);
const currentPage = ref(1);
const totalPages = ref(1);

const fetchLeads = async (page = 1) => {
  isLoading.value = true;
  errorMsg.value = '';
  try {
    const { data } = await affiliatePortalAPI.getLeads(page);
    leads.value = data.leads ?? [];
    currentPage.value = data.meta?.current_page ?? page;
    totalPages.value = data.meta?.total_pages ?? 1;
  } catch {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.LEADS_ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => fetchLeads(1));

const goToPage = p => {
  if (p >= 1 && p <= totalPages.value) fetchLeads(p);
};

const formatCurrency = amount => {
  if (amount == null) return '—';
  return new Intl.NumberFormat('es-CO', {
    style: 'currency',
    currency: 'COP',
    maximumFractionDigits: 0,
  }).format(amount);
};
</script>

<template>
  <div class="p-6 sm:p-8">
    <h2 class="text-lg font-semibold text-n-slate-12 mb-1">
      {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_TITLE') }}
    </h2>
    <p class="text-sm text-n-slate-11 mb-6">
      {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_SUBTITLE') }}
    </p>

    <div
      v-if="isLoading"
      class="py-16 text-center text-sm text-n-slate-10 animate-pulse"
    >
      {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_LOADING') }}
    </div>

    <p
      v-else-if="errorMsg"
      class="text-sm text-n-ruby-9 rounded-lg bg-n-ruby-3 px-3 py-2"
    >
      {{ errorMsg }}
    </p>

    <template v-else>
      <div
        v-if="!leads.length"
        class="py-16 text-center text-sm text-n-slate-10"
      >
        {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_EMPTY') }}
      </div>

      <div
        v-else
        class="rounded-2xl border border-n-weak bg-n-surface-1 overflow-hidden overflow-x-auto"
      >
        <table class="w-full text-sm border-collapse min-w-[900px]">
          <thead>
            <tr class="bg-n-surface-2 border-b border-n-weak">
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_NAME') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_EMAIL') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_PHONE') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_COUNTRY') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_STATUS') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_LAST_MGMT') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_ORDERS') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_TOTAL') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_CREATED') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="lead in leads"
              :key="lead.id"
              class="hover:bg-n-surface-2/50 transition-colors"
            >
              <td class="px-4 py-3 font-medium text-n-slate-12">
                {{ lead.name }}
              </td>
              <td class="px-4 py-3 text-n-slate-11">
                {{ lead.email || '—' }}
              </td>
              <td class="px-4 py-3 text-n-slate-11">
                {{ lead.phone_number || '—' }}
              </td>
              <td class="px-4 py-3 text-n-slate-11">
                {{ lead.country || '—' }}
              </td>
              <td class="px-4 py-3">
                <span
                  v-if="lead.last_management_state"
                  class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium bg-n-alpha-black2 text-n-slate-11"
                >
                  {{ lead.last_management_state }}
                </span>
                <span v-else class="text-n-slate-10">—</span>
              </td>
              <td class="px-4 py-3 text-n-slate-11 text-xs">
                {{
                  lead.last_management_at
                    ? new Date(lead.last_management_at).toLocaleString('es')
                    : '—'
                }}
              </td>
              <td class="px-4 py-3 text-n-slate-12">
                {{ lead.orders_count ?? 0 }}
              </td>
              <td class="px-4 py-3 text-n-slate-12">
                {{ formatCurrency(lead.orders_total) }}
              </td>
              <td class="px-4 py-3 text-n-slate-11 text-xs">
                {{ new Date(lead.created_at).toLocaleDateString('es') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        v-if="totalPages > 1"
        class="mt-4 flex items-center justify-center gap-2"
      >
        <button
          class="h-8 px-3 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-surface-2 disabled:opacity-40 transition-colors"
          :disabled="currentPage <= 1"
          @click="goToPage(currentPage - 1)"
        >
          {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_PREV') }}
        </button>
        <span class="text-sm text-n-slate-11">
          {{ currentPage }} / {{ totalPages }}
        </span>
        <button
          class="h-8 px-3 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-surface-2 disabled:opacity-40 transition-colors"
          :disabled="currentPage >= totalPages"
          @click="goToPage(currentPage + 1)"
        >
          {{ t('JABVOX_AFFILIATE_PORTAL.LEADS_NEXT') }}
        </button>
      </div>
    </template>
  </div>
</template>
