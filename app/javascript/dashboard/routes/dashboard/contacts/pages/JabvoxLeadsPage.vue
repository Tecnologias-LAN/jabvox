<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import leadsAPI from 'dashboard/api/jabvox/leads';
import countries from 'shared/constants/countries.js';

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const leads = useMapGetter('jabvoxLeads/getLeads');
const filterOptions = useMapGetter('jabvoxLeads/getFilterOptions');
const meta = useMapGetter('jabvoxLeads/getMeta');
const uiFlags = useMapGetter('jabvoxLeads/getUIFlags');

// ── Filters ────────────────────────────────────────────────────────────
const filterId = ref('');
const filterName = ref('');
const filterEmail = ref('');
const filterPhone = ref('');
const filterCountry = ref('');
const filterCampaign = ref('');
const filterSold = ref('');
const filterAssignee = ref('');
const filterTeam = ref('');
const filterManagementState = ref('');
const filterDateFrom = ref('');
const filterDateTo = ref('');
const filterInbox = ref('');
const filterAffiliate = ref('');
const showAdvancedFilters = ref(false);

const activeAdvancedFilterCount = computed(
  () =>
    [
      filterEmail,
      filterPhone,
      filterCountry,
      filterCampaign,
      filterSold,
      filterAffiliate,
      filterAssignee,
      filterTeam,
      filterManagementState,
      filterDateFrom,
      filterDateTo,
      filterInbox,
    ].filter(f => f.value).length
);
const perPage = ref(25);
const currentPage = ref(1);

// ── Sorting ────────────────────────────────────────────────────────────
const sortColumn = ref('created_at');
const sortDirection = ref('desc');

// ── Selection ──────────────────────────────────────────────────────────
const selectedIds = ref(new Set());
const bulkAssigneeId = ref('');
const isBulkAssigning = ref(false);
const isBulkUnassigning = ref(false);
const pendingBulkAction = ref(null); // null | 'assign' | 'unassign'

const selectedCount = computed(() => selectedIds.value.size);
const hasSelection = computed(() => selectedIds.value.size > 0);

const PER_PAGE_OPTIONS = [10, 25, 50, 100, 200];

const SOLD_OPTIONS = [
  { value: 'quotes', label: t('JABVOX_LEADS.FILTERS.SOLD_QUOTES') },
  { value: 'sales', label: t('JABVOX_LEADS.FILTERS.SOLD_SALES') },
  { value: 'both', label: t('JABVOX_LEADS.FILTERS.SOLD_ANY') },
];

const accountId = computed(() => route.params.accountId);

// ── Fetch (defined first so callers below can reference it) ────────────
const fetchLeads = () => {
  const params = {
    page: currentPage.value,
    per_page: perPage.value,
    sort_column: sortColumn.value,
    sort_direction: sortDirection.value,
  };
  if (filterId.value) params.lead_id = filterId.value;
  if (filterName.value) params.q = filterName.value;
  if (filterEmail.value) params.email = filterEmail.value;
  if (filterPhone.value) params.phone = filterPhone.value;
  if (filterCountry.value) params.country = filterCountry.value;
  if (filterCampaign.value) params.campaign_id = filterCampaign.value;
  if (filterSold.value) params.sold = filterSold.value;
  if (filterAssignee.value) params.assignee_id = filterAssignee.value;
  if (filterTeam.value) params.team_id = filterTeam.value;
  if (filterManagementState.value)
    params.management_state = filterManagementState.value;
  if (filterDateFrom.value) params.date_from = filterDateFrom.value;
  if (filterDateTo.value) params.date_to = filterDateTo.value;
  if (filterInbox.value) params.inbox_id = filterInbox.value;
  if (filterAffiliate.value) params.affiliate_id = filterAffiliate.value;
  store.dispatch('jabvoxLeads/fetchLeads', params);
};

// ── Sorting helpers ────────────────────────────────────────────────────
const toggleSort = col => {
  if (sortColumn.value === col) {
    sortDirection.value = sortDirection.value === 'asc' ? 'desc' : 'asc';
  } else {
    sortColumn.value = col;
    sortDirection.value = 'asc';
  }
  currentPage.value = 1;
  fetchLeads();
};

const sortIcon = col => {
  if (sortColumn.value !== col) return 'i-lucide-chevrons-up-down';
  return sortDirection.value === 'asc'
    ? 'i-lucide-chevron-up'
    : 'i-lucide-chevron-down';
};

// ── Selection helpers ──────────────────────────────────────────────────
const isSelected = id => selectedIds.value.has(id);

const toggleSelect = id => {
  const s = new Set(selectedIds.value);
  if (s.has(id)) s.delete(id);
  else s.add(id);
  selectedIds.value = s;
};

const selectN = n => {
  const ids = leads.value.slice(0, n).map(l => l.id);
  selectedIds.value = new Set(ids);
};

const clearSelection = () => {
  selectedIds.value = new Set();
};

watch(bulkAssigneeId, newVal => {
  if (newVal && hasSelection.value) pendingBulkAction.value = 'assign';
  else if (!newVal) pendingBulkAction.value = null;
});

// ── Bulk actions ───────────────────────────────────────────────────────
const requestBulkUnassign = () => {
  if (!hasSelection.value) return;
  pendingBulkAction.value = 'unassign';
};

const cancelPendingAction = () => {
  pendingBulkAction.value = null;
};

const confirmBulkAssign = async () => {
  isBulkAssigning.value = true;
  const ids = new Set(selectedIds.value);
  const assigneeIdNum = Number(bulkAssigneeId.value);
  const assignee = filterOptions.value.assignees?.find(
    a => a.id === assigneeIdNum
  );
  try {
    await leadsAPI.bulkAssign([...ids], assigneeIdNum);
    store.commit(
      'jabvoxLeads/SET_LEADS',
      leads.value.map(lead =>
        ids.has(lead.id)
          ? {
              ...lead,
              assignee_id: assigneeIdNum,
              assignee_name: assignee?.name,
            }
          : lead
      )
    );
    clearSelection();
    bulkAssigneeId.value = '';
    pendingBulkAction.value = null;
    fetchLeads();
  } catch {
    useAlert('Error al asignar');
  } finally {
    isBulkAssigning.value = false;
  }
};

const confirmBulkUnassign = async () => {
  isBulkUnassigning.value = true;
  const ids = new Set(selectedIds.value);
  try {
    await leadsAPI.bulkUnassign([...ids]);
    store.commit(
      'jabvoxLeads/SET_LEADS',
      leads.value.map(lead =>
        ids.has(lead.id)
          ? { ...lead, assignee_id: null, assignee_name: null }
          : lead
      )
    );
    clearSelection();
    pendingBulkAction.value = null;
    fetchLeads();
  } catch {
    useAlert('Error al desasignar');
  } finally {
    isBulkUnassigning.value = false;
  }
};

// ── ActionCable notification ───────────────────────────────────────────
const currentUser = computed(() => store.getters.getCurrentUser);

const onLeadsAssigned = data => {
  if (data.assignee_id === currentUser.value?.id) {
    useAlert(t('JABVOX_LEADS.BULK.NOTIFICATION', { count: data.count }));
    fetchLeads();
  }
};

// ── Filter helpers ─────────────────────────────────────────────────────
const onFilterChange = () => {
  currentPage.value = 1;
  fetchLeads();
};

const clearFilters = () => {
  filterId.value = '';
  filterName.value = '';
  filterEmail.value = '';
  filterPhone.value = '';
  filterCountry.value = '';
  filterCampaign.value = '';
  filterSold.value = '';
  filterAssignee.value = '';
  filterTeam.value = '';
  filterManagementState.value = '';
  filterDateFrom.value = '';
  filterDateTo.value = '';
  filterInbox.value = '';
  filterAffiliate.value = '';
  currentPage.value = 1;
  fetchLeads();
};

// ── Navigation + formatting ────────────────────────────────────────────
const goToLead = leadId => {
  router.push({
    name: 'jabvox_lead_detail',
    params: { accountId: accountId.value, leadId },
  });
};

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleDateString('es', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
};

// ── Watchers ───────────────────────────────────────────────────────────
watch(
  [
    filterCampaign,
    filterSold,
    filterAffiliate,
    filterAssignee,
    filterTeam,
    filterManagementState,
    filterInbox,
  ],
  onFilterChange
);

watch(perPage, () => {
  currentPage.value = 1;
  fetchLeads();
});

onMounted(async () => {
  emitter.on('jabvox.leads_assigned', onLeadsAssigned);
  try {
    await leadsAPI.syncContacts();
  } catch {
    // ignore
  }
  fetchLeads();
});

onUnmounted(() => {
  emitter.off('jabvox.leads_assigned', onLeadsAssigned);
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <!-- Header -->
    <div
      class="shrink-0 border-b border-n-weak bg-n-surface-1 px-6 sm:px-8 py-5 flex items-center justify-between"
    >
      <h1 class="text-heading-1 text-n-slate-12">
        {{ t('JABVOX_LEADS.TITLE') }}
      </h1>
      <button
        class="flex items-center gap-1.5 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-3 py-1.5 text-sm text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
        @click="
          router.push({
            name: 'contacts_dashboard_index',
            params: { accountId: accountId },
          })
        "
      >
        <span class="i-lucide-users w-4 h-4" />
        {{ t('JABVOX_LEADS.GO_TO_CONTACTS') }}
      </button>
    </div>

    <!-- Content -->
    <div class="flex-1 overflow-auto px-6 sm:px-8 py-5">
      <!-- Filter bar -->
      <div class="mb-4">
        <!-- Primary row: ID + Name + Filters toggle + Clear -->
        <div class="flex flex-wrap items-center gap-2">
          <!-- ID input -->
          <div
            class="flex items-center gap-1.5 px-3 py-1.5 shrink-0 w-32 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800"
          >
            <span
              class="text-xs font-bold font-mono text-slate-400 dark:text-slate-500 select-none shrink-0 leading-none"
              >#</span
            >
            <input
              v-model="filterId"
              type="text"
              :placeholder="t('JABVOX_LEADS.FILTERS.SEARCH_ID')"
              class="flex-1 min-w-0 py-0 appearance-none bg-transparent text-sm leading-none text-slate-700 dark:text-slate-200 focus:outline-none placeholder:text-slate-400 dark:placeholder:text-slate-500"
              @keydown.enter="onFilterChange"
              @blur="onFilterChange"
            />
          </div>
          <!-- Name input -->
          <div
            class="flex items-center gap-2 px-3 py-1.5 shrink-0 w-48 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800"
          >
            <span class="i-lucide-search w-3.5 h-3.5 text-slate-400 shrink-0" />
            <input
              v-model="filterName"
              type="text"
              :placeholder="t('JABVOX_LEADS.FILTERS.NAME')"
              class="flex-1 min-w-0 py-0 appearance-none bg-transparent text-sm leading-none text-slate-700 dark:text-slate-200 focus:outline-none placeholder:text-slate-400 dark:placeholder:text-slate-500"
              @keydown.enter="onFilterChange"
              @blur="onFilterChange"
            />
          </div>
          <!-- Toggle advanced filters -->
          <button
            class="relative h-8 flex shrink-0 items-center gap-1.5 rounded-lg border px-3 text-sm font-medium transition-colors"
            :class="
              showAdvancedFilters
                ? 'border-indigo-400 bg-indigo-50 text-indigo-700 dark:bg-indigo-900/20 dark:text-indigo-300 dark:border-indigo-500'
                : 'border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-700'
            "
            @click="showAdvancedFilters = !showAdvancedFilters"
          >
            <span class="i-lucide-sliders-horizontal w-3.5 h-3.5" />
            {{ t('JABVOX_LEADS.FILTERS.MORE') }}
            <span
              v-if="activeAdvancedFilterCount > 0"
              class="absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] rounded-full bg-indigo-600 text-white text-[10px] font-bold flex items-center justify-center px-1"
            >
              {{ activeAdvancedFilterCount }}
            </span>
          </button>
          <!-- Clear — only when there are active filters -->
          <button
            v-if="filterId || filterName || activeAdvancedFilterCount > 0"
            class="h-8 shrink-0 flex items-center gap-1.5 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-500 dark:text-slate-400 px-3 hover:bg-rose-50 hover:text-rose-600 hover:border-rose-200 dark:hover:bg-rose-900/20 dark:hover:text-rose-400 transition-colors"
            @click="clearFilters"
          >
            <span class="i-lucide-x w-3.5 h-3.5" />
            {{ t('JABVOX_LEADS.FILTERS.CLEAR') }}
          </button>
        </div>

        <!-- Advanced filters panel -->
        <div
          v-if="showAdvancedFilters"
          class="mt-3 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/60 p-4 space-y-3"
        >
          <!-- Row 1: email + phone -->
          <div class="flex gap-2">
            <input
              v-model="filterEmail"
              type="text"
              :placeholder="t('JABVOX_LEADS.FILTERS.EMAIL')"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 w-52 focus:outline-none focus:ring-2 focus:ring-indigo-400"
              @keydown.enter="onFilterChange"
              @blur="onFilterChange"
            />
            <input
              v-model="filterPhone"
              type="text"
              :placeholder="t('JABVOX_LEADS.FILTERS.PHONE')"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 w-40 focus:outline-none focus:ring-2 focus:ring-indigo-400"
              @keydown.enter="onFilterChange"
              @blur="onFilterChange"
            />
          </div>
          <!-- Row 2: selects -->
          <div class="flex flex-wrap gap-2">
            <select
              v-model="filterCountry"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 focus:outline-none focus:ring-2 focus:ring-indigo-400 w-44"
              @change="onFilterChange"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.COUNTRY') }}
              </option>
              <option v-for="c in countries" :key="c.id" :value="c.name">
                {{ c.emoji }} {{ c.name }}
              </option>
            </select>
            <select
              v-model="filterCampaign"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 focus:outline-none focus:ring-2 focus:ring-indigo-400 w-40"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.ALL_CAMPAIGNS') }}
              </option>
              <option
                v-for="c in filterOptions.campaigns"
                :key="c.id"
                :value="c.id"
              >
                {{ c.name }}
              </option>
            </select>
            <select
              v-model="filterSold"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 focus:outline-none focus:ring-2 focus:ring-indigo-400 w-36"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.ALL_SALES') }}
              </option>
              <option v-for="s in SOLD_OPTIONS" :key="s.value" :value="s.value">
                {{ s.label }}
              </option>
            </select>
            <select
              v-model="filterAffiliate"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 focus:outline-none focus:ring-2 focus:ring-indigo-400 w-40"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.ALL_AFFILIATES') }}
              </option>
              <option value="own">
                {{ t('JABVOX_LEADS.FILTERS.OWN_LEADS') }}
              </option>
              <option
                v-for="aff in filterOptions.affiliates"
                :key="aff.id"
                :value="aff.id"
              >
                {{ aff.name }}
              </option>
            </select>
            <select
              v-model="filterAssignee"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 focus:outline-none focus:ring-2 focus:ring-indigo-400 w-40"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.ALL_ASSIGNEES') }}
              </option>
              <option
                v-for="a in filterOptions.assignees"
                :key="a.id"
                :value="a.id"
              >
                {{ a.name }}
              </option>
            </select>
            <select
              v-model="filterTeam"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 focus:outline-none focus:ring-2 focus:ring-indigo-400 w-36"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.ALL_TEAMS') }}
              </option>
              <option
                v-for="team in filterOptions.teams"
                :key="team.id"
                :value="team.id"
              >
                {{ team.name }}
              </option>
            </select>
            <select
              v-model="filterManagementState"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 focus:outline-none focus:ring-2 focus:ring-indigo-400 w-44"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.ALL_MANAGEMENT_STATES') }}
              </option>
              <option
                v-for="ms in filterOptions.management_states"
                :key="ms.id"
                :value="ms.id"
              >
                {{ ms.name }}
              </option>
            </select>
            <select
              v-model="filterInbox"
              class="h-9 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 focus:outline-none focus:ring-2 focus:ring-indigo-400 w-40"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.ALL_INBOXES') }}
              </option>
              <option
                v-for="inbox in filterOptions.inboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>
          </div>

          <!-- Date range — own row so it never overflows -->
          <div
            class="flex items-center gap-3 pt-2 border-t border-slate-200 dark:border-slate-700 flex-wrap"
          >
            <span
              class="text-xs font-medium text-slate-500 dark:text-slate-400 shrink-0 select-none"
            >
              {{ t('JABVOX_LEADS.FILTERS.DATE_RANGE') }}:
            </span>
            <div class="flex items-center gap-2">
              <span class="text-xs text-slate-400 shrink-0 select-none">{{
                t('JABVOX_LEADS.FILTERS.DATE_FROM')
              }}</span>
              <input
                v-model="filterDateFrom"
                type="date"
                class="h-8 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 px-2 focus:outline-none focus:ring-2 focus:ring-indigo-400"
                @change="onFilterChange"
              />
            </div>
            <div class="flex items-center gap-2">
              <span class="text-xs text-slate-400 shrink-0 select-none">{{
                t('JABVOX_LEADS.FILTERS.DATE_TO')
              }}</span>
              <input
                v-model="filterDateTo"
                type="date"
                class="h-8 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 px-2 focus:outline-none focus:ring-2 focus:ring-indigo-400"
                @change="onFilterChange"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Quick-select + Bulk action toolbar -->
      <div class="mb-3 flex flex-wrap items-center gap-3">
        <!-- Quick-select segmented group -->
        <div class="flex items-center gap-1.5">
          <span
            class="text-xs font-medium text-slate-400 dark:text-slate-500 select-none"
          >
            {{ t('JABVOX_LEADS.BULK.SELECT_LABEL') }}
          </span>
          <div
            class="inline-flex rounded-lg overflow-hidden border border-slate-200 dark:border-slate-600"
          >
            <button
              v-for="n in [1, 25, 50, 100]"
              :key="n"
              class="h-7 px-2.5 text-xs font-medium text-slate-600 dark:text-slate-300 bg-white dark:bg-slate-800 hover:bg-slate-50 dark:hover:bg-slate-700 border-r border-slate-200 dark:border-slate-600 last:border-r-0 transition-colors"
              @click="selectN(n)"
            >
              {{ n }}
            </button>
          </div>
        </div>

        <!-- Bulk action bar — appears when rows are selected -->
        <div
          v-if="hasSelection"
          class="flex flex-wrap items-center gap-2 px-3 py-2 rounded-xl bg-slate-100 dark:bg-slate-700 border border-slate-200 dark:border-slate-600"
        >
          <!-- Selected count -->
          <span
            class="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-700 dark:text-slate-200 whitespace-nowrap"
          >
            <span class="i-lucide-check-square w-3.5 h-3.5" />
            {{ t('JABVOX_LEADS.BULK.SELECTED', { n: selectedCount }) }}
          </span>
          <div class="w-px h-5 bg-slate-300 dark:bg-slate-500 shrink-0" />

          <template v-if="!pendingBulkAction">
            <!-- Assignee picker -->
            <div class="flex items-center gap-1.5">
              <span
                class="text-xs text-slate-600 dark:text-slate-300 font-medium shrink-0 select-none"
              >
                {{ t('JABVOX_LEADS.BULK.ASSIGN_LABEL') }}
              </span>
              <select
                v-model="bulkAssigneeId"
                class="h-8 rounded-lg border border-slate-300 dark:border-slate-500 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 pl-3 pr-7 min-w-[160px] focus:outline-none"
              >
                <option value="" disabled>
                  {{ t('JABVOX_LEADS.BULK.ASSIGN_LABEL') }}
                </option>
                <option
                  v-for="a in filterOptions.assignees"
                  :key="a.id"
                  :value="a.id"
                >
                  {{ a.name }}
                </option>
              </select>
            </div>
            <button
              class="h-8 px-3 rounded-lg border border-slate-300 dark:border-slate-500 bg-white dark:bg-slate-800 text-xs font-medium text-slate-600 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-600 transition-colors whitespace-nowrap"
              @click="requestBulkUnassign"
            >
              {{ t('JABVOX_LEADS.BULK.UNASSIGN_BUTTON') }}
            </button>
          </template>
          <template v-else>
            <!-- Confirmation text -->
            <span
              class="text-sm font-semibold text-slate-700 dark:text-slate-200 whitespace-nowrap"
            >
              <template v-if="pendingBulkAction === 'assign'">
                {{
                  t('JABVOX_LEADS.BULK.CONFIRM_ASSIGN', {
                    n: selectedCount,
                    name:
                      filterOptions.assignees?.find(
                        a => a.id === Number(bulkAssigneeId)
                      )?.name || '?',
                  })
                }}
              </template>
              <template v-else>
                {{
                  t('JABVOX_LEADS.BULK.CONFIRM_UNASSIGN', { n: selectedCount })
                }}
              </template>
            </span>
            <button
              :disabled="isBulkAssigning || isBulkUnassigning"
              class="h-8 px-4 rounded-lg bg-n-brand text-white text-sm font-semibold disabled:opacity-40 hover:brightness-110 transition-all flex items-center gap-1.5 whitespace-nowrap"
              @click="
                pendingBulkAction === 'assign'
                  ? confirmBulkAssign()
                  : confirmBulkUnassign()
              "
            >
              <span
                v-if="isBulkAssigning || isBulkUnassigning"
                class="i-lucide-loader-2 w-3.5 h-3.5 animate-spin"
              />
              <template v-else>
                <span class="i-lucide-check w-3.5 h-3.5" />
                {{ t('JABVOX_LEADS.BULK.CONFIRM') }}
              </template>
            </button>
            <button
              class="h-8 px-3 rounded-lg border border-slate-300 dark:border-slate-500 bg-white dark:bg-slate-800 text-xs font-medium text-slate-500 hover:bg-slate-50 transition-colors whitespace-nowrap"
              @click="cancelPendingAction"
            >
              {{ t('JABVOX_LEADS.BULK.CANCEL') }}
            </button>
          </template>

          <!-- Clear selection -->
          <button
            class="h-8 w-8 flex items-center justify-center rounded-lg text-indigo-400 hover:text-indigo-600 hover:bg-indigo-100 dark:hover:bg-indigo-900/40 transition-colors ml-auto"
            @click="clearSelection"
          >
            <span class="i-lucide-x w-4 h-4" />
          </button>
        </div>
      </div>

      <!-- Loading -->
      <div
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center py-20 text-sm text-slate-400 animate-pulse"
      >
        {{ t('JABVOX_LEADS.LOADING') }}
      </div>

      <!-- Empty -->
      <div
        v-else-if="!leads.length"
        class="flex items-center justify-center py-20 text-sm text-slate-400"
      >
        {{ t('JABVOX_LEADS.EMPTY') }}
      </div>

      <!-- Table -->
      <div
        v-else
        class="bg-white dark:bg-slate-800 rounded-2xl border border-slate-200 dark:border-slate-700 shadow-sm overflow-hidden"
      >
        <div class="overflow-x-auto">
          <table class="w-full text-sm border-collapse">
            <thead>
              <tr
                class="bg-slate-50 dark:bg-slate-700/40 border-b border-slate-200 dark:border-slate-700"
              >
                <th class="px-3 py-3 w-8" />
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap hover:text-slate-700 dark:hover:text-slate-300"
                  @click="toggleSort('lead_number')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.ID') }}
                    <span :class="sortIcon('lead_number')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap hover:text-slate-700 dark:hover:text-slate-300"
                  @click="toggleSort('name')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.NAME') }}
                    <span :class="sortIcon('name')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap hover:text-slate-700 dark:hover:text-slate-300"
                  @click="toggleSort('email')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.EMAIL') }}
                    <span :class="sortIcon('email')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap hover:text-slate-700 dark:hover:text-slate-300"
                  @click="toggleSort('phone_number')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.PHONE') }}
                    <span :class="sortIcon('phone_number')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.COUNTRY') }}
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.AFFILIATE') }}
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.CAMPAIGN') }}
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.INBOX') }}
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.MANAGEMENT_STATE') }}
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap hover:text-slate-700 dark:hover:text-slate-300"
                  @click="toggleSort('created_at')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.MANAGEMENT_DATE') }}
                    <span :class="sortIcon('created_at')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.ASSIGNEE') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 dark:divide-slate-700">
              <tr
                v-for="lead in leads"
                :key="lead.id"
                class="cursor-pointer transition-colors hover:bg-slate-50/60 dark:hover:bg-slate-700/20"
                :class="
                  isSelected(lead.id)
                    ? 'bg-indigo-50/60 dark:bg-indigo-900/10'
                    : ''
                "
                @click="goToLead(lead.id)"
              >
                <td class="px-3 py-2.5 w-8" @click.stop>
                  <input
                    type="checkbox"
                    :checked="isSelected(lead.id)"
                    class="rounded text-indigo-600 focus:ring-indigo-500 cursor-pointer"
                    @change="toggleSelect(lead.id)"
                  />
                </td>
                <td class="px-3 py-2.5">
                  <span
                    class="inline-flex items-center gap-0.5 rounded-md bg-blue-50 dark:bg-blue-900/20 px-2 py-0.5 text-xs font-bold font-mono text-blue-600 dark:text-blue-400 ring-1 ring-blue-200 dark:ring-blue-800"
                  >
                    #{{ lead.lead_number }}
                  </span>
                </td>
                <td class="px-3 py-2.5">
                  <div class="flex items-center gap-2">
                    <img
                      v-if="lead.contact.avatar_url"
                      :src="lead.contact.avatar_url"
                      :alt="lead.contact.name"
                      class="w-7 h-7 rounded-full shrink-0 object-cover"
                    />
                    <div
                      v-else
                      class="w-7 h-7 rounded-full bg-indigo-100 dark:bg-indigo-900/30 flex items-center justify-center shrink-0 text-xs font-medium text-indigo-600 dark:text-indigo-400"
                    >
                      {{ lead.contact.name?.charAt(0)?.toUpperCase() || '?' }}
                    </div>
                    <span
                      class="text-sm text-slate-800 dark:text-slate-100 whitespace-nowrap"
                    >
                      {{ lead.contact.name || '—' }}
                    </span>
                  </div>
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-slate-600 dark:text-slate-300 max-w-[180px] truncate"
                >
                  {{ lead.contact.email || '—' }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-slate-600 dark:text-slate-300 whitespace-nowrap"
                >
                  {{ lead.contact.phone_number || '—' }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-slate-600 dark:text-slate-300 whitespace-nowrap"
                >
                  {{ lead.contact.country || '—' }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-slate-600 dark:text-slate-300 whitespace-nowrap"
                >
                  {{
                    lead.affiliate_name || t('JABVOX_LEADS.TABLE.AFFILIATE_OWN')
                  }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-slate-600 dark:text-slate-300 whitespace-nowrap"
                >
                  {{ lead.campaign?.name || '—' }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-slate-600 dark:text-slate-300 whitespace-nowrap"
                >
                  {{ lead.inbox_name || '—' }}
                </td>
                <td class="px-3 py-2.5">
                  <span
                    v-if="lead.last_management_state"
                    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300 whitespace-nowrap"
                  >
                    {{ lead.last_management_state }}
                  </span>
                  <span v-else class="text-sm text-slate-400">—</span>
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-slate-500 dark:text-slate-400 whitespace-nowrap"
                >
                  {{ formatDate(lead.last_management_at) }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-slate-600 dark:text-slate-300 whitespace-nowrap"
                >
                  {{ lead.assignee_name || '—' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Footer: total + per-page + pagination -->
        <div
          class="px-4 py-3 border-t border-slate-100 dark:border-slate-700 flex flex-wrap items-center justify-between gap-3 text-sm text-slate-500"
        >
          <span>{{
            t('JABVOX_LEADS.PAGINATION.TOTAL', { count: meta.total })
          }}</span>

          <div class="flex items-center gap-4">
            <div class="flex items-center gap-2">
              <span class="text-xs text-slate-400">
                {{ t('JABVOX_LEADS.PAGINATION.PER_PAGE') }}:
              </span>
              <select
                v-model="perPage"
                class="h-7 rounded border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-xs text-slate-700 dark:text-slate-200 px-1 focus:outline-none"
              >
                <option v-for="n in PER_PAGE_OPTIONS" :key="n" :value="n">
                  {{ n }}
                </option>
              </select>
            </div>

            <div v-if="meta.totalPages > 1" class="flex items-center gap-2">
              <button
                :disabled="currentPage <= 1"
                class="px-2.5 py-1 rounded border border-slate-200 dark:border-slate-600 disabled:opacity-40 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors text-xs"
                @click="
                  currentPage--;
                  fetchLeads();
                "
              >
                <span class="i-lucide-chevron-left w-3 h-3" />
              </button>
              <span class="text-xs"
                >{{ currentPage }} / {{ meta.totalPages }}</span
              >
              <button
                :disabled="currentPage >= meta.totalPages"
                class="px-2.5 py-1 rounded border border-slate-200 dark:border-slate-600 disabled:opacity-40 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors text-xs"
                @click="
                  currentPage++;
                  fetchLeads();
                "
              >
                <span class="i-lucide-chevron-right w-3 h-3" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
