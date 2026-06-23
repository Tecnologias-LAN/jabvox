<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { smsProvidersAPI } from 'dashboard/api/jabvox/sms';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SmsCampaignForm from './SmsCampaignForm.vue';
import SmsProviderForm from './SmsProviderForm.vue';
import SideDrawer from './components/SideDrawer.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

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

const campaignSearch = ref('');
const providerSearch = ref('');

const deleteCampaignDialog = ref(null);
const sendDialog = ref(null);
const deleteProviderDialog = ref(null);

onMounted(() => {
  store.dispatch('jabvoxSms/fetchProviders');
  store.dispatch('jabvoxSms/fetchCampaigns');
  store.dispatch('jabvoxSms/fetchMessages');
  store.dispatch('jabvoxSms/fetchStats');
});

// ── campaigns ──
const showCampaignForm = ref(false);
const editingCampaign = ref(null);

const filteredCampaigns = computed(() => {
  const q = campaignSearch.value.trim().toLowerCase();
  if (!q) return campaigns.value;
  return campaigns.value.filter(c => c.name?.toLowerCase().includes(q));
});

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

const askDeleteCampaign = c => {
  deleteCampaignDialog.value?.open({
    title: t('JABVOX_SMS.CAMPAIGNS.DELETE_TITLE'),
    description: t('JABVOX_SMS.CAMPAIGNS.DELETE_BODY', { name: c.name }),
    data: c.id,
  });
};
const doDeleteCampaign = async id => {
  try {
    await store.dispatch('jabvoxSms/deleteCampaign', id);
    useAlert(t('JABVOX_SMS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_SMS.ERROR'));
  }
};

const askSend = c => {
  sendDialog.value?.open({
    title: t('JABVOX_SMS.CAMPAIGNS.SEND_TITLE'),
    description: t('JABVOX_SMS.CAMPAIGNS.SEND_BODY', { name: c.name }),
    confirmLabel: t('JABVOX_SMS.CAMPAIGNS.SEND_BUTTON'),
    data: c.id,
  });
};
const doSend = async id => {
  try {
    const { queued } = await store.dispatch('jabvoxSms/sendBulk', id);
    useAlert(t('JABVOX_SMS.CAMPAIGNS.SEND_SUCCESS', { n: queued }));
  } catch {
    useAlert(t('JABVOX_SMS.ERROR'));
  }
};

const STATUS_COLOR = {
  completed: 'teal',
  active: 'blue',
  paused: 'amber',
  draft: 'slate',
};
const campaignStatusColor = status => STATUS_COLOR[status] || 'slate';

// ── providers ──
const showProviderForm = ref(false);
const editingProvider = ref(null);
const connectionStatus = ref({});

const filteredProviders = computed(() => {
  const q = providerSearch.value.trim().toLowerCase();
  if (!q) return providers.value;
  return providers.value.filter(p => p.name?.toLowerCase().includes(q));
});

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

const askDeleteProvider = p => {
  deleteProviderDialog.value?.open({
    title: t('JABVOX_SMS.PROVIDERS.DELETE_TITLE'),
    description: t('JABVOX_SMS.PROVIDERS.DELETE_BODY', { name: p.name }),
    data: p.id,
  });
};
const doDeleteProvider = async id => {
  try {
    await store.dispatch('jabvoxSms/deleteProvider', id);
    useAlert(t('JABVOX_SMS.DELETE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_SMS.ERROR'));
  }
};

const checkConnection = async provider => {
  connectionStatus.value = {
    ...connectionStatus.value,
    [provider.id]: 'checking',
  };
  try {
    const { data } = await smsProvidersAPI.checkConnection(provider.id);
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

// ── reports ──
const reportPage = ref(1);
const loadMessages = page => {
  reportPage.value = page;
  store.dispatch('jabvoxSms/fetchMessages', { page });
};

const STATUS_BADGE = { sent: 'teal', failed: 'ruby', pending: 'amber' };
const statusBadge = status => STATUS_BADGE[status] || 'slate';

const formatDate = v => (v ? new Date(v).toLocaleString() : '—');

// ── campaign pill helpers ──
const filtersLabel = computed(() => c => {
  const parts = [];
  if (c.jabvox_campaign_id)
    parts.push(t('JABVOX_SMS.CAMPAIGNS.HAS_LEAD_CAMPAIGN'));
  if (c.affiliate_ids_sms?.length)
    parts.push(`${c.affiliate_ids_sms.length} afiliados`);
  if (c.inbox_ids_sms?.length) parts.push(`${c.inbox_ids_sms.length} bandejas`);
  return parts.join(' · ') || t('JABVOX_SMS.CAMPAIGNS.ALL_LEADS');
});

const drawerOpen = computed({
  get: () => showCampaignForm.value || showProviderForm.value,
  set: v => {
    if (!v) {
      closeCampaignForm();
      closeProviderForm();
    }
  },
});
const drawerTitle = computed(() => {
  if (showProviderForm.value) {
    return editingProvider.value
      ? t('JABVOX_SMS.PROVIDERS.EDIT_TITLE')
      : t('JABVOX_SMS.PROVIDERS.NEW_TITLE');
  }
  return editingCampaign.value
    ? t('JABVOX_SMS.CAMPAIGNS.EDIT_TITLE')
    : t('JABVOX_SMS.CAMPAIGNS.NEW_TITLE');
});
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-8 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-message-square-text size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_SMS.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_SMS.SUBTITLE') }}
            </p>
          </div>
        </div>
        <Button
          v-if="activeTab === 'campaigns'"
          :label="t('JABVOX_SMS.CAMPAIGNS.NEW_BUTTON')"
          icon="i-lucide-plus"
          class="shrink-0"
          @click="openNewCampaign"
        />
        <Button
          v-else-if="activeTab === 'providers'"
          :label="t('JABVOX_SMS.PROVIDERS.NEW_BUTTON')"
          icon="i-lucide-plus"
          class="shrink-0"
          @click="openNewProvider"
        />
      </div>

      <!-- Tabs -->
      <div
        class="flex items-center gap-1 p-1 rounded-xl bg-n-alpha-1 border border-n-weak w-full sm:w-fit overflow-x-auto"
      >
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg whitespace-nowrap transition-colors flex-1 sm:flex-none focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
          :class="
            activeTab === tab.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeTab = tab.key"
        >
          <span :class="tab.icon" class="size-4 shrink-0" />
          {{ tab.label() }}
        </button>
      </div>

      <!-- ── CAMPAIGNS ── -->
      <div v-if="activeTab === 'campaigns'" class="flex flex-col gap-5">
        <div
          v-if="uiFlags.isFetchingCampaigns"
          class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
        >
          <Spinner :size="18" />
        </div>

        <EmptyStateLayout
          v-else-if="!campaigns.length"
          :title="t('JABVOX_SMS.CAMPAIGNS.EMPTY_TITLE')"
          :subtitle="t('JABVOX_SMS.CAMPAIGNS.EMPTY')"
        >
          <template #actions>
            <Button
              icon="i-lucide-plus"
              :label="t('JABVOX_SMS.CAMPAIGNS.NEW_BUTTON')"
              size="sm"
              @click="openNewCampaign"
            />
          </template>
        </EmptyStateLayout>

        <template v-else>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="relative w-full sm:w-64">
              <Input
                v-model="campaignSearch"
                :placeholder="t('JABVOX_SMS.CAMPAIGNS.SEARCH_PLACEHOLDER')"
                custom-input-class="!pl-9"
              >
                <template #prefix>
                  <span
                    class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                  />
                </template>
              </Input>
            </div>
            <span class="text-xs text-n-slate-10">
              {{
                t('JABVOX_SMS.CAMPAIGNS.COUNT_LABEL', {
                  count: campaigns.length,
                })
              }}
            </span>
          </div>

          <div
            v-if="!filteredCampaigns.length"
            class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_SMS.CAMPAIGNS.NO_RESULTS') }}
          </div>

          <div v-else class="grid grid-cols-1 xl:grid-cols-2 gap-4">
            <div
              v-for="c in filteredCampaigns"
              :key="c.id"
              class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm transition-shadow hover:shadow-md"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="flex items-center gap-2 min-w-0">
                  <span class="i-lucide-send size-4 text-n-slate-10 shrink-0" />
                  <h3 class="text-sm font-semibold text-n-slate-12 truncate">
                    {{ c.name }}
                  </h3>
                </div>
                <Label
                  :label="c.status"
                  :color="campaignStatusColor(c.status)"
                  compact
                />
              </div>

              <p
                v-if="c.description"
                class="text-xs text-n-slate-11 line-clamp-2"
              >
                {{ c.description }}
              </p>

              <div
                class="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-n-slate-10"
              >
                <span class="inline-flex items-center gap-1">
                  <span class="i-lucide-plug size-3.5" />
                  {{
                    c.provider?.name ||
                    providers.find(p => p.id === c.jabvox_sms_provider_id)
                      ?.name ||
                    '—'
                  }}
                </span>
                <span class="inline-flex items-center gap-1">
                  <span class="i-lucide-filter size-3.5" />
                  {{ filtersLabel(c) }}
                </span>
              </div>

              <div class="grid grid-cols-2 gap-2">
                <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
                  <p class="text-sm font-semibold text-n-teal-11 tabular-nums">
                    {{ c.sent_count ?? 0 }}
                  </p>
                  <p class="text-[11px] text-n-slate-10">
                    {{ t('JABVOX_SMS.CAMPAIGNS.SENT') }}
                  </p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-3 py-2 text-center">
                  <p class="text-sm font-semibold text-n-ruby-11 tabular-nums">
                    {{ c.failed_count ?? 0 }}
                  </p>
                  <p class="text-[11px] text-n-slate-10">
                    {{ t('JABVOX_SMS.CAMPAIGNS.FAILED') }}
                  </p>
                </div>
              </div>

              <div class="flex items-center gap-1 pt-2 border-t border-n-weak">
                <Button
                  :label="t('JABVOX_SMS.CAMPAIGNS.SEND_BUTTON')"
                  icon="i-lucide-send"
                  variant="outline"
                  color="slate"
                  size="sm"
                  :disabled="c.status === 'completed' || uiFlags.isSending"
                  @click="askSend(c)"
                />
                <div class="flex-1" />
                <Button
                  icon="i-lucide-pencil"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="openEditCampaign(c)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  @click="askDeleteCampaign(c)"
                />
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- ── PROVIDERS ── -->
      <div v-else-if="activeTab === 'providers'" class="flex flex-col gap-5">
        <div
          v-if="uiFlags.isFetchingProviders"
          class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
        >
          <Spinner :size="18" />
        </div>

        <EmptyStateLayout
          v-else-if="!providers.length"
          :title="t('JABVOX_SMS.PROVIDERS.EMPTY_TITLE')"
          :subtitle="t('JABVOX_SMS.PROVIDERS.EMPTY')"
        >
          <template #actions>
            <Button
              icon="i-lucide-plus"
              :label="t('JABVOX_SMS.PROVIDERS.NEW_BUTTON')"
              size="sm"
              @click="openNewProvider"
            />
          </template>
        </EmptyStateLayout>

        <template v-else>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="relative w-full sm:w-64">
              <Input
                v-model="providerSearch"
                :placeholder="t('JABVOX_SMS.PROVIDERS.SEARCH_PLACEHOLDER')"
                custom-input-class="!pl-9"
              >
                <template #prefix>
                  <span
                    class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
                  />
                </template>
              </Input>
            </div>
            <span class="text-xs text-n-slate-10">
              {{
                t('JABVOX_SMS.PROVIDERS.COUNT_LABEL', {
                  count: providers.length,
                })
              }}
            </span>
          </div>

          <div
            v-if="!filteredProviders.length"
            class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
          >
            {{ t('JABVOX_SMS.PROVIDERS.NO_RESULTS') }}
          </div>

          <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div
              v-for="p in filteredProviders"
              :key="p.id"
              class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="flex items-center gap-2 min-w-0">
                  <span class="i-lucide-plug size-4 text-n-slate-10 shrink-0" />
                  <h3 class="text-sm font-semibold text-n-slate-12 truncate">
                    {{ p.name }}
                  </h3>
                </div>
                <div class="flex items-center gap-1.5 shrink-0">
                  <Label
                    v-if="connectionStatus[p.id] === 'checking'"
                    :label="t('JABVOX_SMS.PROVIDERS.CHECKING')"
                    color="blue"
                    compact
                  />
                  <Label
                    v-else-if="connectionStatus[p.id] === 'ok'"
                    :label="t('JABVOX_SMS.PROVIDERS.CONNECTED')"
                    color="teal"
                    compact
                  />
                  <Label
                    v-else-if="connectionStatus[p.id] === 'fail'"
                    :label="t('JABVOX_SMS.PROVIDERS.DISCONNECTED')"
                    color="ruby"
                    compact
                  />
                  <Label
                    :label="
                      p.active
                        ? t('JABVOX_SMS.PROVIDERS.ACTIVE')
                        : t('JABVOX_SMS.PROVIDERS.INACTIVE')
                    "
                    :color="p.active ? 'teal' : 'slate'"
                    compact
                  />
                </div>
              </div>

              <div
                class="flex flex-col gap-0.5 text-xs text-n-slate-10 font-mono"
              >
                <span class="truncate">{{ p.base_url }}</span>
                <span class="truncate">{{ p.api_user }}</span>
              </div>

              <div class="flex items-center gap-1 pt-2 border-t border-n-weak">
                <Button
                  :label="t('JABVOX_SMS.PROVIDERS.TEST')"
                  icon="i-lucide-plug-zap"
                  variant="outline"
                  color="slate"
                  size="sm"
                  :is-loading="connectionStatus[p.id] === 'checking'"
                  @click="checkConnection(p)"
                />
                <div class="flex-1" />
                <Button
                  icon="i-lucide-pencil"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="openEditProvider(p)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  @click="askDeleteProvider(p)"
                />
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- ── REPORTS ── -->
      <div v-else class="flex flex-col gap-6">
        <!-- KPIs -->
        <div v-if="stats" class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-teal-3 text-n-teal-11"
            >
              <span class="i-lucide-circle-check size-5" />
            </span>
            <div>
              <p class="text-xl font-semibold tabular-nums text-n-slate-12">
                {{ stats.total_sent ?? 0 }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_SMS.REPORTS.SENT') }}
              </p>
            </div>
          </div>
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-ruby-3 text-n-ruby-11"
            >
              <span class="i-lucide-circle-x size-5" />
            </span>
            <div>
              <p class="text-xl font-semibold tabular-nums text-n-slate-12">
                {{ stats.total_failed ?? 0 }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_SMS.REPORTS.FAILED') }}
              </p>
            </div>
          </div>
          <div
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
          >
            <span
              class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-amber-3 text-n-amber-11"
            >
              <span class="i-lucide-clock size-5" />
            </span>
            <div>
              <p class="text-xl font-semibold tabular-nums text-n-slate-12">
                {{ stats.total_pending ?? 0 }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_SMS.REPORTS.PENDING') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Messages -->
        <div
          v-if="uiFlags.isFetchingMessages"
          class="flex items-center justify-center gap-2 py-12 text-sm text-n-slate-11"
        >
          <Spinner :size="18" />
        </div>
        <div
          v-else-if="!messages.length"
          class="rounded-xl border border-dashed border-n-weak py-12 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_SMS.REPORTS.EMPTY') }}
        </div>
        <div
          v-else
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden overflow-x-auto"
        >
          <table class="min-w-full text-sm">
            <thead
              class="bg-n-alpha-1 text-[11px] font-semibold uppercase tracking-wide text-n-slate-10"
            >
              <tr>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_SMS.REPORTS.PHONE') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_SMS.REPORTS.CONTACT') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_SMS.REPORTS.CAMPAIGN') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_SMS.REPORTS.MESSAGE') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_SMS.REPORTS.STATUS') }}
                </th>
                <th class="text-left px-4 py-2.5">
                  {{ t('JABVOX_SMS.REPORTS.DATE') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="m in messages"
                :key="m.id"
                class="hover:bg-n-alpha-1 transition-colors"
              >
                <td
                  class="px-4 py-2.5 font-mono text-xs text-n-slate-12 whitespace-nowrap"
                >
                  {{ m.phone }}
                </td>
                <td class="px-4 py-2.5 text-n-slate-11">
                  {{ m.contact_name || '—' }}
                </td>
                <td class="px-4 py-2.5 text-n-slate-11">
                  {{ m.campaign_name || '—' }}
                </td>
                <td class="px-4 py-2.5 text-n-slate-11 max-w-xs truncate">
                  {{ m.message }}
                </td>
                <td class="px-4 py-2.5">
                  <Label
                    :label="m.status"
                    :color="statusBadge(m.status)"
                    compact
                  />
                </td>
                <td
                  class="px-4 py-2.5 text-n-slate-10 text-xs whitespace-nowrap"
                >
                  {{ formatDate(m.created_at) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Pagination -->
        <div
          v-if="messagesMeta.total_pages > 1"
          class="flex items-center justify-between gap-3"
        >
          <span class="text-xs text-n-slate-11 tabular-nums">
            {{
              t('JABVOX_SMS.REPORTS.PAGE', {
                current: messagesMeta.current_page,
                total: messagesMeta.total_pages,
              })
            }}
          </span>
          <div class="flex items-center gap-2">
            <Button
              icon="i-lucide-chevron-left"
              variant="outline"
              color="slate"
              size="sm"
              :disabled="messagesMeta.current_page <= 1"
              @click="loadMessages(messagesMeta.current_page - 1)"
            />
            <Button
              icon="i-lucide-chevron-right"
              variant="outline"
              color="slate"
              size="sm"
              :disabled="messagesMeta.current_page >= messagesMeta.total_pages"
              @click="loadMessages(messagesMeta.current_page + 1)"
            />
          </div>
        </div>
      </div>
    </div>

    <!-- Form drawer (campaign or provider) -->
    <SideDrawer v-model:open="drawerOpen" :title="drawerTitle">
      <SmsCampaignForm
        v-if="showCampaignForm"
        :campaign="editingCampaign"
        @save="saveCampaign"
        @cancel="closeCampaignForm"
      />
      <SmsProviderForm
        v-else-if="showProviderForm"
        :provider="editingProvider"
        @save="saveProvider"
        @cancel="closeProviderForm"
      />
    </SideDrawer>

    <!-- Dialogs -->
    <ConfirmDialog ref="deleteCampaignDialog" @confirm="doDeleteCampaign" />
    <ConfirmDialog ref="deleteProviderDialog" @confirm="doDeleteProvider" />
    <ConfirmDialog ref="sendDialog" type="edit" @confirm="doSend" />
  </div>
</template>
