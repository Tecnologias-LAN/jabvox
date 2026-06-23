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
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

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
const isBulkDeleting = ref(false);
const pendingBulkAction = ref(null); // null | 'assign' | 'unassign' | 'delete'

const selectedCount = computed(() => selectedIds.value.size);
const hasSelection = computed(() => selectedIds.value.size > 0);

const PER_PAGE_OPTIONS = [10, 25, 50, 100, 250];

// ── Pagination helpers (shared by top + bottom bars) ────────────────────
const rangeStart = computed(() =>
  meta.value.total ? (currentPage.value - 1) * perPage.value + 1 : 0
);
const rangeEnd = computed(() =>
  Math.min(currentPage.value * perPage.value, meta.value.total || 0)
);

// ── Page-level selection (Gmail/HubSpot style) ──────────────────────────
const pageIds = computed(() => leads.value.map(l => l.id));
const allPageSelected = computed(
  () =>
    pageIds.value.length > 0 &&
    pageIds.value.every(id => selectedIds.value.has(id))
);
const somePageSelected = computed(
  () =>
    pageIds.value.some(id => selectedIds.value.has(id)) &&
    !allPageSelected.value
);

const toggleSelectPage = () => {
  const s = new Set(selectedIds.value);
  if (allPageSelected.value) {
    pageIds.value.forEach(id => s.delete(id));
  } else {
    pageIds.value.forEach(id => s.add(id));
  }
  selectedIds.value = s;
};

// Reflect the "some-but-not-all" state on the header checkbox.
const pageCheckbox = ref(null);
watch(somePageSelected, val => {
  if (pageCheckbox.value) pageCheckbox.value.indeterminate = val;
});

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

const goToPage = delta => {
  const next = currentPage.value + delta;
  if (next < 1 || next > (meta.value.totalPages || 1)) return;
  currentPage.value = next;
  fetchLeads();
};

// Phone filter accepts digits and a leading + only (strips anything else).
const onPhoneInput = e => {
  filterPhone.value = e.target.value.replace(/[^\d+]/g, '');
};
// ID filter accepts digits only.
const onIdInput = e => {
  filterId.value = e.target.value.replace(/\D/g, '');
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

const requestBulkDelete = () => {
  if (!hasSelection.value) return;
  pendingBulkAction.value = 'delete';
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

const confirmBulkDelete = async () => {
  isBulkDeleting.value = true;
  const ids = [...selectedIds.value];
  try {
    await leadsAPI.bulkDestroy(ids);
    store.commit(
      'jabvoxLeads/SET_LEADS',
      leads.value.filter(lead => !selectedIds.value.has(lead.id))
    );
    clearSelection();
    pendingBulkAction.value = null;
    useAlert(t('JABVOX_LEADS.BULK.DELETE_SUCCESS', { n: ids.length }));
    fetchLeads();
  } catch {
    useAlert(t('JABVOX_LEADS.ERROR'));
  } finally {
    isBulkDeleting.value = false;
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
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-background">
    <!-- Header -->
    <div
      class="shrink-0 border-b border-n-weak bg-n-solid-1 px-4 sm:px-6 lg:px-8 py-4 flex items-start justify-between gap-4"
    >
      <div class="flex items-start gap-3 min-w-0">
        <span
          class="i-lucide-target size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_LEADS.TITLE') }}
          </h1>
          <p class="mt-0.5 text-sm text-n-slate-11">
            {{ t('JABVOX_LEADS.SUBTITLE') }}
            <span v-if="meta.total" class="text-n-slate-10">
              · {{ t('JABVOX_LEADS.PAGINATION.TOTAL', { count: meta.total }) }}
            </span>
          </p>
        </div>
      </div>
      <Button
        :label="t('JABVOX_LEADS.GO_TO_CONTACTS')"
        icon="i-lucide-users"
        variant="outline"
        color="slate"
        size="sm"
        class="shrink-0"
        @click="
          router.push({
            name: 'contacts_dashboard_index',
            params: { accountId: accountId },
          })
        "
      />
    </div>

    <!-- Content -->
    <div class="flex-1 overflow-auto px-4 sm:px-6 lg:px-8 py-5">
      <!-- Filter bar -->
      <div class="mb-4">
        <!-- Primary row: search by name (grows) + ID + filters + clear -->
        <div class="flex flex-wrap items-end gap-3">
          <!-- Name search (primary) -->
          <div class="flex flex-col gap-1 w-full sm:w-64">
            <label class="text-xs font-medium text-n-slate-10 select-none">
              {{ t('JABVOX_LEADS.FILTERS.NAME') }}
            </label>
            <div
              class="flex items-center gap-2 px-3 h-9 rounded-lg border border-n-weak bg-n-solid-1 focus-within:border-n-slate-7 transition-colors"
            >
              <span class="i-lucide-search size-3.5 text-n-slate-9 shrink-0" />
              <input
                v-model="filterName"
                type="text"
                :placeholder="t('JABVOX_LEADS.FILTERS.NAME')"
                class="reset-base flex-1 min-w-0 p-0 m-0 border-0 h-5 appearance-none bg-transparent text-sm leading-5 text-n-slate-12 focus:outline-none focus:ring-0 placeholder:text-n-slate-9"
                @keydown.enter="onFilterChange"
                @blur="onFilterChange"
              />
            </div>
          </div>
          <!-- ID search (own labelled field) -->
          <div class="flex flex-col gap-1 shrink-0 w-40">
            <label class="text-xs font-medium text-n-slate-10 select-none">
              {{ t('JABVOX_LEADS.FILTERS.SEARCH_ID') }}
            </label>
            <div
              class="flex items-center gap-1.5 px-3 h-9 rounded-lg border border-n-weak bg-n-solid-1 focus-within:border-n-slate-7 transition-colors"
            >
              <span class="i-lucide-hash size-3.5 text-n-slate-9 shrink-0" />
              <input
                v-model="filterId"
                type="text"
                inputmode="numeric"
                :placeholder="t('JABVOX_LEADS.FILTERS.SEARCH_ID_PLACEHOLDER')"
                class="reset-base flex-1 min-w-0 p-0 m-0 border-0 h-5 appearance-none bg-transparent text-sm leading-5 font-mono text-n-slate-12 focus:outline-none focus:ring-0 placeholder:text-n-slate-9"
                @input="onIdInput"
                @keydown.enter="onFilterChange"
                @blur="onFilterChange"
              />
            </div>
          </div>
          <!-- Toggle advanced filters -->
          <button
            class="relative h-9 flex shrink-0 items-center gap-1.5 rounded-lg border px-3 text-sm font-medium transition-colors"
            :class="
              showAdvancedFilters
                ? 'border-n-brand/40 bg-n-alpha-2 text-n-brand'
                : 'border-n-weak bg-n-solid-1 text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="showAdvancedFilters = !showAdvancedFilters"
          >
            <span class="i-lucide-sliders-horizontal size-3.5" />
            {{ t('JABVOX_LEADS.FILTERS.MORE') }}
            <span
              v-if="activeAdvancedFilterCount > 0"
              class="absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] rounded-full bg-n-brand text-white text-[10px] font-bold flex items-center justify-center px-1"
            >
              {{ activeAdvancedFilterCount }}
            </span>
          </button>
          <!-- Clear — only when there are active filters -->
          <button
            v-if="filterId || filterName || activeAdvancedFilterCount > 0"
            class="h-9 shrink-0 flex items-center gap-1.5 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-10 px-3 hover:bg-n-ruby-3 hover:text-n-ruby-11 hover:border-n-ruby-6 transition-colors"
            @click="clearFilters"
          >
            <span class="i-lucide-x size-3.5" />
            {{ t('JABVOX_LEADS.FILTERS.CLEAR') }}
          </button>
        </div>

        <!-- Advanced filters panel -->
        <div
          v-if="showAdvancedFilters"
          class="mt-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 space-y-3 shadow-sm"
        >
          <!-- Row 1: email + phone -->
          <div class="flex flex-wrap gap-2">
            <input
              v-model="filterEmail"
              type="text"
              :placeholder="t('JABVOX_LEADS.FILTERS.EMAIL')"
              class="reset-base h-9 rounded-lg border border-n-weak bg-n-background text-sm text-n-slate-12 placeholder:text-n-slate-9 px-3 w-52 focus:outline-none focus:border-n-slate-7 transition-colors"
              @keydown.enter="onFilterChange"
              @blur="onFilterChange"
            />
            <input
              v-model="filterPhone"
              type="tel"
              inputmode="numeric"
              :placeholder="t('JABVOX_LEADS.FILTERS.PHONE')"
              class="reset-base h-9 rounded-lg border border-n-weak bg-n-background text-sm text-n-slate-12 placeholder:text-n-slate-9 px-3 w-40 focus:outline-none focus:border-n-slate-7 transition-colors"
              @input="onPhoneInput"
              @keydown.enter="onFilterChange"
              @blur="onFilterChange"
            />
          </div>
          <!-- Row 2: selects -->
          <div
            class="flex flex-wrap gap-2 [&_select]:reset-base [&_select]:h-9 [&_select]:rounded-lg [&_select]:border [&_select]:border-n-weak [&_select]:bg-n-background [&_select]:text-sm [&_select]:text-n-slate-12 [&_select]:pl-3 [&_select]:pr-7 [&_select]:focus:outline-none [&_select]:focus:border-n-slate-7"
          >
            <select
              v-model="filterCountry"
              class="w-44"
              @change="onFilterChange"
            >
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.COUNTRY') }}
              </option>
              <option v-for="c in countries" :key="c.id" :value="c.name">
                {{ c.emoji }} {{ c.name }}
              </option>
            </select>
            <select v-model="filterCampaign" class="w-40">
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
            <select v-model="filterSold" class="w-36">
              <option value="">
                {{ t('JABVOX_LEADS.FILTERS.ALL_SALES') }}
              </option>
              <option v-for="s in SOLD_OPTIONS" :key="s.value" :value="s.value">
                {{ s.label }}
              </option>
            </select>
            <select v-model="filterAffiliate" class="w-40">
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
            <select v-model="filterAssignee" class="w-40">
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
            <select v-model="filterTeam" class="w-36">
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
            <select v-model="filterManagementState" class="w-44">
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
            <select v-model="filterInbox" class="w-40">
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
            class="flex items-center gap-3 pt-3 border-t border-n-weak flex-wrap"
          >
            <span
              class="text-xs font-medium text-n-slate-10 shrink-0 select-none"
            >
              {{ t('JABVOX_LEADS.FILTERS.DATE_RANGE') }}:
            </span>
            <div class="flex items-center gap-2">
              <span class="text-xs text-n-slate-9 shrink-0 select-none">{{
                t('JABVOX_LEADS.FILTERS.DATE_FROM')
              }}</span>
              <input
                v-model="filterDateFrom"
                type="date"
                class="reset-base h-9 rounded-lg border border-n-weak bg-n-background text-sm text-n-slate-12 px-2.5 focus:outline-none focus:border-n-slate-7 transition-colors"
                @change="onFilterChange"
              />
            </div>
            <div class="flex items-center gap-2">
              <span class="text-xs text-n-slate-9 shrink-0 select-none">{{
                t('JABVOX_LEADS.FILTERS.DATE_TO')
              }}</span>
              <input
                v-model="filterDateTo"
                type="date"
                class="reset-base h-9 rounded-lg border border-n-weak bg-n-background text-sm text-n-slate-12 px-2.5 focus:outline-none focus:border-n-slate-7 transition-colors"
                @change="onFilterChange"
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Top summary + pagination bar -->
      <div
        v-if="!uiFlags.isFetching && leads.length"
        class="mb-3 flex flex-wrap items-center justify-between gap-3"
      >
        <!-- Showing X-Y of N -->
        <p class="text-sm text-n-slate-11">
          {{
            t('JABVOX_LEADS.PAGINATION.SHOWING', {
              from: rangeStart,
              to: rangeEnd,
              total: meta.total,
            })
          }}
        </p>
        <!-- Per-page + nav -->
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <span class="text-xs text-n-slate-10 select-none">
              {{ t('JABVOX_LEADS.PAGINATION.PER_PAGE') }}
            </span>
            <select
              v-model="perPage"
              class="reset-base h-8 rounded-lg border border-n-weak bg-n-solid-1 text-xs text-n-slate-12 pl-2.5 pr-7 focus:outline-none focus:border-n-slate-7"
            >
              <option v-for="n in PER_PAGE_OPTIONS" :key="n" :value="n">
                {{ n }}
              </option>
            </select>
          </div>
          <div v-if="meta.totalPages > 1" class="flex items-center gap-1.5">
            <button
              :disabled="currentPage <= 1"
              class="size-8 flex items-center justify-center rounded-lg border border-n-weak bg-n-solid-1 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-n-alpha-1 transition-colors"
              @click="goToPage(-1)"
            >
              <span class="i-lucide-chevron-left size-3.5" />
            </button>
            <span class="text-xs text-n-slate-11 tabular-nums px-1">
              {{ currentPage }} / {{ meta.totalPages }}
            </span>
            <button
              :disabled="currentPage >= meta.totalPages"
              class="size-8 flex items-center justify-center rounded-lg border border-n-weak bg-n-solid-1 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-n-alpha-1 transition-colors"
              @click="goToPage(1)"
            >
              <span class="i-lucide-chevron-right size-3.5" />
            </button>
          </div>
        </div>
      </div>

      <!-- Bulk action toolbar -->
      <div v-if="hasSelection" class="mb-3 flex flex-wrap items-center gap-3">
        <!-- Bulk action bar -->
        <div
          class="w-full flex flex-wrap items-center gap-2 px-3 py-2 rounded-xl bg-n-alpha-2 border border-n-weak shadow-sm"
        >
          <!-- Selected count -->
          <span
            class="inline-flex items-center gap-1.5 text-xs font-semibold text-n-slate-12 whitespace-nowrap"
          >
            <span class="i-lucide-check-square size-3.5 text-n-brand" />
            {{ t('JABVOX_LEADS.BULK.SELECTED', { n: selectedCount }) }}
          </span>
          <div class="w-px h-5 bg-n-weak shrink-0" />

          <template v-if="!pendingBulkAction">
            <!-- Assignee picker -->
            <div class="flex items-center gap-1.5">
              <span
                class="text-xs text-n-slate-11 font-medium shrink-0 select-none"
              >
                {{ t('JABVOX_LEADS.BULK.ASSIGN_LABEL') }}
              </span>
              <select
                v-model="bulkAssigneeId"
                class="reset-base h-8 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 pl-3 pr-7 min-w-[160px] focus:outline-none focus:border-n-slate-7"
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
              class="h-8 px-3 rounded-lg border border-n-weak bg-n-solid-1 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-1 transition-colors whitespace-nowrap"
              @click="requestBulkUnassign"
            >
              {{ t('JABVOX_LEADS.BULK.UNASSIGN_BUTTON') }}
            </button>
            <button
              class="h-8 px-3 rounded-lg border border-n-ruby-6 bg-n-solid-1 text-xs font-medium text-n-ruby-11 hover:bg-n-ruby-3 transition-colors whitespace-nowrap"
              @click="requestBulkDelete"
            >
              {{ t('JABVOX_LEADS.BULK.DELETE_BUTTON') }}
            </button>
          </template>
          <template v-else>
            <!-- Confirmation text -->
            <span
              class="text-sm font-semibold text-n-slate-12 whitespace-nowrap"
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
              <template v-else-if="pendingBulkAction === 'unassign'">
                {{
                  t('JABVOX_LEADS.BULK.CONFIRM_UNASSIGN', { n: selectedCount })
                }}
              </template>
              <template v-else>
                {{
                  t('JABVOX_LEADS.BULK.CONFIRM_DELETE', { n: selectedCount })
                }}
              </template>
            </span>
            <button
              :disabled="isBulkAssigning || isBulkUnassigning || isBulkDeleting"
              class="h-8 px-4 rounded-lg text-white text-sm font-semibold disabled:opacity-40 hover:brightness-110 transition-all flex items-center gap-1.5 whitespace-nowrap"
              :class="
                pendingBulkAction === 'delete' ? 'bg-n-ruby-9' : 'bg-n-brand'
              "
              @click="
                pendingBulkAction === 'assign'
                  ? confirmBulkAssign()
                  : pendingBulkAction === 'delete'
                    ? confirmBulkDelete()
                    : confirmBulkUnassign()
              "
            >
              <span
                v-if="isBulkAssigning || isBulkUnassigning || isBulkDeleting"
                class="i-lucide-loader-2 size-3.5 animate-spin"
              />
              <template v-else>
                <span class="i-lucide-check size-3.5" />
                {{ t('JABVOX_LEADS.BULK.CONFIRM') }}
              </template>
            </button>
            <button
              class="h-8 px-3 rounded-lg border border-n-weak bg-n-solid-1 text-xs font-medium text-n-slate-10 hover:bg-n-alpha-1 transition-colors whitespace-nowrap"
              @click="cancelPendingAction"
            >
              {{ t('JABVOX_LEADS.BULK.CANCEL') }}
            </button>
          </template>

          <!-- Clear selection -->
          <button
            class="h-8 w-8 flex items-center justify-center rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-1 transition-colors ml-auto"
            @click="clearSelection"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>
      </div>

      <!-- Loading -->
      <div
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center gap-2 py-20 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_LEADS.LOADING') }}
      </div>

      <!-- Empty -->
      <EmptyStateLayout
        v-else-if="!leads.length"
        :title="t('JABVOX_LEADS.EMPTY_TITLE')"
        :subtitle="t('JABVOX_LEADS.EMPTY')"
      />

      <!-- Table -->
      <div
        v-else
        class="bg-n-solid-1 rounded-2xl border border-n-weak shadow-sm overflow-hidden"
      >
        <div class="overflow-x-auto max-h-[calc(100vh-22rem)]">
          <table class="w-full text-sm border-collapse">
            <thead class="sticky top-0 z-10">
              <tr class="bg-n-alpha-1 border-b border-n-weak">
                <th class="px-3 py-3 w-8 bg-n-alpha-1">
                  <input
                    ref="pageCheckbox"
                    type="checkbox"
                    :checked="allPageSelected"
                    class="rounded accent-n-brand cursor-pointer align-middle"
                    :title="t('JABVOX_LEADS.BULK.SELECT_PAGE')"
                    @change="toggleSelectPage"
                  />
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap hover:text-n-slate-12 transition-colors"
                  @click="toggleSort('lead_number')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.ID') }}
                    <span :class="sortIcon('lead_number')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap hover:text-n-slate-12 transition-colors"
                  @click="toggleSort('name')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.NAME') }}
                    <span :class="sortIcon('name')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap hover:text-n-slate-12 transition-colors"
                  @click="toggleSort('email')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.EMAIL') }}
                    <span :class="sortIcon('email')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap hover:text-n-slate-12 transition-colors"
                  @click="toggleSort('phone_number')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.PHONE') }}
                    <span :class="sortIcon('phone_number')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.COUNTRY') }}
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.AFFILIATE') }}
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.CAMPAIGN') }}
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.INBOX') }}
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.MANAGEMENT_STATE') }}
                </th>
                <th
                  class="cursor-pointer select-none text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap hover:text-n-slate-12 transition-colors"
                  @click="toggleSort('created_at')"
                >
                  <span class="flex items-center gap-1">
                    {{ t('JABVOX_LEADS.TABLE.MANAGEMENT_DATE') }}
                    <span :class="sortIcon('created_at')" class="w-3 h-3" />
                  </span>
                </th>
                <th
                  class="text-left px-3 py-3 text-xs font-semibold text-n-slate-10 uppercase tracking-wide whitespace-nowrap"
                >
                  {{ t('JABVOX_LEADS.TABLE.ASSIGNEE') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="lead in leads"
                :key="lead.id"
                class="cursor-pointer transition-colors group/row"
                :class="
                  isSelected(lead.id)
                    ? 'bg-n-alpha-2'
                    : 'odd:bg-transparent even:bg-n-alpha-1/40 hover:!bg-n-alpha-1'
                "
                @click="goToLead(lead.id)"
              >
                <td class="px-3 py-2.5 w-8" @click.stop>
                  <input
                    type="checkbox"
                    :checked="isSelected(lead.id)"
                    class="rounded accent-n-brand cursor-pointer"
                    @change="toggleSelect(lead.id)"
                  />
                </td>
                <td class="px-3 py-2.5">
                  <span
                    class="inline-flex items-center gap-0.5 rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs font-bold font-mono text-n-brand ring-1 ring-inset ring-n-brand/20"
                  >
                    #{{ lead.lead_number }}
                  </span>
                </td>
                <td class="px-3 py-2.5">
                  <div class="flex items-center gap-2">
                    <Avatar
                      :name="lead.contact.name || '?'"
                      :src="lead.contact.avatar_url"
                      :size="28"
                      rounded-full
                    />
                    <span class="text-sm text-n-slate-12 whitespace-nowrap">
                      {{ lead.contact.name || '—' }}
                    </span>
                  </div>
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-n-slate-11 max-w-[180px] truncate"
                >
                  {{ lead.contact.email || '—' }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-n-slate-11 whitespace-nowrap"
                >
                  {{ lead.contact.phone_number || '—' }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-n-slate-11 whitespace-nowrap"
                >
                  {{ lead.contact.country || '—' }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-n-slate-11 whitespace-nowrap"
                >
                  {{
                    lead.affiliate_name || t('JABVOX_LEADS.TABLE.AFFILIATE_OWN')
                  }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-n-slate-11 whitespace-nowrap"
                >
                  {{ lead.campaign?.name || '—' }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-n-slate-11 whitespace-nowrap"
                >
                  {{ lead.inbox_name || '—' }}
                </td>
                <td class="px-3 py-2.5">
                  <span
                    v-if="lead.last_management_state"
                    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-n-alpha-2 text-n-brand whitespace-nowrap"
                  >
                    {{ lead.last_management_state }}
                  </span>
                  <span v-else class="text-sm text-n-slate-9">—</span>
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-n-slate-10 whitespace-nowrap"
                >
                  {{ formatDate(lead.last_management_at) }}
                </td>
                <td
                  class="px-3 py-2.5 text-sm text-n-slate-11 whitespace-nowrap"
                >
                  {{ lead.assignee_name || '—' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Footer: showing range + per-page + pagination (synced with top) -->
        <div
          class="px-4 py-3 border-t border-n-weak flex flex-wrap items-center justify-between gap-3 text-sm text-n-slate-10"
        >
          <span>
            {{
              t('JABVOX_LEADS.PAGINATION.SHOWING', {
                from: rangeStart,
                to: rangeEnd,
                total: meta.total,
              })
            }}
          </span>

          <div class="flex items-center gap-4">
            <div class="flex items-center gap-2">
              <span class="text-xs text-n-slate-9">
                {{ t('JABVOX_LEADS.PAGINATION.PER_PAGE') }}:
              </span>
              <select
                v-model="perPage"
                class="reset-base h-8 rounded-lg border border-n-weak bg-n-solid-1 text-xs text-n-slate-12 pl-2.5 pr-7 focus:outline-none focus:border-n-slate-7"
              >
                <option v-for="n in PER_PAGE_OPTIONS" :key="n" :value="n">
                  {{ n }}
                </option>
              </select>
            </div>

            <div v-if="meta.totalPages > 1" class="flex items-center gap-1.5">
              <button
                :disabled="currentPage <= 1"
                class="size-8 flex items-center justify-center rounded-lg border border-n-weak bg-n-solid-1 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-n-alpha-1 transition-colors"
                @click="goToPage(-1)"
              >
                <span class="i-lucide-chevron-left size-3.5" />
              </button>
              <span class="text-xs text-n-slate-11 tabular-nums px-1">
                {{ currentPage }} / {{ meta.totalPages }}
              </span>
              <button
                :disabled="currentPage >= meta.totalPages"
                class="size-8 flex items-center justify-center rounded-lg border border-n-weak bg-n-solid-1 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-n-alpha-1 transition-colors"
                @click="goToPage(1)"
              >
                <span class="i-lucide-chevron-right size-3.5" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
