<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import affiliatePortalAPI from '../../api/jabvox/affiliatePortal';

const { t } = useI18n();

const isLoading = ref(false);
const errorMsg = ref('');
const imports = ref([]);
const currentPage = ref(1);
const totalPages = ref(1);

const IMPORT_TYPE_LABEL = { manual: 'Manual', csv: 'CSV' };

const fetchHistory = async (page = 1) => {
  isLoading.value = true;
  errorMsg.value = '';
  try {
    const { data } = await affiliatePortalAPI.getHistory(page);
    imports.value = data.imports ?? [];
    currentPage.value = data.meta?.current_page ?? page;
    totalPages.value = data.meta?.total_pages ?? 1;
  } catch {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.HISTORY_ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => fetchHistory(1));

const goToPage = p => {
  if (p >= 1 && p <= totalPages.value) fetchHistory(p);
};
</script>

<template>
  <div class="p-6 sm:p-8">
    <h2 class="text-lg font-semibold text-n-slate-12 mb-1">
      {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_TITLE') }}
    </h2>
    <p class="text-sm text-n-slate-11 mb-6">
      {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_SUBTITLE') }}
    </p>

    <div
      v-if="isLoading"
      class="py-16 text-center text-sm text-n-slate-10 animate-pulse"
    >
      {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_LOADING') }}
    </div>

    <p
      v-else-if="errorMsg"
      class="text-sm text-n-ruby-9 rounded-lg bg-n-ruby-3 px-3 py-2"
    >
      {{ errorMsg }}
    </p>

    <template v-else>
      <div
        v-if="!imports.length"
        class="py-16 text-center text-sm text-n-slate-10"
      >
        {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_EMPTY') }}
      </div>

      <div
        v-else
        class="rounded-2xl border border-n-weak bg-n-surface-1 overflow-hidden"
      >
        <table class="w-full text-sm border-collapse">
          <thead>
            <tr class="bg-n-surface-2 border-b border-n-weak">
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_TYPE') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_FILE') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_TOTAL') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_OK') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_FAILED') }}
              </th>
              <th
                class="text-left px-4 py-3 text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
              >
                {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_DATE') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr
              v-for="item in imports"
              :key="item.id"
              class="hover:bg-n-surface-2/50 transition-colors"
            >
              <td class="px-4 py-3">
                <span
                  class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium bg-n-alpha-black2 text-n-slate-11"
                >
                  {{ IMPORT_TYPE_LABEL[item.import_type] ?? item.import_type }}
                </span>
              </td>
              <td class="px-4 py-3 text-n-slate-11 max-w-xs truncate">
                {{ item.filename ?? '—' }}
              </td>
              <td class="px-4 py-3 text-n-slate-12 font-medium">
                {{ item.rows_total }}
              </td>
              <td class="px-4 py-3 text-n-teal-11 font-medium">
                {{ item.rows_ok }}
              </td>
              <td class="px-4 py-3 text-n-ruby-9 font-medium">
                {{ item.rows_failed }}
              </td>
              <td class="px-4 py-3 text-n-slate-11 text-xs">
                {{ new Date(item.created_at).toLocaleString('es') }}
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
          {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_PREV') }}
        </button>
        <span class="text-sm text-n-slate-11">
          {{ currentPage }} / {{ totalPages }}
        </span>
        <button
          class="h-8 px-3 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-surface-2 disabled:opacity-40 transition-colors"
          :disabled="currentPage >= totalPages"
          @click="goToPage(currentPage + 1)"
        >
          {{ t('JABVOX_AFFILIATE_PORTAL.HISTORY_NEXT') }}
        </button>
      </div>
    </template>
  </div>
</template>
