<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import { analyticsPermissionsAPI } from 'dashboard/api/jabvox/analytics';
import AnalyticsLoadingState from '../components/AnalyticsLoadingState.vue';
import AnalyticsEmptyState from '../components/AnalyticsEmptyState.vue';

const { t } = useI18n();
const { showError } = useAnalyticsError();

const loading = ref(true);
const logs = ref([]);

const resultClass = result => {
  if (result === 'success') return 'text-n-teal-11';
  if (result === 'rejected') return 'text-n-ruby-11';
  return 'text-n-slate-11';
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await analyticsPermissionsAPI.getAuditLogs();
    logs.value = data.payload || [];
  } catch (error) {
    showError(error);
  } finally {
    loading.value = false;
  }
};

onMounted(load);
</script>

<template>
  <AnalyticsLoadingState v-if="loading" />
  <AnalyticsEmptyState
    v-else-if="!logs.length"
    icon="i-lucide-scroll-text"
    :title="t('JABVOX_ANALYTICS.AUDIT.TITLE')"
  />
  <div v-else class="overflow-x-auto border rounded-lg border-n-weak">
    <table class="w-full text-sm">
      <thead class="bg-n-alpha-1 text-n-slate-11">
        <tr>
          <th class="px-3 py-2 text-left">
            {{ t('JABVOX_ANALYTICS.AUDIT.DATE') }}
          </th>
          <th class="px-3 py-2 text-left">
            {{ t('JABVOX_ANALYTICS.AUDIT.USER') }}
          </th>
          <th class="px-3 py-2 text-left">
            {{ t('JABVOX_ANALYTICS.AUDIT.ACTION') }}
          </th>
          <th class="px-3 py-2 text-left">
            {{ t('JABVOX_ANALYTICS.AUDIT.RESULT') }}
          </th>
          <th class="px-3 py-2 text-left">
            {{ t('JABVOX_ANALYTICS.AUDIT.IP') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="log in logs"
          :key="log.id"
          class="border-t border-n-weak text-n-slate-12"
        >
          <td class="px-3 py-2 whitespace-nowrap text-n-slate-11">
            {{ new Date(log.created_at).toLocaleString() }}
          </td>
          <td class="px-3 py-2">{{ log.user || '—' }}</td>
          <td class="px-3 py-2 font-mono text-xs">{{ log.action_jabvox }}</td>
          <td
            class="px-3 py-2 font-medium"
            :class="resultClass(log.result_jabvox)"
          >
            {{ log.result_jabvox }}
          </td>
          <td class="px-3 py-2 text-n-slate-10">
            {{ log.ip_address_jabvox || '—' }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
