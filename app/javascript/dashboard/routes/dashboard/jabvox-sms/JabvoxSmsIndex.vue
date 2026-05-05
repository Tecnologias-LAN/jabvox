<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import SmsCampaignForm from './SmsCampaignForm.vue';
import SmsProviderForm from './SmsProviderForm.vue';

const store = useStore();
const { t } = useI18n();

const activeTab = ref('campaigns');
const tabs = [
  {
    key: 'campaigns',
    label: () => t('JABVOX_SMS.TABS.CAMPAIGNS'),
    icon: 'i-lucide-send',
  },
  {
    key: 'providers',
    label: () => t('JABVOX_SMS.TABS.PROVIDERS'),
    icon: 'i-lucide-plug',
  },
  {
    key: 'reports',
    label: () => t('JABVOX_SMS.TABS.REPORTS'),
    icon: 'i-lucide-bar-chart-2',
  },
];

const campaigns = useMapGetter('jabvoxSms/getCampaigns');
const providers = useMapGetter('jabvoxSms/getProviders');
const messages = useMapGetter('jabvoxSms/getMessages');
const messagesMeta = useMapGetter('jabvoxSms/getMessagesMeta');
const stats = useMapGetter('jabvoxSms/getStats');
const uiFlags = useMapGetter('jabvoxSms/getUIFlags');

onMounted(() => {
  store.dispatch('jabvoxSms/fetchProviders');
  store.dispatch('jabvoxSms/fetchCampaigns');
  store.dispatch('jabvoxSms/fetchMessages');
  store.dispatch('jabvoxSms/fetchStats');
});

// ── campaigns ──────────────────────────────────────────────────────────────
const showCampaignForm = ref(false);
const editingCampaign = ref(null);

const openNewCampaign = () => {
  editingCampaign.value = null;
  showCampaignForm.value = true;
};
const openEditCampaign = c => {
  editingCampaign.value = c;
  showCampaignForm.value = true;
};
const closeCampaignForm = () => {
  showCampaignForm.value = false;
  editingCampaign.value = null;
};

const saveCampaign = async payload => {
  try {
    if (editingCampaign.value) {
      await store.dispatch('jabvoxSms/updateCampaign', {
        id: editingCampaign.value.id,
        ...payload,
      });
    } else {
      await store.dispatch('jabvoxSms/createCampaign', payload);
    }
    useAlert(t('JABVOX_SMS.SAVE_SUCCESS'));
    closeCampaignForm();
  } catch {
    useAlert(t('JABVOX_SMS.ERROR'));
  }
};

const deleteCampaign = async id => {
  if (!window.confirm(t('JABVOX_SMS.CAMPAIGNS.DELETE_CONFIRM'))) return;
  await store.dispatch('jabvoxSms/deleteCampaign', id);
  useAlert(t('JABVOX_SMS.DELETE_SUCCESS'));
};

const sendBulk = async campaign => {
  if (
    !window.confirm(
      t('JABVOX_SMS.CAMPAIGNS.SEND_CONFIRM', { name: campaign.name, n: '?' })
    )
  )
    return;
  try {
    const { queued } = await store.dispatch('jabvoxSms/sendBulk', campaign.id);
    useAlert(t('JABVOX_SMS.CAMPAIGNS.SEND_SUCCESS', { n: queued }));
  } catch {
    useAlert(t('JABVOX_SMS.ERROR'));
  }
};

const campaignStatusColor = status =>
  ({
    completed: 'bg-green-100 text-green-700',
    active: 'bg-blue-100 text-blue-700',
    paused: 'bg-yellow-100 text-yellow-700',
    draft: 'bg-slate-100 text-slate-500',
  })[status] || 'bg-slate-100 text-slate-500';

// ── providers ──────────────────────────────────────────────────────────────
const showProviderForm = ref(false);
const editingProvider = ref(null);
const connectionStatus = ref({});

const openNewProvider = () => {
  editingProvider.value = null;
  showProviderForm.value = true;
};
const openEditProvider = p => {
  editingProvider.value = p;
  showProviderForm.value = true;
};
const closeProviderForm = () => {
  showProviderForm.value = false;
  editingProvider.value = null;
};

const saveProvider = async payload => {
  try {
    if (editingProvider.value) {
      await store.dispatch('jabvoxSms/updateProvider', {
        id: editingProvider.value.id,
        ...payload,
      });
    } else {
      await store.dispatch('jabvoxSms/createProvider', payload);
    }
    useAlert(t('JABVOX_SMS.SAVE_SUCCESS'));
    closeProviderForm();
  } catch {
    useAlert(t('JABVOX_SMS.ERROR'));
  }
};

const deleteProvider = async id => {
  if (!window.confirm(t('JABVOX_SMS.PROVIDERS.DELETE_CONFIRM'))) return;
  await store.dispatch('jabvoxSms/deleteProvider', id);
};

const checkConnection = async provider => {
  connectionStatus.value = {
    ...connectionStatus.value,
    [provider.id]: 'checking',
  };
  try {
    const { data } = await import('dashboard/api/jabvox/sms').then(m =>
      m.smsProvidersAPI.checkConnection(provider.id)
    );
    connectionStatus.value = {
      ...connectionStatus.value,
      [provider.id]: data.connected ? 'ok' : 'fail',
    };
  } catch {
    connectionStatus.value = {
      ...connectionStatus.value,
      [provider.id]: 'fail',
    };
  }
};

// ── reports ────────────────────────────────────────────────────────────────
const reportPage = ref(1);

const loadMessages = page => {
  reportPage.value = page;
  store.dispatch('jabvoxSms/fetchMessages', { page });
};

const statusBadge = status =>
  ({
    sent: 'bg-green-100 text-green-700',
    failed: 'bg-red-100 text-red-600',
    pending: 'bg-yellow-100 text-yellow-700',
  })[status] || 'bg-slate-100 text-slate-500';

const formatDate = v => (v ? new Date(v).toLocaleString() : '—');

// ── campaign pill helpers ──────────────────────────────────────────────────
const filtersLabel = computed(() => c => {
  const parts = [];
  if (c.jabvox_campaign_id)
    parts.push(t('JABVOX_SMS.CAMPAIGNS.HAS_LEAD_CAMPAIGN'));
  if (c.affiliate_ids_sms?.length)
    parts.push(`${c.affiliate_ids_sms.length} afiliados`);
  if (c.inbox_ids_sms?.length) parts.push(`${c.inbox_ids_sms.length} bandejas`);
  return parts.join(' · ') || t('JABVOX_SMS.CAMPAIGNS.ALL_LEADS');
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <!-- Header -->
    <div class="shrink-0 border-b border-n-weak bg-n-surface-1">
      <div
        class="max-w-3xl mx-auto px-6 sm:px-8 pt-6 pb-0 flex items-center justify-between"
      >
        <h1 class="text-heading-1 text-n-slate-12">
          {{ t('JABVOX_SMS.TITLE') }}
        </h1>
        <Button
          v-if="activeTab === 'campaigns' && !showCampaignForm"
          icon="i-lucide-plus"
          :label="t('JABVOX_SMS.CAMPAIGNS.NEW_BUTTON')"
          @click="openNewCampaign"
        />
        <Button
          v-if="activeTab === 'providers' && !showProviderForm"
          icon="i-lucide-plus"
          :label="t('JABVOX_SMS.PROVIDERS.NEW_BUTTON')"
          @click="openNewProvider"
        />
      </div>
      <div class="flex px-6 sm:px-8 gap-1 max-w-3xl mx-auto mt-4">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px"
          :class="
            activeTab === tab.key
              ? 'border-woot-500 text-woot-600'
              : 'border-transparent text-n-slate-10 hover:text-n-slate-12 hover:border-n-weak'
          "
          @click="activeTab = tab.key"
        >
          <span class="w-4 h-4" :class="[tab.icon]" />
          {{ tab.label() }}
        </button>
      </div>
    </div>

    <!-- Body -->
    <div class="flex-1 overflow-y-auto">
      <!-- ── Campaigns ── -->
      <div
        v-if="activeTab === 'campaigns'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8"
      >
        <!-- List -->
        <div v-if="!showCampaignForm">
          <div
            v-if="uiFlags.isFetchingCampaigns"
            class="text-sm text-n-slate-10 text-center py-10"
          >
            {{ t('JABVOX_PRODUCTS.LOADING') }}
          </div>
          <div
            v-else-if="!campaigns.length"
            class="text-sm text-n-slate-10 text-center py-10"
          >
            {{ t('JABVOX_SMS.CAMPAIGNS.EMPTY') }}
          </div>
          <div v-else class="space-y-3">
            <div
              v-for="c in campaigns"
              :key="c.id"
              class="bg-white dark:bg-n-surface-2 rounded-2xl border border-n-weak p-5 flex items-start justify-between gap-4"
            >
              <div class="min-w-0 space-y-1.5">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="text-sm font-semibold text-n-slate-12">
                    {{ c.name }}
                  </span>
                  <span
                    class="text-xs px-2 py-0.5 rounded-full font-medium"
                    :class="campaignStatusColor(c.status)"
                  >
                    {{ c.status }}
                  </span>
                </div>
                <p v-if="c.description" class="text-xs text-n-slate-9 truncate">
                  {{ c.description }}
                </p>
                <p class="text-xs text-n-slate-9">
                  <span class="font-medium text-n-slate-10">
                    {{ c.provider_name || '—' }}
                  </span>
                  · {{ filtersLabel(c) }} ·
                  {{ t('JABVOX_SMS.CAMPAIGNS.SENT') }}: {{ c.sent_count }} ·
                  {{ t('JABVOX_SMS.CAMPAIGNS.FAILED') }}: {{ c.failed_count }}
                </p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <Button
                  v-if="c.status !== 'completed'"
                  size="small"
                  variant="clear"
                  icon="i-lucide-send"
                  :disabled="uiFlags.isSending"
                  :label="t('JABVOX_SMS.CAMPAIGNS.SEND_BUTTON')"
                  @click="sendBulk(c)"
                />
                <Button
                  size="small"
                  variant="clear"
                  icon="i-lucide-pencil"
                  @click="openEditCampaign(c)"
                />
                <Button
                  size="small"
                  variant="clear"
                  icon="i-lucide-trash-2"
                  color-scheme="alert"
                  @click="deleteCampaign(c.id)"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- Form -->
        <div v-else>
          <SmsCampaignForm
            :campaign="editingCampaign"
            @save="saveCampaign"
            @cancel="closeCampaignForm"
          />
        </div>
      </div>

      <!-- ── Providers ── -->
      <div
        v-else-if="activeTab === 'providers'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8"
      >
        <div v-if="!showProviderForm">
          <div
            v-if="!providers.length"
            class="text-sm text-n-slate-10 text-center py-10"
          >
            {{ t('JABVOX_SMS.PROVIDERS.EMPTY') }}
          </div>
          <div v-else class="space-y-3">
            <div
              v-for="p in providers"
              :key="p.id"
              class="bg-white dark:bg-n-surface-2 rounded-2xl border border-n-weak p-5 flex items-center justify-between gap-4"
            >
              <div class="min-w-0 space-y-0.5">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-semibold text-n-slate-12">
                    {{ p.name }}
                  </span>
                  <span
                    class="text-xs px-2 py-0.5 rounded-full font-medium"
                    :class="
                      p.active
                        ? 'bg-green-100 text-green-700'
                        : 'bg-slate-100 text-slate-500'
                    "
                  >
                    {{
                      p.active
                        ? t('JABVOX_SMS.PROVIDERS.ACTIVE')
                        : t('JABVOX_SMS.PROVIDERS.INACTIVE')
                    }}
                  </span>
                  <span
                    v-if="connectionStatus[p.id]"
                    class="text-xs px-2 py-0.5 rounded-full font-medium"
                    :class="{
                      'bg-blue-100 text-blue-600':
                        connectionStatus[p.id] === 'checking',
                      'bg-green-100 text-green-700':
                        connectionStatus[p.id] === 'ok',
                      'bg-red-100 text-red-600':
                        connectionStatus[p.id] === 'fail',
                    }"
                  >
                    {{
                      connectionStatus[p.id] === 'checking'
                        ? '...'
                        : connectionStatus[p.id] === 'ok'
                          ? t('JABVOX_SMS.PROVIDERS.CONNECTED')
                          : t('JABVOX_SMS.PROVIDERS.DISCONNECTED')
                    }}
                  </span>
                </div>
                <p class="text-xs text-n-slate-9">
                  {{ p.base_url }} · {{ p.api_user }}
                </p>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <Button
                  size="small"
                  variant="clear"
                  icon="i-lucide-plug"
                  :label="t('JABVOX_SMS.PROVIDERS.TEST')"
                  @click="checkConnection(p)"
                />
                <Button
                  size="small"
                  variant="clear"
                  icon="i-lucide-pencil"
                  @click="openEditProvider(p)"
                />
                <Button
                  size="small"
                  variant="clear"
                  icon="i-lucide-trash-2"
                  color-scheme="alert"
                  @click="deleteProvider(p.id)"
                />
              </div>
            </div>
          </div>
        </div>
        <div v-else>
          <SmsProviderForm
            :provider="editingProvider"
            @save="saveProvider"
            @cancel="closeProviderForm"
          />
        </div>
      </div>

      <!-- ── Reports ── -->
      <div
        v-else-if="activeTab === 'reports'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-6"
      >
        <!-- Stats -->
        <div v-if="stats" class="grid grid-cols-3 gap-4">
          <div
            class="bg-white dark:bg-n-surface-2 rounded-2xl border border-n-weak p-4 text-center"
          >
            <p class="text-2xl font-bold text-green-600">
              {{ stats.total_sent }}
            </p>
            <p class="text-xs text-n-slate-9 mt-1">
              {{ t('JABVOX_SMS.REPORTS.SENT') }}
            </p>
          </div>
          <div
            class="bg-white dark:bg-n-surface-2 rounded-2xl border border-n-weak p-4 text-center"
          >
            <p class="text-2xl font-bold text-red-500">
              {{ stats.total_failed }}
            </p>
            <p class="text-xs text-n-slate-9 mt-1">
              {{ t('JABVOX_SMS.REPORTS.FAILED') }}
            </p>
          </div>
          <div
            class="bg-white dark:bg-n-surface-2 rounded-2xl border border-n-weak p-4 text-center"
          >
            <p class="text-2xl font-bold text-yellow-500">
              {{ stats.total_pending }}
            </p>
            <p class="text-xs text-n-slate-9 mt-1">
              {{ t('JABVOX_SMS.REPORTS.PENDING') }}
            </p>
          </div>
        </div>

        <!-- Messages table -->
        <div
          class="bg-white dark:bg-n-surface-2 rounded-2xl border border-n-weak overflow-hidden"
        >
          <div
            v-if="uiFlags.isFetchingMessages"
            class="text-sm text-n-slate-10 text-center py-10"
          >
            {{ t('JABVOX_PRODUCTS.LOADING') }}
          </div>
          <div
            v-else-if="!messages.length"
            class="text-sm text-n-slate-10 text-center py-10"
          >
            {{ t('JABVOX_SMS.REPORTS.EMPTY') }}
          </div>
          <table v-else class="w-full text-sm">
            <thead class="bg-n-surface-2 dark:bg-n-surface-3">
              <tr>
                <th
                  class="text-left px-4 py-3 text-xs font-medium text-n-slate-9"
                >
                  {{ t('JABVOX_SMS.REPORTS.PHONE') }}
                </th>
                <th
                  class="text-left px-4 py-3 text-xs font-medium text-n-slate-9"
                >
                  {{ t('JABVOX_SMS.REPORTS.CONTACT') }}
                </th>
                <th
                  class="text-left px-4 py-3 text-xs font-medium text-n-slate-9"
                >
                  {{ t('JABVOX_SMS.REPORTS.CAMPAIGN') }}
                </th>
                <th
                  class="text-left px-4 py-3 text-xs font-medium text-n-slate-9"
                >
                  {{ t('JABVOX_SMS.REPORTS.MESSAGE') }}
                </th>
                <th
                  class="text-left px-4 py-3 text-xs font-medium text-n-slate-9"
                >
                  {{ t('JABVOX_SMS.REPORTS.STATUS') }}
                </th>
                <th
                  class="text-left px-4 py-3 text-xs font-medium text-n-slate-9"
                >
                  {{ t('JABVOX_SMS.REPORTS.DATE') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="msg in messages"
                :key="msg.id"
                class="border-t border-n-weak hover:bg-n-surface-2"
              >
                <td class="px-4 py-3 font-mono text-xs text-n-slate-11">
                  {{ msg.phone }}
                </td>
                <td class="px-4 py-3 text-xs text-n-slate-9">
                  {{ msg.contact_name || '—' }}
                </td>
                <td class="px-4 py-3 text-xs text-n-slate-9">
                  {{ msg.campaign_name || '—' }}
                </td>
                <td class="px-4 py-3 text-xs text-n-slate-11 max-w-xs truncate">
                  {{ msg.message }}
                </td>
                <td class="px-4 py-3">
                  <span
                    class="text-xs px-2 py-0.5 rounded-full font-medium"
                    :class="statusBadge(msg.status)"
                  >
                    {{ msg.status }}
                  </span>
                </td>
                <td class="px-4 py-3 text-xs text-n-slate-9">
                  {{ formatDate(msg.created_at) }}
                </td>
              </tr>
            </tbody>
          </table>
          <div
            v-if="messagesMeta.total_pages > 1"
            class="flex items-center justify-between px-4 py-3 border-t border-n-weak"
          >
            <span class="text-xs text-n-slate-9">
              {{
                t('JABVOX_SMS.REPORTS.PAGE', {
                  page: messagesMeta.current_page,
                  total: messagesMeta.total_pages,
                })
              }}
            </span>
            <div class="flex gap-2">
              <Button
                size="small"
                variant="clear"
                :disabled="messagesMeta.current_page <= 1"
                label="←"
                @click="loadMessages(messagesMeta.current_page - 1)"
              />
              <Button
                size="small"
                variant="clear"
                :disabled="
                  messagesMeta.current_page >= messagesMeta.total_pages
                "
                label="→"
                @click="loadMessages(messagesMeta.current_page + 1)"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
