<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import allCountries from 'shared/constants/countries.js';

const store = useStore();
const { t } = useI18n();

// ─── Store getters ─────────────────────────────────────────────────────────
const campaigns = useMapGetter('jabvoxDialer/getCampaigns');
const dialerStates = useMapGetter('jabvoxDialer/getDialerStates');
const dialerAccesses = useMapGetter('jabvoxDialer/getDialerAccesses');
const uiFlags = useMapGetter('jabvoxDialer/getUIFlags');
const agents = useMapGetter('agents/getAgents');
const leadCampaigns = useMapGetter('jabvoxCampaigns/getCampaigns');
const managementStates = useMapGetter('jabvoxManagementStates/getStates');
const affiliates = useMapGetter('jabvoxAffiliates/getAffiliates');
const inboxes = useMapGetter('inboxes/getInboxes');

// ─── Tab ───────────────────────────────────────────────────────────────────
const activeTab = ref('campaigns');

const tabs = [
  {
    key: 'campaigns',
    label: () => t('JABVOX_DIALER.SETTINGS.TABS.CAMPAIGNS'),
    icon: 'i-lucide-phone-call',
  },
  {
    key: 'states',
    label: () => t('JABVOX_DIALER.SETTINGS.TABS.STATES'),
    icon: 'i-lucide-sliders-horizontal',
  },
  {
    key: 'permissions',
    label: () => t('JABVOX_DIALER.SETTINGS.TABS.PERMISSIONS'),
    icon: 'i-lucide-shield-check',
  },
];

// ─── Countries ─────────────────────────────────────────────────────────────
const countryOptions = computed(() =>
  allCountries.map(c => ({ value: c.name, label: c.name }))
);

const leadCampaignOptions = computed(() =>
  (leadCampaigns.value || []).map(c => ({ value: c.id, label: c.name }))
);

const affiliateOptions = computed(() =>
  (affiliates.value || []).map(a => ({ value: a.id, label: a.name }))
);

const inboxOptions = computed(() =>
  (inboxes.value || []).map(i => ({ value: i.id, label: i.name }))
);

// ─── Campaigns ─────────────────────────────────────────────────────────────
const showCampaignForm = ref(false);
const editingCampaignId = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  jabvox_campaign_id: null,
  countries_jabvox: [],
  wrapup_time_jabvox: 30,
  lines_per_agent_jabvox: 1,
  wait_in_queue_jabvox: true,
  management_state_ids_jabvox: [],
  agent_ids_jabvox: [],
  affiliate_ids_jabvox: [],
  inbox_ids_jabvox: [],
});

const campaignForm = ref(emptyForm());

const openCreateCampaign = () => {
  editingCampaignId.value = null;
  campaignForm.value = emptyForm();
  // eslint-disable-next-line no-use-before-define
  leadCount.value = null;
  showCampaignForm.value = true;
};

const openEditCampaign = c => {
  editingCampaignId.value = c.id;
  // eslint-disable-next-line no-use-before-define
  leadCount.value = null;
  campaignForm.value = {
    name_jabvox: c.name_jabvox,
    jabvox_campaign_id: c.jabvox_campaign_id || null,
    countries_jabvox: [...(c.countries_jabvox || [])],
    wrapup_time_jabvox: c.wrapup_time_jabvox ?? 30,
    lines_per_agent_jabvox: c.lines_per_agent_jabvox ?? 1,
    wait_in_queue_jabvox: c.wait_in_queue_jabvox ?? true,
    management_state_ids_jabvox: [...(c.management_state_ids_jabvox || [])],
    agent_ids_jabvox: [...(c.agent_ids_jabvox || [])],
    affiliate_ids_jabvox: [...(c.affiliate_ids_jabvox || [])],
    inbox_ids_jabvox: [...(c.inbox_ids_jabvox || [])],
  };
  showCampaignForm.value = true;
  // eslint-disable-next-line no-use-before-define
  if (c.jabvox_campaign_id) debouncedFetchLeadCount();
};

const toggleManagementState = id => {
  const list = campaignForm.value.management_state_ids_jabvox;
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

const toggleAgent = id => {
  const list = campaignForm.value.agent_ids_jabvox;
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

// ─── Lead count ────────────────────────────────────────────────────────────
const leadCount = ref(null);
const loadingLeadCount = ref(false);
let leadCountTimer = null;

const liveLeadCounts = ref({});

const fetchAllLiveCounts = async campaignList => {
  const results = await Promise.allSettled(
    campaignList
      .filter(c => c.jabvox_campaign_id)
      .map(c =>
        dialerCampaignsAPI
          .leadCount({
            jabvox_campaign_id: c.jabvox_campaign_id,
            countries: c.countries_jabvox || [],
            management_state_ids: c.management_state_ids_jabvox || [],
            affiliate_ids: c.affiliate_ids_jabvox || [],
            inbox_ids: c.inbox_ids_jabvox || [],
          })
          .then(({ data }) => ({ id: c.id, count: data.count }))
      )
  );
  const counts = {};
  results.forEach(r => {
    if (r.status === 'fulfilled') counts[r.value.id] = r.value.count;
  });
  liveLeadCounts.value = counts;
};

const fetchLeadCount = async () => {
  if (!campaignForm.value.jabvox_campaign_id) {
    leadCount.value = null;
    return;
  }
  loadingLeadCount.value = true;
  try {
    const { data } = await dialerCampaignsAPI.leadCount({
      jabvox_campaign_id: campaignForm.value.jabvox_campaign_id,
      countries: campaignForm.value.countries_jabvox,
      management_state_ids: campaignForm.value.management_state_ids_jabvox,
      affiliate_ids: campaignForm.value.affiliate_ids_jabvox,
      inbox_ids: campaignForm.value.inbox_ids_jabvox,
    });
    leadCount.value = data.count;
  } catch {
    leadCount.value = null;
  } finally {
    loadingLeadCount.value = false;
  }
};

const debouncedFetchLeadCount = () => {
  clearTimeout(leadCountTimer);
  leadCountTimer = setTimeout(fetchLeadCount, 400);
};

watch(
  () => [
    campaignForm.value.jabvox_campaign_id,
    campaignForm.value.countries_jabvox.length,
    campaignForm.value.management_state_ids_jabvox.length,
    campaignForm.value.affiliate_ids_jabvox.length,
    campaignForm.value.inbox_ids_jabvox.length,
  ],
  debouncedFetchLeadCount
);

const onSaveCampaign = async () => {
  if (!campaignForm.value.name_jabvox) return;
  try {
    const payload = {
      ...campaignForm.value,
      jabvox_campaign_id: campaignForm.value.jabvox_campaign_id || null,
      leads_count_jabvox: leadCount.value ?? 0,
    };
    if (editingCampaignId.value) {
      await store.dispatch('jabvoxDialer/updateCampaign', {
        id: editingCampaignId.value,
        ...payload,
      });
    } else {
      await store.dispatch('jabvoxDialer/createCampaign', payload);
    }
    showCampaignForm.value = false;
    useAlert(t('JABVOX_DIALER.CAMPAIGN.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  }
};

const onDeleteCampaign = async c => {
  if (!window.confirm(t('JABVOX_DIALER.CAMPAIGN.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('jabvoxDialer/deleteCampaign', c.id);
    useAlert(t('JABVOX_DIALER.CAMPAIGN.DELETED'));
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  }
};

const togglingCampaignId = ref(null);

// ─── Report modal ────────────────────────────────────────────────────────────
const showReportModal = ref(false);
const reportCampaign = ref(null);
const reportFrom = ref('');
const reportTo = ref('');
const reportGroupBy = ref('day');
const reportFromHour = ref(0);
const reportToHour = ref(23);
const reportRows = ref([]);
const reportTotals = ref({
  total: 0,
  answered: 0,
  no_answer: 0,
  no_agent: 0,
  agents: 0,
});
const reportLoading = ref(false);
const reportDrillDay = ref(null);

const isSingleDay = computed(
  () =>
    reportFrom.value && reportTo.value && reportFrom.value === reportTo.value
);

const fetchReport = async (groupBy = null, day = null) => {
  if (!reportCampaign.value) return;
  reportLoading.value = true;
  try {
    const params = {
      from: day || reportFrom.value,
      to: day || reportTo.value,
      group_by: groupBy || reportGroupBy.value,
    };
    if (isSingleDay.value || day) {
      params.from_hour = reportFromHour.value;
      params.to_hour = reportToHour.value;
    }
    const { data } = await dialerCampaignsAPI.getReport(
      reportCampaign.value.id,
      params
    );
    reportRows.value = data.rows || [];
    reportTotals.value = data.totals || {
      total: 0,
      answered: 0,
      no_answer: 0,
      no_agent: 0,
      agents: 0,
    };
  } catch {
    reportRows.value = [];
  } finally {
    reportLoading.value = false;
  }
};

const openReport = c => {
  reportCampaign.value = c;
  const today = new Date().toISOString().slice(0, 10);
  const weekAgo = new Date(Date.now() - 6 * 86400000)
    .toISOString()
    .slice(0, 10);
  reportFrom.value = weekAgo;
  reportTo.value = today;
  reportGroupBy.value = 'day';
  reportDrillDay.value = null;
  reportRows.value = [];
  reportTotals.value = {
    total: 0,
    answered: 0,
    no_answer: 0,
    no_agent: 0,
    agents: 0,
  };
  showReportModal.value = true;
  fetchReport();
};

const drillIntoDay = day => {
  const dayStr =
    typeof day === 'string'
      ? day.slice(0, 10)
      : new Date(day).toISOString().slice(0, 10);
  reportDrillDay.value = dayStr;
  fetchReport('hour', dayStr);
};

const backToDaily = () => {
  reportDrillDay.value = null;
  fetchReport('day');
};

watch([reportFrom, reportTo], () => {
  if (reportFrom.value && reportTo.value && showReportModal.value) {
    reportDrillDay.value = null;
    fetchReport(isSingleDay.value ? 'hour' : 'day');
  }
});

const formatPeriod = (period, groupBy) => {
  if (!period) return '—';
  const d = new Date(period);
  if (groupBy === 'hour' || reportDrillDay.value) {
    return `${String(d.getUTCHours()).padStart(2, '0')}:00`;
  }
  return d.toISOString().slice(0, 10);
};

const onToggleCampaign = async c => {
  togglingCampaignId.value = c.id;
  try {
    if (c.status_jabvox === 'active') {
      await store.dispatch('jabvoxDialer/pauseCampaign', c.id);
      useAlert(t('JABVOX_DIALER.CAMPAIGN.PAUSED'));
    } else {
      await store.dispatch('jabvoxDialer/startCampaign', c.id);
      useAlert(t('JABVOX_DIALER.CAMPAIGN.STARTED'));
    }
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  } finally {
    togglingCampaignId.value = null;
  }
};

const campaignStatusColor = status =>
  ({
    draft: 'bg-slate-100 text-slate-500',
    active: 'bg-green-100 text-green-700',
    paused: 'bg-yellow-100 text-yellow-700',
    completed: 'bg-blue-100 text-blue-600',
  })[status] || 'bg-slate-100 text-slate-500';

const canToggle = c => ['draft', 'paused', 'active'].includes(c.status_jabvox);
const canEdit = c => ['draft', 'paused'].includes(c.status_jabvox);
const canDelete = c => c.status_jabvox !== 'active';

const leadCampaignName = id =>
  leadCampaigns.value.find(c => c.id === id)?.name || '';

// ─── Dialer States ──────────────────────────────────────────────────────────
const showStateForm = ref(false);
const editingStateId = ref(null);
const stateForm = ref({ name: '', color: '#64748b', is_active: true });

const openCreateState = () => {
  editingStateId.value = null;
  stateForm.value = { name: '', color: '#64748b', is_active: true };
  showStateForm.value = true;
};

const openEditState = s => {
  editingStateId.value = s.id;
  stateForm.value = { name: s.name, color: s.color, is_active: s.is_active };
  showStateForm.value = true;
};

const onSaveState = async () => {
  if (!stateForm.value.name) return;
  try {
    if (editingStateId.value) {
      await store.dispatch('jabvoxDialer/updateDialerState', {
        id: editingStateId.value,
        ...stateForm.value,
      });
    } else {
      await store.dispatch('jabvoxDialer/createDialerState', stateForm.value);
    }
    showStateForm.value = false;
    useAlert(t('JABVOX_DIALER.DIALER_STATES.SAVE_SUCCESS'));
  } catch {
    useAlert(t('JABVOX_DIALER.DIALER_STATES.ERROR'));
  }
};

const onDeleteState = async s => {
  if (!window.confirm(t('JABVOX_DIALER.DIALER_STATES.DELETE_CONFIRM'))) return;
  try {
    await store.dispatch('jabvoxDialer/deleteDialerState', s.id);
    useAlert(t('JABVOX_DIALER.DIALER_STATES.DELETED'));
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  }
};

// ─── Permissions ────────────────────────────────────────────────────────────
const savingAccessUserId = ref(null);

const isGranted = userId => {
  const a = dialerAccesses.value.find(x => x.user_id === userId);
  return a?.can_access ?? false;
};

const toggleAccess = async agent => {
  savingAccessUserId.value = agent.id;
  try {
    await store.dispatch('jabvoxDialer/updateDialerAccess', {
      userId: agent.id,
      canAccess: !isGranted(agent.id),
    });
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  } finally {
    savingAccessUserId.value = null;
  }
};

// ─── Init ───────────────────────────────────────────────────────────────────
onMounted(async () => {
  await store.dispatch('jabvoxDialer/fetchCampaigns');
  fetchAllLiveCounts(campaigns.value || []);
  store.dispatch('jabvoxDialer/fetchDialerStates');
  store.dispatch('jabvoxDialer/fetchDialerAccesses');
  store.dispatch('agents/get');
  store.dispatch('jabvoxCampaigns/fetchCampaigns');
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('jabvoxAffiliates/fetchAffiliates');
  store.dispatch('inboxes/get');
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
          {{ t('JABVOX_DIALER.SETTINGS.TITLE') }}
        </h1>
        <Button
          v-if="activeTab === 'campaigns'"
          :label="t('JABVOX_DIALER.CAMPAIGN.NEW')"
          icon="i-lucide-plus"
          @click="openCreateCampaign"
        />
        <Button
          v-if="activeTab === 'states'"
          :label="t('JABVOX_DIALER.DIALER_STATES.NEW')"
          icon="i-lucide-plus"
          @click="openCreateState"
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

    <!-- Scrollable body -->
    <div class="flex-1 overflow-y-auto">
      <!-- ── Campaigns tab ── -->
      <div
        v-if="activeTab === 'campaigns'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-4"
      >
        <div
          v-if="uiFlags.isFetchingCampaigns"
          class="text-sm text-slate-400 text-center py-10"
        >
          {{ t('JABVOX_PRODUCTS.LOADING') }}
        </div>
        <div
          v-else-if="!campaigns.length"
          class="text-sm text-n-slate-10 text-center py-10"
        >
          {{ t('JABVOX_DIALER.CAMPAIGN.EMPTY') }}
        </div>
        <template v-else>
          <div
            v-for="campaign in campaigns"
            :key="campaign.id"
            class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 p-5 space-y-3"
          >
            <!-- Top row: name + status + toggle -->
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-3 flex-wrap">
                  <h4
                    class="text-sm font-semibold text-slate-800 dark:text-slate-100 truncate"
                  >
                    {{ campaign.name_jabvox }}
                  </h4>
                  <span
                    class="text-xs px-2 py-0.5 rounded-full font-medium"
                    :class="campaignStatusColor(campaign.status_jabvox)"
                  >
                    {{
                      t(
                        `JABVOX_DIALER.STATUS.${campaign.status_jabvox.toUpperCase()}`
                      )
                    }}
                  </span>
                </div>
                <!-- Lead campaign & stats row -->
                <div class="flex flex-wrap gap-4 mt-2 text-xs text-slate-500">
                  <span
                    v-if="campaign.jabvox_campaign_id"
                    class="flex items-center gap-1"
                  >
                    <i class="i-lucide-tag text-slate-400" />
                    {{ leadCampaignName(campaign.jabvox_campaign_id) }}
                  </span>
                  <span class="flex items-center gap-1">
                    <i class="i-lucide-users text-slate-400" />
                    {{
                      liveLeadCounts[campaign.id] !== undefined
                        ? liveLeadCounts[campaign.id]
                        : campaign.leads_count_jabvox
                    }}
                    {{ t('JABVOX_DIALER.STATS.LEADS') }}
                  </span>
                  <span
                    v-if="campaign.dialed_count_jabvox"
                    class="flex items-center gap-1"
                  >
                    <i class="i-lucide-phone text-slate-400" />
                    {{ campaign.dialed_count_jabvox }}
                    {{ t('JABVOX_DIALER.CAMPAIGN.DIALED') }}
                  </span>
                  <span
                    v-if="campaign.answered_count_jabvox"
                    class="flex items-center gap-1"
                  >
                    <i class="i-lucide-phone-incoming text-green-500" />
                    {{ campaign.answered_count_jabvox }}
                    {{ t('JABVOX_DIALER.STATS.ANSWERED') }}
                  </span>
                  <span
                    v-if="campaign.countries_jabvox?.length"
                    class="flex items-center gap-1"
                  >
                    <i class="i-lucide-globe text-slate-400" />
                    {{ campaign.countries_jabvox.join(', ') }}
                  </span>
                  <span
                    v-if="campaign.agent_ids_jabvox?.length"
                    class="flex items-center gap-1"
                  >
                    <i class="i-lucide-user-check text-slate-400" />
                    {{ campaign.agent_ids_jabvox.length }}
                    {{ t('JABVOX_DIALER.CAMPAIGN.AGENTS_LABEL') }}
                  </span>
                </div>
              </div>
              <!-- Actions -->
              <div class="flex items-center gap-2 shrink-0">
                <button
                  v-if="canToggle(campaign)"
                  class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors shrink-0"
                  :class="
                    campaign.status_jabvox === 'active'
                      ? 'bg-woot-600'
                      : 'bg-slate-200 dark:bg-slate-700'
                  "
                  :disabled="togglingCampaignId === campaign.id"
                  :title="
                    campaign.status_jabvox === 'active'
                      ? t('JABVOX_DIALER.CAMPAIGN.PAUSE')
                      : t('JABVOX_DIALER.CAMPAIGN.START')
                  "
                  @click="onToggleCampaign(campaign)"
                >
                  <span
                    class="inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform"
                    :class="
                      campaign.status_jabvox === 'active'
                        ? 'translate-x-6'
                        : 'translate-x-1'
                    "
                  />
                </button>
                <button
                  class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-slate-200 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700"
                  @click="openReport(campaign)"
                >
                  <i class="i-lucide-bar-chart-2" />
                  {{ t('JABVOX_DIALER.REPORT.BUTTON') }}
                </button>
                <button
                  v-if="canEdit(campaign)"
                  class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-slate-200 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700"
                  @click="openEditCampaign(campaign)"
                >
                  <i class="i-lucide-pencil" />
                  {{ t('JABVOX_PRODUCTS.EDIT') }}
                </button>
                <button
                  v-if="canDelete(campaign)"
                  class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-lg border border-red-200 text-red-500 hover:bg-red-50"
                  @click="onDeleteCampaign(campaign)"
                >
                  <i class="i-lucide-trash-2" />
                  {{ t('JABVOX_PRODUCTS.DELETE') }}
                </button>
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- ── States tab ── -->
      <div
        v-else-if="activeTab === 'states'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-6"
      >
        <div class="flex items-start justify-between gap-4">
          <p class="text-body-main text-n-slate-11 max-w-lg">
            {{ t('JABVOX_DIALER.DIALER_STATES.DESCRIPTION') }}
          </p>
        </div>

        <div
          v-if="uiFlags.isFetchingStates"
          class="text-sm text-slate-400 text-center py-10"
        >
          {{ t('JABVOX_PRODUCTS.LOADING') }}
        </div>
        <div
          v-else-if="!dialerStates.length"
          class="text-sm text-n-slate-10 text-center py-10"
        >
          {{ t('JABVOX_DIALER.DIALER_STATES.EMPTY') }}
        </div>
        <div
          v-else
          class="rounded-xl border border-slate-200 dark:border-slate-700 overflow-hidden"
        >
          <table
            class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
          >
            <tbody
              class="divide-y divide-slate-100 dark:divide-slate-700 bg-white dark:bg-slate-800"
            >
              <tr
                v-for="s in dialerStates"
                :key="s.id"
                class="hover:bg-slate-50 dark:hover:bg-slate-800/50"
              >
                <td class="px-5 py-3">
                  <div class="flex items-center gap-3">
                    <span
                      class="w-3 h-3 rounded-full shrink-0"
                      :style="{ backgroundColor: s.color }"
                    />
                    <span
                      class="font-medium text-slate-800 dark:text-slate-100"
                    >
                      {{ s.name }}
                    </span>
                    <span
                      v-if="!s.is_active"
                      class="text-xs px-1.5 py-0.5 rounded bg-slate-100 dark:bg-slate-700 text-slate-500"
                    >
                      {{ t('JABVOX_DIALER.DIALER_STATES.INACTIVE') }}
                    </span>
                  </div>
                </td>
                <td class="px-5 py-3 text-right">
                  <div class="flex items-center gap-2 justify-end">
                    <button
                      class="text-xs font-medium px-3 py-1.5 rounded-lg border border-slate-200 dark:border-slate-600 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700"
                      @click="openEditState(s)"
                    >
                      <i class="i-lucide-pencil" />
                    </button>
                    <button
                      class="text-xs font-medium px-3 py-1.5 rounded-lg border border-red-200 text-red-500 hover:bg-red-50"
                      @click="onDeleteState(s)"
                    >
                      <i class="i-lucide-trash-2" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- ── Permissions tab ── -->
      <div
        v-else-if="activeTab === 'permissions'"
        class="max-w-3xl mx-auto px-6 sm:px-8 py-8 space-y-6"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2
              class="text-base font-semibold text-slate-800 dark:text-slate-100"
            >
              {{ t('JABVOX_DIALER.PERMISSIONS.TITLE') }}
            </h2>
            <p class="text-sm text-n-slate-11 mt-1">
              {{ t('JABVOX_DIALER.PERMISSIONS.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <div
          v-if="uiFlags.isFetchingAccesses"
          class="text-sm text-slate-400 animate-pulse py-6 text-center"
        >
          {{ t('JABVOX_PRODUCTS.LOADING') }}
        </div>
        <div
          v-else-if="!agents.length"
          class="text-sm text-n-slate-10 text-center py-8"
        >
          {{ t('JABVOX_DIALER.PERMISSIONS.NO_AGENTS') }}
        </div>
        <div
          v-else
          class="rounded-2xl border border-slate-200 dark:border-slate-700 overflow-hidden"
        >
          <table
            class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm"
          >
            <thead>
              <tr
                class="bg-slate-50 dark:bg-slate-800 text-left text-slate-500 dark:text-slate-400"
              >
                <th class="px-5 py-3 font-medium">
                  {{ t('JABVOX_DIALER.PERMISSIONS.COLS.AGENT') }}
                </th>
                <th class="px-5 py-3 font-medium">
                  {{ t('JABVOX_DIALER.PERMISSIONS.COLS.EMAIL') }}
                </th>
                <th class="px-5 py-3 font-medium">
                  {{ t('JABVOX_DIALER.PERMISSIONS.COLS.ACCESS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
              <tr
                v-for="agent in agents"
                :key="agent.id"
                class="hover:bg-slate-50 dark:hover:bg-slate-800/30"
              >
                <td
                  class="px-5 py-3 font-medium text-slate-800 dark:text-slate-100"
                >
                  {{ agent.name }}
                </td>
                <td class="px-5 py-3 text-slate-500">{{ agent.email }}</td>
                <td class="px-5 py-3">
                  <button
                    class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors"
                    :class="
                      isGranted(agent.id)
                        ? 'bg-woot-600'
                        : 'bg-slate-200 dark:bg-slate-700'
                    "
                    :disabled="savingAccessUserId === agent.id"
                    @click="toggleAccess(agent)"
                  >
                    <span
                      class="inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform"
                      :class="
                        isGranted(agent.id) ? 'translate-x-6' : 'translate-x-1'
                      "
                    />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>

  <!-- ── Campaign create/edit modal ── -->
  <div
    v-if="showCampaignForm"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
  >
    <div
      class="bg-white dark:bg-slate-800 rounded-2xl shadow-xl w-full max-w-lg p-6 space-y-5 overflow-y-auto max-h-[90vh]"
    >
      <!-- Header -->
      <div>
        <div class="flex items-center justify-between mb-1">
          <h3
            class="text-base font-semibold text-slate-800 dark:text-slate-100"
          >
            {{
              editingCampaignId
                ? t('JABVOX_DIALER.CAMPAIGN.EDIT')
                : t('JABVOX_DIALER.CAMPAIGN.NEW')
            }}
          </h3>
          <button
            class="text-slate-400 hover:text-slate-600"
            @click="showCampaignForm = false"
          >
            <i class="i-lucide-x" />
          </button>
        </div>
        <p class="text-xs text-slate-400">
          {{ t('JABVOX_DIALER.CAMPAIGN.FORM_SUBTITLE') }}
        </p>
      </div>

      <div class="space-y-5">
        <!-- Nombre -->
        <div class="space-y-1">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300"
          >
            {{ t('JABVOX_DIALER.FORM.NAME') }} *
          </label>
          <input
            v-model="campaignForm.name_jabvox"
            type="text"
            :placeholder="t('JABVOX_DIALER.FORM.NAME_PLACEHOLDER')"
            class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>

        <!-- Campaña del Lead -->
        <div class="space-y-1">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300"
          >
            {{ t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN') }} *
          </label>
          <ComboBox
            v-model="campaignForm.jabvox_campaign_id"
            :options="leadCampaignOptions"
            :placeholder="t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN_PLACEHOLDER')"
            :search-placeholder="
              t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN_PLACEHOLDER')
            "
          />
        </div>

        <!-- Países -->
        <div class="space-y-2">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ t('JABVOX_DIALER.FORM.COUNTRIES') }}
            </label>
            <p class="text-xs text-slate-400 mt-0.5">
              {{ t('JABVOX_DIALER.FORM.COUNTRIES_HINT') }}
            </p>
          </div>
          <TagMultiSelectComboBox
            v-model="campaignForm.countries_jabvox"
            :options="countryOptions"
            :placeholder="t('JABVOX_DIALER.FORM.COUNTRIES_PLACEHOLDER')"
            :search-placeholder="t('JABVOX_DIALER.FORM.COUNTRIES_SEARCH')"
          />
        </div>

        <!-- Wrap-up + Líneas por agente -->
        <div class="grid grid-cols-2 gap-4">
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ t('JABVOX_DIALER.FORM.WRAPUP_TIME') }}
            </label>
            <input
              v-model.number="campaignForm.wrapup_time_jabvox"
              type="number"
              min="0"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
            <p class="text-xs text-slate-400">
              {{ t('JABVOX_DIALER.FORM.WRAPUP_TIME_HINT') }}
            </p>
          </div>
          <div class="space-y-1">
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ t('JABVOX_DIALER.FORM.LINES_PER_AGENT') }}
            </label>
            <input
              v-model.number="campaignForm.lines_per_agent_jabvox"
              type="number"
              min="1"
              max="10"
              class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
            />
            <p class="text-xs text-slate-400">
              {{ t('JABVOX_DIALER.FORM.LINES_PER_AGENT_HINT') }}
            </p>
          </div>
        </div>

        <!-- Espera en cola -->
        <label
          class="flex items-start gap-3 p-3 rounded-lg border border-slate-200 dark:border-slate-700 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-700/30"
        >
          <input
            v-model="campaignForm.wait_in_queue_jabvox"
            type="checkbox"
            class="mt-0.5 rounded"
          />
          <div class="flex flex-col gap-0.5">
            <span
              class="text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              {{ t('JABVOX_DIALER.FORM.WAIT_IN_QUEUE') }}
            </span>
            <span class="text-xs text-slate-400">
              {{ t('JABVOX_DIALER.FORM.WAIT_IN_QUEUE_HINT') }}
            </span>
          </div>
        </label>

        <!-- Gestiones -->
        <div class="space-y-2">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ t('JABVOX_DIALER.FORM.MANAGEMENT_STATES') }}
            </label>
            <p class="text-xs text-slate-400 mt-0.5">
              {{ t('JABVOX_DIALER.FORM.MANAGEMENT_STATES_HINT') }}
            </p>
          </div>
          <div class="flex flex-col gap-1.5 max-h-44 overflow-y-auto pr-1">
            <!-- Sin gestión -->
            <label
              class="flex items-center gap-2 cursor-pointer text-sm text-slate-700 dark:text-slate-300 select-none"
            >
              <input
                type="checkbox"
                :checked="
                  campaignForm.management_state_ids_jabvox.includes('none')
                "
                class="rounded"
                @change="toggleManagementState('none')"
              />
              {{ t('JABVOX_DIALER.FORM.NO_MANAGEMENT_STATE') }}
            </label>
            <label
              v-for="ms in managementStates"
              :key="ms.id"
              class="flex items-center gap-2 cursor-pointer text-sm text-slate-700 dark:text-slate-300 select-none"
            >
              <input
                type="checkbox"
                :checked="
                  campaignForm.management_state_ids_jabvox.includes(ms.id)
                "
                class="rounded"
                @change="toggleManagementState(ms.id)"
              />
              <span
                class="w-2.5 h-2.5 rounded-full shrink-0"
                :style="{ backgroundColor: ms.color_jabvox }"
              />
              {{ ms.name_jabvox }}
            </label>
          </div>
        </div>

        <!-- Afiliados -->
        <div class="space-y-2">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ t('JABVOX_DIALER.FORM.AFFILIATES') }}
            </label>
            <p class="text-xs text-slate-400 mt-0.5">
              {{ t('JABVOX_DIALER.FORM.AFFILIATES_HINT') }}
            </p>
          </div>
          <TagMultiSelectComboBox
            v-model="campaignForm.affiliate_ids_jabvox"
            :options="affiliateOptions"
            :placeholder="t('JABVOX_DIALER.FORM.AFFILIATES_PLACEHOLDER')"
            :search-placeholder="t('JABVOX_DIALER.FORM.AFFILIATES_SEARCH')"
          />
        </div>

        <!-- Bandejas -->
        <div class="space-y-2">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ t('JABVOX_DIALER.FORM.INBOXES') }}
            </label>
            <p class="text-xs text-slate-400 mt-0.5">
              {{ t('JABVOX_DIALER.FORM.INBOXES_HINT') }}
            </p>
          </div>
          <TagMultiSelectComboBox
            v-model="campaignForm.inbox_ids_jabvox"
            :options="inboxOptions"
            :placeholder="t('JABVOX_DIALER.FORM.INBOXES_PLACEHOLDER')"
            :search-placeholder="t('JABVOX_DIALER.FORM.INBOXES_SEARCH')"
          />
        </div>

        <!-- Agentes -->
        <div class="space-y-2">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-300"
            >
              {{ t('JABVOX_DIALER.FORM.AGENTS') }}
            </label>
            <p class="text-xs text-slate-400 mt-0.5">
              {{ t('JABVOX_DIALER.FORM.AGENTS_HINT') }}
            </p>
          </div>
          <div class="flex flex-col gap-1.5 max-h-36 overflow-y-auto pr-1">
            <label
              v-for="agent in agents"
              :key="agent.id"
              class="flex items-center gap-2 cursor-pointer text-sm text-slate-700 dark:text-slate-300 select-none"
            >
              <input
                type="checkbox"
                :checked="campaignForm.agent_ids_jabvox.includes(agent.id)"
                class="rounded"
                @change="toggleAgent(agent.id)"
              />
              {{ agent.name }}
              <span class="text-xs text-slate-400">{{ agent.email }}</span>
            </label>
          </div>
        </div>
      </div>

      <!-- Lead count -->
      <div
        v-if="campaignForm.jabvox_campaign_id"
        class="rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-700/40 px-4 py-3 flex items-center justify-between"
      >
        <div
          class="flex items-center gap-2 text-sm text-slate-600 dark:text-slate-300"
        >
          <i class="i-lucide-users text-woot-500" />
          {{ t('JABVOX_DIALER.FORM.LEAD_COUNT_LABEL') }}
        </div>
        <div class="text-sm font-semibold">
          <span v-if="loadingLeadCount" class="text-slate-400 animate-pulse">
            {{ t('JABVOX_PRODUCTS.LOADING') }}
          </span>
          <span
            v-else-if="leadCount !== null"
            class="text-woot-600 dark:text-woot-400"
          >
            {{ leadCount.toLocaleString() }}
            {{ t('JABVOX_DIALER.FORM.LEAD_COUNT_UNIT') }}
          </span>
          <span v-else class="text-slate-400">—</span>
        </div>
      </div>

      <!-- Buttons -->
      <div class="flex gap-3 pt-2">
        <button
          class="flex-1 rounded-lg border border-slate-200 dark:border-slate-600 text-sm py-2 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700"
          @click="showCampaignForm = false"
        >
          {{ t('JABVOX_PRODUCTS.CANCEL') }}
        </button>
        <button
          class="flex-1 rounded-lg bg-woot-500 text-white text-sm py-2 font-medium hover:bg-woot-600 disabled:opacity-50"
          :disabled="!campaignForm.name_jabvox || uiFlags.isSaving"
          @click="onSaveCampaign"
        >
          {{
            uiFlags.isSaving
              ? t('JABVOX_PRODUCTS.LOADING')
              : editingCampaignId
                ? t('JABVOX_PRODUCTS.SAVE')
                : t('JABVOX_DIALER.CAMPAIGN.CREATE')
          }}
        </button>
      </div>
    </div>
  </div>

  <!-- ── Report modal ── -->
  <div
    v-if="showReportModal && reportCampaign"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="showReportModal = false"
  >
    <div
      class="bg-white dark:bg-slate-800 rounded-2xl shadow-2xl w-full max-w-3xl mx-4 flex flex-col max-h-[92vh] overflow-hidden"
    >
      <!-- Header -->
      <div
        class="flex items-center justify-between px-6 py-4 border-b border-slate-200 dark:border-slate-700 shrink-0"
      >
        <div>
          <h3
            class="text-base font-semibold text-slate-800 dark:text-slate-100"
          >
            {{ t('JABVOX_DIALER.REPORT.TITLE') }} —
            {{ reportCampaign.name_jabvox }}
          </h3>
          <p v-if="reportDrillDay" class="text-xs text-slate-400 mt-0.5">
            {{ reportDrillDay }}
            <button
              class="ml-2 text-woot-500 hover:underline"
              @click="backToDaily"
            >
              {{ t('JABVOX_DIALER.REPORT.BACK_TO_DAILY') }}
            </button>
          </p>
        </div>
        <button
          class="text-slate-400 hover:text-slate-600 text-lg"
          @click="showReportModal = false"
        >
          <i class="i-lucide-x" />
        </button>
      </div>

      <!-- Filters -->
      <div
        v-if="!reportDrillDay"
        class="px-6 py-3 border-b border-slate-100 dark:border-slate-700 shrink-0 flex flex-wrap gap-3 items-end"
      >
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-slate-500">{{
            t('JABVOX_DIALER.REPORT.FROM')
          }}</label>
          <input
            v-model="reportFrom"
            type="date"
            class="rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs font-medium text-slate-500">{{
            t('JABVOX_DIALER.REPORT.TO')
          }}</label>
          <input
            v-model="reportTo"
            type="date"
            class="rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
        <template v-if="isSingleDay">
          <div class="flex flex-col gap-1">
            <label class="text-xs font-medium text-slate-500">{{
              t('JABVOX_DIALER.REPORT.FROM_HOUR')
            }}</label>
            <select
              v-model.number="reportFromHour"
              class="rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option v-for="h in 24" :key="h - 1" :value="h - 1">
                {{ `${String(h - 1).padStart(2, '0')}:00` }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-xs font-medium text-slate-500">{{
              t('JABVOX_DIALER.REPORT.TO_HOUR')
            }}</label>
            <select
              v-model.number="reportToHour"
              class="rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option v-for="h in 24" :key="h - 1" :value="h - 1">
                {{ `${String(h - 1).padStart(2, '0')}:00` }}
              </option>
            </select>
          </div>
        </template>
        <button
          class="rounded-lg bg-woot-500 text-white text-sm px-4 py-1.5 font-medium hover:bg-woot-600 disabled:opacity-50"
          :disabled="reportLoading"
          @click="fetchReport(isSingleDay ? 'hour' : 'day')"
        >
          {{
            reportLoading
              ? t('JABVOX_PRODUCTS.LOADING')
              : t('JABVOX_DIALER.REPORT.SEARCH')
          }}
        </button>
      </div>

      <!-- Totals cards -->
      <div
        class="px-6 py-4 grid grid-cols-5 gap-3 shrink-0 border-b border-slate-100 dark:border-slate-700"
      >
        <div
          v-for="card in [
            {
              key: 'total',
              label: 'JABVOX_DIALER.REPORT.TOTAL',
              cls: 'text-slate-700',
            },
            {
              key: 'answered',
              label: 'JABVOX_DIALER.REPORT.ANSWERED',
              cls: 'text-green-600',
            },
            {
              key: 'no_answer',
              label: 'JABVOX_DIALER.REPORT.NO_ANSWER',
              cls: 'text-orange-500',
            },
            {
              key: 'no_agent',
              label: 'JABVOX_DIALER.REPORT.NO_AGENT',
              cls: 'text-red-500',
            },
            {
              key: 'agents',
              label: 'JABVOX_DIALER.REPORT.AGENTS',
              cls: 'text-slate-500',
            },
          ]"
          :key="card.key"
          class="bg-slate-50 dark:bg-slate-700/40 rounded-xl p-3 text-center"
        >
          <div class="text-xl font-bold" :class="card.cls">
            {{ reportTotals[card.key] ?? 0 }}
          </div>
          <div class="text-xs text-slate-500 mt-0.5">{{ t(card.label) }}</div>
        </div>
      </div>

      <!-- Table -->
      <div class="flex-1 overflow-y-auto px-6 pb-6">
        <div
          v-if="reportLoading"
          class="py-10 text-center text-sm text-slate-400 animate-pulse"
        >
          {{ t('JABVOX_PRODUCTS.LOADING') }}
        </div>
        <div
          v-else-if="!reportRows.length"
          class="py-10 text-center text-sm text-slate-400"
        >
          {{ t('JABVOX_DIALER.REPORT.EMPTY') }}
        </div>
        <table
          v-else
          class="min-w-full divide-y divide-slate-200 dark:divide-slate-700 text-sm mt-4"
        >
          <thead class="sticky top-0 bg-white dark:bg-slate-800">
            <tr
              class="text-left text-xs font-medium text-slate-500 uppercase tracking-wide"
            >
              <th class="pb-2 pr-4">
                {{ t('JABVOX_DIALER.REPORT.COL_PERIOD') }}
              </th>
              <th class="pb-2 pr-4 text-right">
                {{ t('JABVOX_DIALER.REPORT.TOTAL') }}
              </th>
              <th class="pb-2 pr-4 text-right text-green-600">
                {{ t('JABVOX_DIALER.REPORT.ANSWERED') }}
              </th>
              <th class="pb-2 pr-4 text-right text-orange-500">
                {{ t('JABVOX_DIALER.REPORT.NO_ANSWER') }}
              </th>
              <th class="pb-2 pr-4 text-right text-red-500">
                {{ t('JABVOX_DIALER.REPORT.NO_AGENT') }}
              </th>
              <th class="pb-2 text-right">
                {{ t('JABVOX_DIALER.REPORT.AGENTS') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
            <tr
              v-for="row in reportRows"
              :key="row.period"
              class="hover:bg-slate-50 dark:hover:bg-slate-800/40"
              :class="{ 'cursor-pointer': !reportDrillDay }"
              @click="!reportDrillDay && drillIntoDay(row.period)"
            >
              <td
                class="py-2 pr-4 font-mono text-xs text-slate-700 dark:text-slate-200"
              >
                {{ formatPeriod(row.period, reportDrillDay ? 'hour' : 'day') }}
                <i
                  v-if="!reportDrillDay"
                  class="i-lucide-chevron-right text-slate-300 ml-1"
                />
              </td>
              <td class="py-2 pr-4 text-right font-medium">{{ row.total }}</td>
              <td class="py-2 pr-4 text-right text-green-600">
                {{ row.answered }}
              </td>
              <td class="py-2 pr-4 text-right text-orange-500">
                {{ row.no_answer }}
              </td>
              <td class="py-2 pr-4 text-right text-red-500">
                {{ row.no_agent }}
              </td>
              <td class="py-2 text-right text-slate-500">{{ row.agents }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <!-- ── State create/edit modal ── -->
  <div
    v-if="showStateForm"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    @click.self="showStateForm = false"
  >
    <div
      class="bg-white dark:bg-slate-800 rounded-2xl shadow-xl w-full max-w-sm p-6 space-y-5"
    >
      <div class="flex items-center justify-between">
        <h3 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          {{
            editingStateId
              ? t('JABVOX_DIALER.DIALER_STATES.EDIT')
              : t('JABVOX_DIALER.DIALER_STATES.NEW')
          }}
        </h3>
        <button
          class="text-slate-400 hover:text-slate-600"
          @click="showStateForm = false"
        >
          <i class="i-lucide-x" />
        </button>
      </div>
      <div class="space-y-4">
        <div class="space-y-1">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300"
          >
            {{ t('JABVOX_DIALER.DIALER_STATES.FORM.NAME') }} *
          </label>
          <input
            v-model="stateForm.name"
            type="text"
            :placeholder="
              t('JABVOX_DIALER.DIALER_STATES.FORM.NAME_PLACEHOLDER')
            "
            class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500"
          />
        </div>
        <div class="space-y-1">
          <label
            class="block text-xs font-medium text-slate-600 dark:text-slate-300"
          >
            {{ t('JABVOX_DIALER.DIALER_STATES.FORM.COLOR') }}
          </label>
          <div class="flex items-center gap-3">
            <input
              v-model="stateForm.color"
              type="color"
              class="w-10 h-9 rounded border border-slate-200 dark:border-slate-600 cursor-pointer"
            />
            <span class="text-sm font-mono text-slate-600 dark:text-slate-300">
              {{ stateForm.color }}
            </span>
          </div>
        </div>
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            v-model="stateForm.is_active"
            type="checkbox"
            class="rounded"
          />
          <span class="text-sm text-slate-700 dark:text-slate-300">{{
            t('JABVOX_DIALER.DIALER_STATES.FORM.ACTIVE')
          }}</span>
        </label>
      </div>
      <div class="flex gap-3 pt-2">
        <button
          class="flex-1 rounded-lg border border-slate-200 dark:border-slate-600 text-sm py-2 text-slate-600 hover:bg-slate-50"
          @click="showStateForm = false"
        >
          {{ t('JABVOX_PRODUCTS.CANCEL') }}
        </button>
        <button
          class="flex-1 rounded-lg bg-woot-500 text-white text-sm py-2 font-medium hover:bg-woot-600 disabled:opacity-50"
          :disabled="!stateForm.name || uiFlags.isSavingState"
          @click="onSaveState"
        >
          {{
            uiFlags.isSavingState
              ? t('JABVOX_PRODUCTS.LOADING')
              : t('JABVOX_PRODUCTS.SAVE')
          }}
        </button>
      </div>
    </div>
  </div>
</template>
