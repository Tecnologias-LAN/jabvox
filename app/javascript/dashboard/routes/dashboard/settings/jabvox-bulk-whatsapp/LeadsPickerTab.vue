<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import leadsAPI from 'dashboard/api/jabvox/leads';
import bulkWhatsappAPI from 'dashboard/api/jabvox/bulkWhatsapp';

const props = defineProps({
  inboxId: { type: [Number, String], default: '' },
  senderUserId: { type: [Number, String], default: '' },
  // 'template' | 'text' | null — derived from the inbox by the parent.
  mode: { type: String, default: null },
  configReady: { type: Boolean, default: false },
  responseEmail: { type: String, default: '' },
  emailValid: { type: Boolean, default: false },
});

const emit = defineEmits(['sent']);

const { t } = useI18n();
const rootStore = useStore();

const PER_PAGE = 25;

// ── Filters ────────────────────────────────────────────────────────────────
// Mirrors every filter the leads list supports (Jabvox::LeadsFilterService).
const filters = ref({
  q: '',
  email: '',
  phone: '',
  country: '',
  campaign_id: '',
  assignee_id: '',
  team_id: '',
  inbox_id: '',
  affiliate_id: '',
  management_state: '',
  sold: '',
  status: '',
  date_from: '',
  date_to: '',
});
// Select options returned by the leads index (campaigns, assignees, teams…).
const filterOptions = ref({});
const SOLD_OPTIONS = ['quotes', 'sales'];
const STATUS_OPTIONS = ['open', 'pending', 'snoozed', 'resolved'];
// Lead custom-field definitions + the current filter value for each one.
const customFields = ref([]);
const customValues = ref({});
// Filters panel can be collapsed to keep the view uncluttered.
const filtersOpen = ref(false);

// A custom-field value counts as "set" when it's a non-empty string OR a
// non-empty array (option selectors store an array of chosen options).
const customValueIsSet = v =>
  Array.isArray(v) ? v.length > 0 : `${v ?? ''}`.trim().length > 0;

// How many filters currently have a value (shown as a badge when collapsed).
const activeFilterCount = computed(() => {
  const base = Object.values(filters.value).filter(v =>
    `${v ?? ''}`.trim()
  ).length;
  const custom = Object.values(customValues.value).filter(
    customValueIsSet
  ).length;
  return base + custom;
});

// Every custom field is offered as a checkbox selector as long as it has known
// values (options come from the field definition AND the values discovered in
// the leads). Only fields with no discoverable values fall back to a text input.
const fieldHasOptions = cf =>
  Array.isArray(cf.options) && cf.options.length > 0;

// Per-field search text inside its options dropdown (for fields with many values).
const optionSearch = ref({});
const filteredOptions = cf => {
  const q = (optionSearch.value[cf.key] || '').trim().toLowerCase();
  const opts = cf.options || [];
  if (!q) return opts;
  return opts.filter(o => String(o).toLowerCase().includes(q));
};

// ── Lead list / pagination ───────────────────────────────────────────────
const leads = ref([]);
const total = ref(0);
const page = ref(1);
const loading = ref(false);

// ── Selection ────────────────────────────────────────────────────────────
// selectAll = every lead matching the filter (across pages), minus `excluded`.
// Otherwise `selectedIds` holds explicit picks.
const selectAll = ref(false);
const selectedIds = ref(new Set());
const excludedIds = ref(new Set());

// ── Message body ──────────────────────────────────────────────────────────
const templateName = ref('');
const language = ref('');
const text = ref('');
const sending = ref(false);

const totalPages = computed(() =>
  Math.max(1, Math.ceil(total.value / PER_PAGE))
);

// Templates of the chosen inbox (official WhatsApp only).
const inboxTemplates = computed(() => {
  if (!props.inboxId) return [];
  const tpls =
    rootStore.getters['inboxes/getWhatsAppTemplates'](props.inboxId) || [];
  // Only approved templates are usable.
  return tpls.filter(tp => (tp.status || '').toUpperCase() === 'APPROVED');
});

const activeFilters = computed(() => {
  const f = {};
  Object.entries(filters.value).forEach(([k, v]) => {
    if (v !== '' && v != null) f[k] = v;
  });
  // Custom-field filters go under `custom` as { field_key: value }. Value is an
  // array (option selectors) or a string (text/number); both are honored by the
  // backend LeadsFilterService.
  const custom = {};
  Object.entries(customValues.value).forEach(([k, v]) => {
    if (customValueIsSet(v)) custom[k] = v;
  });
  if (Object.keys(custom).length) f.custom = custom;
  return f;
});

const selectedCount = computed(() => {
  if (selectAll.value) return Math.max(0, total.value - excludedIds.value.size);
  return selectedIds.value.size;
});

const isRowChecked = id =>
  selectAll.value ? !excludedIds.value.has(id) : selectedIds.value.has(id);

const canSend = computed(
  () =>
    props.configReady &&
    props.emailValid &&
    !!props.inboxId &&
    !!props.senderUserId &&
    !!props.mode &&
    selectedCount.value > 0 &&
    (props.mode === 'template'
      ? !!templateName.value && !!language.value
      : !!text.value.trim())
);

const loadLeads = async () => {
  loading.value = true;
  try {
    const { data } = await leadsAPI.getAll({
      ...activeFilters.value,
      page: page.value,
      per_page: PER_PAGE,
    });
    // The leads index responds with { data: [...], meta: { total }, filter_options }.
    const list = Array.isArray(data?.data) ? data.data : data;
    leads.value = Array.isArray(list) ? list : [];
    total.value = data?.meta?.total ?? leads.value.length;
    if (data?.filter_options) filterOptions.value = data.filter_options;
  } catch {
    useAlert(t('JABVOX_BULK_WA.LEADS.ERROR'));
  } finally {
    loading.value = false;
  }
};

const applyFilters = () => {
  page.value = 1;
  // Changing the filter resets the "all" selection to avoid sending to an unexpected set.
  selectAll.value = false;
  selectedIds.value = new Set();
  excludedIds.value = new Set();
  loadLeads();
};

const clearFilters = () => {
  Object.keys(filters.value).forEach(k => {
    filters.value[k] = '';
  });
  customValues.value = {};
  applyFilters();
};

// Toggle an option in a field's selected-values array, then re-run the filter.
const toggleCustomOption = (key, option) => {
  const current = Array.isArray(customValues.value[key])
    ? customValues.value[key]
    : [];
  customValues.value[key] = current.includes(option)
    ? current.filter(o => o !== option)
    : [...current, option];
  applyFilters();
};

const goToPage = p => {
  if (p < 1 || p > totalPages.value) return;
  page.value = p;
  loadLeads();
};

const toggleRow = id => {
  if (selectAll.value) {
    if (excludedIds.value.has(id)) excludedIds.value.delete(id);
    else excludedIds.value.add(id);
    excludedIds.value = new Set(excludedIds.value);
  } else {
    if (selectedIds.value.has(id)) selectedIds.value.delete(id);
    else selectedIds.value.add(id);
    selectedIds.value = new Set(selectedIds.value);
  }
};

const toggleSelectAll = () => {
  selectAll.value = !selectAll.value;
  selectedIds.value = new Set();
  excludedIds.value = new Set();
};

const clearSelection = () => {
  selectAll.value = false;
  selectedIds.value = new Set();
  excludedIds.value = new Set();
};

const onSend = async () => {
  if (!canSend.value) return;
  sending.value = true;
  try {
    await bulkWhatsappAPI.sendLeads({
      inboxId: props.inboxId,
      senderUserId: props.senderUserId,
      responseEmail: props.responseEmail,
      all: selectAll.value,
      leadIds: selectAll.value ? [] : [...selectedIds.value],
      excludedIds: selectAll.value ? [...excludedIds.value] : [],
      filters: activeFilters.value,
      templateName: props.mode === 'template' ? templateName.value : undefined,
      language: props.mode === 'template' ? language.value : undefined,
      text: props.mode === 'text' ? text.value : undefined,
    });
    useAlert(t('JABVOX_BULK_WA.SEND.SUCCESS'));
    clearSelection();
    emit('sent');
  } catch (error) {
    useAlert(error?.response?.data?.error || t('JABVOX_BULK_WA.SEND.ERROR'));
  } finally {
    sending.value = false;
  }
};

const contactName = lead => lead.contact?.name || lead.name || '—';
const contactPhone = lead => lead.contact?.phone_number || lead.phone || '—';

watch(
  () => props.inboxId,
  () => {
    templateName.value = '';
    language.value = '';
  }
);

// The language is a property of the selected template in Meta, so it must
// match exactly. Derive it from the chosen template instead of letting the
// user type a value that could mismatch and fail the send.
watch(templateName, name => {
  const tpl = inboxTemplates.value.find(tp => tp.name === name);
  language.value = tpl?.language || '';
});

const loadCustomFields = async () => {
  try {
    const { data } = await bulkWhatsappAPI.getLeadFields();
    customFields.value = data.custom || [];
  } catch {
    customFields.value = [];
  }
};

onMounted(() => {
  rootStore.dispatch('inboxes/get');
  loadCustomFields();
  loadLeads();
});
</script>

<template>
  <div class="space-y-4">
    <!-- Config required -->
    <div
      v-if="!configReady"
      class="flex items-start gap-3 rounded-xl border border-n-amber-6 bg-n-amber-3 px-4 py-3"
    >
      <span
        class="i-lucide-triangle-alert size-5 text-n-amber-11 shrink-0 mt-0.5"
        aria-hidden="true"
      />
      <p class="text-sm text-n-amber-12">
        {{ t('JABVOX_BULK_WA.SEND.CONFIG_REQUIRED_BODY') }}
      </p>
    </div>

    <!-- Filters (collapsible) -->
    <section class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm">
      <button
        type="button"
        class="flex items-center justify-between w-full px-4 py-3"
        @click="filtersOpen = !filtersOpen"
      >
        <span
          class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
        >
          <span
            class="i-lucide-sliders-horizontal size-4 text-n-slate-10"
            aria-hidden="true"
          />
          {{ t('JABVOX_BULK_WA.LEADS.FILTERS') }}
          <span
            v-if="activeFilterCount"
            class="inline-flex items-center justify-center min-w-5 h-5 px-1.5 text-[11px] font-semibold rounded-full bg-n-brand text-white"
          >
            {{ activeFilterCount }}
          </span>
        </span>
        <span
          :class="filtersOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          class="size-4 text-n-slate-10"
          aria-hidden="true"
        />
      </button>

      <div v-show="filtersOpen" class="px-4 pb-4 space-y-3">
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_NAME') }}
            </label>
            <input
              v-model="filters.q"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="t('JABVOX_BULK_WA.LEADS.FILTER_NAME')"
              @keyup.enter="applyFilters"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_EMAIL') }}
            </label>
            <input
              v-model="filters.email"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="t('JABVOX_BULK_WA.LEADS.FILTER_EMAIL')"
              @keyup.enter="applyFilters"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_PHONE') }}
            </label>
            <input
              v-model="filters.phone"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="t('JABVOX_BULK_WA.LEADS.FILTER_PHONE')"
              @keyup.enter="applyFilters"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_COUNTRY') }}
            </label>
            <input
              v-model="filters.country"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="t('JABVOX_BULK_WA.LEADS.FILTER_COUNTRY')"
              @keyup.enter="applyFilters"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_CAMPAIGN') }}
            </label>
            <select
              v-model="filters.campaign_id"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            >
              <option value="">{{ t('JABVOX_BULK_WA.LEADS.ALL') }}</option>
              <option
                v-for="c in filterOptions.campaigns || []"
                :key="c.id"
                :value="c.id"
              >
                {{ c.name }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_ASSIGNEE') }}
            </label>
            <select
              v-model="filters.assignee_id"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            >
              <option value="">{{ t('JABVOX_BULK_WA.LEADS.ALL') }}</option>
              <option
                v-for="a in filterOptions.assignees || []"
                :key="a.id"
                :value="a.id"
              >
                {{ a.name }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_TEAM') }}
            </label>
            <select
              v-model="filters.team_id"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            >
              <option value="">{{ t('JABVOX_BULK_WA.LEADS.ALL') }}</option>
              <option
                v-for="team in filterOptions.teams || []"
                :key="team.id"
                :value="team.id"
              >
                {{ team.name }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_INBOX') }}
            </label>
            <select
              v-model="filters.inbox_id"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            >
              <option value="">{{ t('JABVOX_BULK_WA.LEADS.ALL') }}</option>
              <option
                v-for="i in filterOptions.inboxes || []"
                :key="i.id"
                :value="i.id"
              >
                {{ i.name }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_AFFILIATE') }}
            </label>
            <select
              v-model="filters.affiliate_id"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            >
              <option value="">{{ t('JABVOX_BULK_WA.LEADS.ALL') }}</option>
              <option value="own">
                {{ t('JABVOX_BULK_WA.LEADS.AFFILIATE_OWN') }}
              </option>
              <option
                v-for="aff in filterOptions.affiliates || []"
                :key="aff.id"
                :value="aff.id"
              >
                {{ aff.name }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_STATE') }}
            </label>
            <select
              v-model="filters.management_state"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            >
              <option value="">{{ t('JABVOX_BULK_WA.LEADS.ALL') }}</option>
              <option
                v-for="ms in filterOptions.management_states || []"
                :key="ms.id"
                :value="ms.id"
              >
                {{ ms.name }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_SOLD') }}
            </label>
            <select
              v-model="filters.sold"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            >
              <option value="">{{ t('JABVOX_BULK_WA.LEADS.ALL') }}</option>
              <option v-for="opt in SOLD_OPTIONS" :key="opt" :value="opt">
                {{ t(`JABVOX_BULK_WA.LEADS.SOLD_${opt.toUpperCase()}`) }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_STATUS') }}
            </label>
            <select
              v-model="filters.status"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            >
              <option value="">{{ t('JABVOX_BULK_WA.LEADS.ALL') }}</option>
              <option v-for="st in STATUS_OPTIONS" :key="st" :value="st">
                {{ t(`JABVOX_BULK_WA.LEADS.STATUS_${st.toUpperCase()}`) }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_DATE_FROM') }}
            </label>
            <input
              v-model="filters.date_from"
              type="date"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_DATE_TO') }}
            </label>
            <input
              v-model="filters.date_to"
              type="date"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              @change="applyFilters"
            />
          </div>
          <div class="flex items-end gap-2 lg:col-span-2">
            <button
              type="button"
              class="inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90"
              @click="applyFilters"
            >
              <span class="i-lucide-search size-4" aria-hidden="true" />
              {{ t('JABVOX_BULK_WA.LEADS.APPLY') }}
            </button>
            <button
              v-if="activeFilterCount"
              type="button"
              class="inline-flex items-center justify-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3"
              @click="clearFilters"
            >
              <span class="i-lucide-x size-4" aria-hidden="true" />
              {{ t('JABVOX_BULK_WA.LEADS.CLEAR_FILTERS') }}
            </button>
          </div>
        </div>

        <!-- Custom-field filters (dynamic, from the account's lead custom columns) -->
        <div
          v-if="customFields.length"
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 pt-1 border-t border-n-weak"
        >
          <div
            v-for="cf in customFields"
            :key="cf.key"
            class="flex flex-col gap-1"
          >
            <label class="text-[11px] text-n-slate-10">{{ cf.label }}</label>

            <!-- Campos con opciones (select / multiselect): elegir uno o varios -->
            <details
              v-if="fieldHasOptions(cf)"
              class="group rounded-lg border border-n-weak bg-n-alpha-1"
            >
              <summary
                class="flex items-center justify-between gap-2 px-3 py-2 text-sm cursor-pointer select-none list-none"
              >
                <span class="truncate text-n-slate-12">
                  {{
                    (customValues[cf.key] || []).length
                      ? t('JABVOX_BULK_WA.LEADS.SELECTED_COUNT', {
                          count: (customValues[cf.key] || []).length,
                        })
                      : t('JABVOX_BULK_WA.LEADS.ALL')
                  }}
                </span>
                <span
                  class="i-lucide-chevron-down size-4 text-n-slate-10 group-open:rotate-180 transition-transform"
                />
              </summary>
              <div class="border-t border-n-weak">
                <!-- Buscador interno para campos con muchas opciones -->
                <div v-if="(cf.options || []).length > 8" class="p-2">
                  <input
                    v-model="optionSearch[cf.key]"
                    type="search"
                    :placeholder="t('JABVOX_BULK_WA.LEADS.SEARCH_OPTION')"
                    class="reset-base w-full text-sm rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5"
                    @click.stop
                  />
                </div>
                <div
                  class="max-h-40 overflow-y-auto px-3 pb-2 flex flex-col gap-1.5"
                >
                  <label
                    v-for="opt in filteredOptions(cf)"
                    :key="opt"
                    class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer"
                  >
                    <input
                      type="checkbox"
                      class="rounded accent-n-brand shrink-0"
                      :checked="(customValues[cf.key] || []).includes(opt)"
                      @change="toggleCustomOption(cf.key, opt)"
                    />
                    <span class="truncate">{{ opt }}</span>
                  </label>
                  <p
                    v-if="!filteredOptions(cf).length"
                    class="text-xs text-n-slate-10 py-1"
                  >
                    {{ t('JABVOX_BULK_WA.LEADS.NO_OPTIONS') }}
                  </p>
                </div>
              </div>
            </details>

            <!-- Texto / número: input libre -->
            <input
              v-else
              v-model="customValues[cf.key]"
              :type="cf.column_type === 'number' ? 'number' : 'text'"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="cf.label"
              @keyup.enter="applyFilters"
            />
          </div>
        </div>
      </div>
    </section>

    <!-- Selection summary -->
    <div
      class="flex flex-wrap items-center justify-between gap-2 text-sm text-n-slate-11"
    >
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium rounded-lg border border-n-weak hover:bg-n-alpha-2"
          @click="toggleSelectAll"
        >
          <span
            :class="selectAll ? 'i-lucide-check-square' : 'i-lucide-square'"
            class="size-3.5"
            aria-hidden="true"
          />
          {{ t('JABVOX_BULK_WA.LEADS.SELECT_ALL_FILTER', { total }) }}
        </button>
        <span v-if="selectedCount" class="text-n-slate-12 font-medium">
          {{ t('JABVOX_BULK_WA.LEADS.SELECTED', { count: selectedCount }) }}
        </span>
      </div>
      <button
        v-if="selectedCount"
        type="button"
        class="text-xs text-n-slate-10 hover:text-n-slate-12"
        @click="clearSelection"
      >
        {{ t('JABVOX_BULK_WA.LEADS.CLEAR') }}
      </button>
    </div>

    <!-- Lead table -->
    <div class="overflow-x-auto rounded-2xl border border-n-weak bg-n-solid-1">
      <table class="w-full text-sm">
        <thead class="bg-n-alpha-1 text-n-slate-11">
          <tr>
            <th class="w-10 px-3 py-2.5" />
            <th class="text-left px-4 py-2.5 font-medium">
              {{ t('JABVOX_BULK_WA.COLS.NAME') }}
            </th>
            <th class="text-left px-4 py-2.5 font-medium">
              {{ t('JABVOX_BULK_WA.COLS.NUMBER') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading">
            <td colspan="3" class="px-4 py-6 text-center text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.LOADING') }}
            </td>
          </tr>
          <tr v-else-if="!leads.length">
            <td colspan="3" class="px-4 py-6 text-center text-n-slate-10">
              {{ t('JABVOX_BULK_WA.LEADS.EMPTY') }}
            </td>
          </tr>
          <template v-else>
            <tr
              v-for="lead in leads"
              :key="lead.id"
              class="border-t border-n-weak text-n-slate-12"
            >
              <td class="px-3 py-2.5">
                <input
                  type="checkbox"
                  :checked="isRowChecked(lead.id)"
                  @change="toggleRow(lead.id)"
                />
              </td>
              <td class="px-4 py-2.5">{{ contactName(lead) }}</td>
              <td class="px-4 py-2.5">{{ contactPhone(lead) }}</td>
            </tr>
          </template>
        </tbody>
      </table>
    </div>

    <!-- Pagination -->
    <div
      v-if="totalPages > 1"
      class="flex items-center justify-center gap-2 text-sm"
    >
      <button
        type="button"
        class="px-2.5 py-1.5 rounded-lg border border-n-weak text-n-slate-11 disabled:opacity-40"
        :disabled="page <= 1"
        @click="goToPage(page - 1)"
      >
        <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
      </button>
      <span class="text-n-slate-11">
        {{ t('JABVOX_BULK_WA.LEADS.PAGE', { page, pages: totalPages }) }}
      </span>
      <button
        type="button"
        class="px-2.5 py-1.5 rounded-lg border border-n-weak text-n-slate-11 disabled:opacity-40"
        :disabled="page >= totalPages"
        @click="goToPage(page + 1)"
      >
        <span class="i-lucide-chevron-right size-4" aria-hidden="true" />
      </button>
    </div>

    <!-- Message body -->
    <section
      class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm space-y-3"
    >
      <p v-if="!mode" class="text-sm text-n-slate-10">
        {{ t('JABVOX_BULK_WA.LEADS.SELECT_INBOX_FIRST') }}
      </p>

      <!-- Template mode -->
      <template v-else-if="mode === 'template'">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_BULK_WA.LEADS.TEMPLATE')
            }}</label>
            <select
              v-model="templateName"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
            >
              <option value="">
                {{ t('JABVOX_BULK_WA.LEADS.TEMPLATE_PLACEHOLDER') }}
              </option>
              <option
                v-for="tp in inboxTemplates"
                :key="tp.id || tp.name"
                :value="tp.name"
              >
                {{ tp.name }}
              </option>
            </select>
            <span
              v-if="!inboxTemplates.length"
              class="text-[11px] text-n-slate-9"
            >
              {{ t('JABVOX_BULK_WA.LEADS.NO_TEMPLATES') }}
            </span>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_BULK_WA.COLS.LANGUAGE')
            }}</label>
            <input
              :value="language"
              readonly
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-2 px-3 py-2 text-n-slate-11 cursor-default"
              :placeholder="t('JABVOX_BULK_WA.LEADS.LANGUAGE_AUTO')"
            />
            <span class="text-[11px] text-n-slate-9">
              {{ t('JABVOX_BULK_WA.LEADS.LANGUAGE_HINT') }}
            </span>
          </div>
        </div>
      </template>

      <!-- Text mode -->
      <template v-else>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">{{
            t('JABVOX_BULK_WA.LEADS.MESSAGE')
          }}</label>
          <textarea
            v-model="text"
            rows="4"
            class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 resize-y"
            :placeholder="t('JABVOX_BULK_WA.LEADS.MESSAGE_PLACEHOLDER')"
          />
        </div>
      </template>
    </section>

    <div class="flex justify-end">
      <button
        type="button"
        class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50"
        :disabled="!canSend || sending"
        @click="onSend"
      >
        <span
          v-if="sending"
          class="i-lucide-loader-2 size-4 animate-spin"
          aria-hidden="true"
        />
        <span v-else class="i-lucide-send size-4" aria-hidden="true" />
        {{ t('JABVOX_BULK_WA.LEADS.SEND', { count: selectedCount }) }}
      </button>
    </div>
  </div>
</template>
