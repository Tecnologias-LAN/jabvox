<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dialerCampaignsAPI } from 'dashboard/api/jabvox/dialer';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

defineProps({
  isSaving: { type: Boolean, default: false },
  leadCampaignOptions: { type: Array, default: () => [] },
  countryOptions: { type: Array, default: () => [] },
  affiliateOptions: { type: Array, default: () => [] },
  inboxOptions: { type: Array, default: () => [] },
  managementStates: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);
const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const editingId = ref(null);

// Collapsible form sections keep the dialog short; open only what you need.
const openSections = ref({
  targeting: false,
  leadFilters: false,
  leads: true,
  schedule: false,
  dialing: false,
  assignment: false,
});
const toggleSection = key => {
  openSections.value[key] = !openSections.value[key];
};

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
  lead_filters_jabvox: { q: '', email: '', phone: '', custom: {} },
  excluded_lead_ids_jabvox: [],
  schedule_start_date_jabvox: '',
  schedule_end_date_jabvox: '',
  calling_hours_start_jabvox: '',
  calling_hours_end_jabvox: '',
  dial_mode_jabvox: 'last_state',
  dial_field_jabvox: 'phone', // required: which number to dial (one per campaign)
  dial_prefix_jabvox: '',
  retry_statuses_jabvox: [],
  max_retries_jabvox: 0,
});
const form = ref(emptyForm());

// Lead custom-field definitions, fetched from the dialer's own endpoint so
// they load regardless of the customization module's permissions.
const customColumns = ref([]);
onMounted(async () => {
  try {
    const { data } = await dialerCampaignsAPI.getLeadFields();
    customColumns.value = data.custom || [];
  } catch {
    customColumns.value = [];
  }
});

// ── Configurable preview-table columns (same pattern as the leads page) ──
// The campaign's leads table shows exactly 6 data columns; each slot can be
// swapped for any default field OR any lead custom field. The layout persists
// per account in localStorage; corrupt/unknown entries fall back to the
// default of that slot so the table never breaks.
const DEFAULT_PREVIEW_COLUMNS = [
  { id: 'name', labelKey: 'JABVOX_DIALER.FORM.LEAD_NAME' },
  { id: 'phone', labelKey: 'JABVOX_DIALER.FORM.LEAD_PHONE' },
  { id: 'email', labelKey: 'JABVOX_DIALER.FORM.LEAD_EMAIL' },
  { id: 'campaign', labelKey: 'JABVOX_DIALER.FORM.LEAD_CAMPAIGN_COL' },
  { id: 'document', labelKey: 'JABVOX_DIALER.FORM.LEAD_DOCUMENT' },
  {
    id: 'last_management_state',
    labelKey: 'JABVOX_DIALER.FORM.LEAD_LAST_STATE',
  },
];
const COLUMN_SLOTS = DEFAULT_PREVIEW_COLUMNS.length;
const defaultColumnConfig = () => DEFAULT_PREVIEW_COLUMNS.map(c => `d:${c.id}`);

const columnConfig = ref(defaultColumnConfig());
const showColumnConfig = ref(false);
const columnsStorageKey = computed(
  () => `jabvox_dialer_campaign_columns_v1_${store.getters.getCurrentAccountId}`
);

const loadColumnConfig = () => {
  try {
    const raw = localStorage.getItem(columnsStorageKey.value);
    if (!raw) return;
    const parsed = JSON.parse(raw);
    if (
      Array.isArray(parsed) &&
      parsed.length === COLUMN_SLOTS &&
      parsed.every(v => typeof v === 'string')
    ) {
      columnConfig.value = parsed;
    }
  } catch {
    // corrupt storage → keep defaults
  }
};
onMounted(loadColumnConfig);

const saveColumnConfig = () => {
  try {
    localStorage.setItem(
      columnsStorageKey.value,
      JSON.stringify(columnConfig.value)
    );
  } catch {
    // storage full/blocked → the in-memory config still applies this session
  }
};

const resetColumns = () => {
  columnConfig.value = defaultColumnConfig();
  saveColumnConfig();
};

// Every choice a slot can take: the 6 default fields + each custom field.
const columnOptions = computed(() => [
  ...DEFAULT_PREVIEW_COLUMNS.map(c => ({
    value: `d:${c.id}`,
    label: t(c.labelKey),
  })),
  ...customColumns.value.map(f => ({ value: `c:${f.key}`, label: f.label })),
]);

// Resolved descriptors used by the table. Unknown/broken entries degrade to
// the default column of that slot (never an empty or crashed cell).
const visibleColumns = computed(() =>
  columnConfig.value.map((entry, i) => {
    if (typeof entry === 'string' && entry.startsWith('c:')) {
      const key = entry.slice(2);
      const def = customColumns.value.find(f => f.key === key);
      return { kind: 'custom', uid: entry, key, label: def?.label || key };
    }
    const id = typeof entry === 'string' ? entry.replace(/^d:/, '') : '';
    const def =
      DEFAULT_PREVIEW_COLUMNS.find(c => c.id === id) ||
      DEFAULT_PREVIEW_COLUMNS[i] ||
      DEFAULT_PREVIEW_COLUMNS[0];
    return {
      kind: 'default',
      uid: `d:${def.id}`,
      id: def.id,
      label: t(def.labelKey),
    };
  })
);

// Display value for any cell: default fields read the lead's flat keys; custom
// fields read custom_fields (arrays joined, booleans localized, empty as dash).
const cellValue = (lead, colDef) => {
  const v =
    colDef.kind === 'custom'
      ? lead.custom_fields?.[colDef.key]
      : lead[colDef.id];
  if (v === null || v === undefined || `${v}`.trim() === '') return '—';
  if (Array.isArray(v)) return v.length ? v.join(', ') : '—';
  if (v === true) return t('JABVOX_DIALER.FORM.BOOL_YES');
  if (v === false) return t('JABVOX_DIALER.FORM.BOOL_NO');
  return `${v}`;
};

// Fields the campaign can dial: contact phone + each lead custom column.
const dialFieldOptions = computed(() => [
  { value: 'phone', label: t('JABVOX_DIALER.FORM.DIAL_FIELD_PHONE') },
  ...customColumns.value.map(c => ({ value: c.key, label: c.label })),
]);

// Every custom field is a checkbox selector (one or several values), except
// identity fields (nombre/correo/teléfono/documento) which stay as free text —
// name/email/phone already have their own inputs above.
const TEXT_ONLY_FIELDS = new Set([
  'nombre',
  'name',
  'correo',
  'email',
  'telefono',
  'phone',
  'documento',
  'document',
]);
const normalizeKey = value =>
  String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/(_c|_jabvox)$/, '');
const isTextOnlyField = col =>
  TEXT_ONLY_FIELDS.has(normalizeKey(col.key)) ||
  TEXT_ONLY_FIELDS.has(normalizeKey(col.label));

// Selected values for a field (always an array once the user picks options).
const selectedValues = key => {
  const v = form.value.lead_filters_jabvox.custom[key];
  return Array.isArray(v) ? v : [];
};

// Per-field search inside its options dropdown. For fields whose distinct
// values exceed the backend cap (truncated), the search also queries the
// server so any value is findable.
const optionSearch = ref({});
const remoteOptions = ref({});
const searchTimers = {};
const onOptionSearch = col => {
  if (!col.truncated) return;
  clearTimeout(searchTimers[col.key]);
  const q = (optionSearch.value[col.key] || '').trim();
  if (!q) {
    remoteOptions.value[col.key] = [];
    return;
  }
  searchTimers[col.key] = setTimeout(async () => {
    try {
      const { data } = await dialerCampaignsAPI.searchFieldValues(col.key, q);
      remoteOptions.value[col.key] = data.values || [];
    } catch {
      remoteOptions.value[col.key] = [];
    }
  }, 300);
};
const filteredOptions = col => {
  const q = (optionSearch.value[col.key] || '').trim().toLowerCase();
  const selected = selectedValues(col.key);
  const base = [
    ...new Set([
      ...(col.options || []),
      ...(remoteOptions.value[col.key] || []),
      ...selected,
    ]),
  ];
  if (!q) return base;
  return base.filter(o => String(o).toLowerCase().includes(q));
};

// Toggle an option in a field's selected-values array.
const toggleCustomOption = (key, option) => {
  const current = selectedValues(key);
  form.value.lead_filters_jabvox.custom[key] = current.includes(option)
    ? current.filter(o => o !== option)
    : [...current, option];
};

// Filters payload shared by the count and the leads preview.
const filterParams = () => ({
  jabvox_campaign_id: form.value.jabvox_campaign_id,
  countries: form.value.countries_jabvox,
  management_state_ids: form.value.management_state_ids_jabvox,
  affiliate_ids: form.value.affiliate_ids_jabvox,
  inbox_ids: form.value.inbox_ids_jabvox,
  q: form.value.lead_filters_jabvox.q || undefined,
  email: form.value.lead_filters_jabvox.email || undefined,
  phone: form.value.lead_filters_jabvox.phone || undefined,
  custom: form.value.lead_filters_jabvox.custom,
});

const title = computed(() =>
  editingId.value
    ? t('JABVOX_DIALER.CAMPAIGN.EDIT_TITLE')
    : t('JABVOX_DIALER.CAMPAIGN.NEW')
);
// Only the name is required; the lead campaign (and every other filter) is
// optional — no campaign means "all account leads matching the other filters".
// Name is required AND the dial field must be chosen (one per campaign).
const isValid = computed(
  () =>
    form.value.name_jabvox.trim().length > 0 && !!form.value.dial_field_jabvox
);

// ─── lead count live preview ───
const leadCount = ref(null);
const loadingLeadCount = ref(false);
let leadCountTimer = null;

// ─── leads preview (list + select/deselect) ───
const previewLeads = ref([]);
const previewTotal = ref(0);
const previewPage = ref(1);
const previewPerPage = ref(25);
const loadingPreview = ref(false);

const previewPages = computed(() =>
  Math.max(1, Math.ceil(previewTotal.value / previewPerPage.value))
);

const fetchLeadCount = async () => {
  loadingLeadCount.value = true;
  try {
    const { data } = await dialerCampaignsAPI.leadCount({
      ...filterParams(),
      excluded_lead_ids: form.value.excluded_lead_ids_jabvox,
    });
    leadCount.value = data.count;
  } catch {
    leadCount.value = null;
  } finally {
    loadingLeadCount.value = false;
  }
};

const fetchPreviewLeads = async () => {
  loadingPreview.value = true;
  try {
    const { data } = await dialerCampaignsAPI.previewLeads({
      ...filterParams(),
      page: previewPage.value,
    });
    previewLeads.value = data.leads || [];
    previewTotal.value = data.total || 0;
    previewPerPage.value = data.per_page || 25;
  } catch {
    previewLeads.value = [];
    previewTotal.value = 0;
  } finally {
    loadingPreview.value = false;
  }
};

const debouncedFetchLeadCount = () => {
  clearTimeout(leadCountTimer);
  leadCountTimer = setTimeout(() => {
    previewPage.value = 1;
    fetchLeadCount();
    fetchPreviewLeads();
  }, 400);
};

watch(
  () => [
    form.value.jabvox_campaign_id,
    form.value.countries_jabvox.length,
    form.value.management_state_ids_jabvox.length,
    form.value.affiliate_ids_jabvox.length,
    form.value.inbox_ids_jabvox.length,
    form.value.lead_filters_jabvox.q,
    form.value.lead_filters_jabvox.email,
    form.value.lead_filters_jabvox.phone,
    JSON.stringify(form.value.lead_filters_jabvox.custom),
  ],
  debouncedFetchLeadCount
);

// Refresh only the count when exclusions change — the list stays put so the
// admin can keep unchecking rows.
watch(() => form.value.excluded_lead_ids_jabvox.length, fetchLeadCount);

const goToPreviewPage = p => {
  if (p < 1 || p > previewPages.value) return;
  previewPage.value = p;
  fetchPreviewLeads();
};

const leadIncluded = id => !form.value.excluded_lead_ids_jabvox.includes(id);

const toggleLead = id => {
  const list = form.value.excluded_lead_ids_jabvox;
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

// Header checkbox: include/exclude every lead on the current page.
const pageAllIncluded = computed(
  () =>
    previewLeads.value.length > 0 &&
    previewLeads.value.every(l => leadIncluded(l.id))
);
const togglePage = () => {
  const excluded = new Set(form.value.excluded_lead_ids_jabvox);
  if (pageAllIncluded.value) {
    previewLeads.value.forEach(l => excluded.add(l.id));
  } else {
    previewLeads.value.forEach(l => excluded.delete(l.id));
  }
  form.value.excluded_lead_ids_jabvox = [...excluded];
};

// Select all = no exclusions (every matching lead is included).
const selectAllLeads = () => {
  form.value.excluded_lead_ids_jabvox = [];
};

// Deselect all = exclude every lead matching the current filters. The ids come
// from the backend so we never ship thousands from the client.
const selectingAll = ref(false);
const deselectAllLeads = async () => {
  selectingAll.value = true;
  try {
    const { data } = await dialerCampaignsAPI.matchingLeadIds(filterParams());
    form.value.excluded_lead_ids_jabvox = data.ids || [];
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  } finally {
    selectingAll.value = false;
  }
};

const toggleManagementState = id => {
  const list = form.value.management_state_ids_jabvox;
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

const toggleAgent = id => {
  const list = form.value.agent_ids_jabvox;
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
};

// Retry rules (one-by-one mode only): which outcomes get re-queued.
const RETRY_STATUS_OPTIONS = ['no_answer', 'busy', 'failed'];
const retryStatusChecked = status =>
  form.value.retry_statuses_jabvox.includes(status);
const toggleRetryStatus = status => {
  const list = form.value.retry_statuses_jabvox;
  const idx = list.indexOf(status);
  if (idx === -1) list.push(status);
  else list.splice(idx, 1);
};

const openCreate = () => {
  editingId.value = null;
  form.value = emptyForm();
  leadCount.value = null;
  nextTick(() => dialogRef.value?.open());
  // Show the total + leads list immediately (no filters = all account leads).
  debouncedFetchLeadCount();
};

// Normalize saved custom filters into arrays so the checkboxes reflect the saved
// selection. Handles the current array shape, a single string, and the old
// corrupted "[\"121\"]" form (JSON-parses it back to an array when possible).
const normalizeSavedCustom = custom => {
  const out = {};
  Object.entries(custom || {}).forEach(([key, value]) => {
    // Text-only fields (documento, etc.) bind to a plain input: keep a string.
    if (TEXT_ONLY_FIELDS.has(normalizeKey(key))) {
      out[key] = Array.isArray(value) ? String(value[0] ?? '') : String(value);
      if (out[key] === '') delete out[key];
    } else if (Array.isArray(value)) {
      out[key] = value.map(String).filter(v => v !== '');
    } else if (typeof value === 'string' && value !== '') {
      const trimmed = value.trim();
      if (trimmed.startsWith('[')) {
        try {
          const parsed = JSON.parse(trimmed);
          out[key] = Array.isArray(parsed)
            ? parsed.map(String).filter(v => v !== '')
            : [value];
        } catch {
          out[key] = [value];
        }
      } else {
        out[key] = [value];
      }
    }
  });
  return out;
};

const openEdit = c => {
  editingId.value = c.id;
  leadCount.value = null;
  const lf = c.lead_filters_jabvox || {};
  form.value = {
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
    lead_filters_jabvox: {
      q: lf.q || '',
      email: lf.email || '',
      phone: lf.phone || '',
      custom: normalizeSavedCustom(lf.custom),
    },
    excluded_lead_ids_jabvox: [...(c.excluded_lead_ids_jabvox || [])],
    schedule_start_date_jabvox: c.schedule_start_date_jabvox || '',
    schedule_end_date_jabvox: c.schedule_end_date_jabvox || '',
    calling_hours_start_jabvox: c.calling_hours_start_jabvox || '',
    calling_hours_end_jabvox: c.calling_hours_end_jabvox || '',
    dial_mode_jabvox: c.dial_mode_jabvox || 'last_state',
    dial_field_jabvox: c.dial_field_jabvox || 'phone',
    dial_prefix_jabvox: c.dial_prefix_jabvox || '',
    retry_statuses_jabvox: [...(c.retry_statuses_jabvox || [])],
    max_retries_jabvox: c.max_retries_jabvox ?? 0,
  };
  nextTick(() => dialogRef.value?.open());
  debouncedFetchLeadCount();
};

const close = () => dialogRef.value?.close();

const handleConfirm = async () => {
  if (!isValid.value) return;
  try {
    const payload = {
      ...form.value,
      jabvox_campaign_id: form.value.jabvox_campaign_id || null,
      leads_count_jabvox: leadCount.value ?? 0,
    };
    if (editingId.value) {
      await store.dispatch('jabvoxDialer/updateCampaign', {
        id: editingId.value,
        ...payload,
      });
    } else {
      await store.dispatch('jabvoxDialer/createCampaign', payload);
    }
    close();
    useAlert(t('JABVOX_DIALER.CAMPAIGN.SAVE_SUCCESS'));
    emit('saved');
  } catch {
    useAlert(t('JABVOX_DIALER.ERROR'));
  }
};

const stateChecked = id => form.value.management_state_ids_jabvox.includes(id);
const agentChecked = id => form.value.agent_ids_jabvox.includes(id);

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('JABVOX_DIALER.CAMPAIGN.FORM_SUBTITLE')"
    :confirm-button-label="t('JABVOX_DIALER.COMMON.SAVE')"
    :cancel-button-label="t('JABVOX_DIALER.COMMON.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="5xl"
    overflow-y-auto
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-6">
      <!-- Group: source -->
      <section class="flex flex-col gap-4">
        <h3
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_SOURCE') }}
        </h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            v-model="form.name_jabvox"
            :label="t('JABVOX_DIALER.FORM.NAME')"
            :placeholder="t('JABVOX_DIALER.FORM.NAME_PLACEHOLDER')"
            autofocus
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN') }}
            </label>
            <ComboBox
              v-model="form.jabvox_campaign_id"
              :options="leadCampaignOptions"
              :placeholder="t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN_PLACEHOLDER')"
              :search-placeholder="
                t('JABVOX_DIALER.FORM.LEAD_CAMPAIGN_PLACEHOLDER')
              "
            />
          </div>
        </div>
      </section>

      <!-- Group: targeting -->
      <section class="rounded-xl border border-n-weak">
        <button
          type="button"
          class="flex w-full items-center justify-between px-4 py-3"
          @click="toggleSection('targeting')"
        >
          <span
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_TARGETING') }}
          </span>
          <span
            :class="
              openSections.targeting
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            class="size-4 text-n-slate-10"
          />
        </button>
        <div
          v-show="openSections.targeting"
          class="flex flex-col gap-4 px-4 pb-4"
        >
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.COUNTRIES') }}
            </label>
            <TagMultiSelectComboBox
              v-model="form.countries_jabvox"
              :options="countryOptions"
              :placeholder="t('JABVOX_DIALER.FORM.COUNTRIES_PLACEHOLDER')"
              :search-placeholder="t('JABVOX_DIALER.FORM.COUNTRIES_SEARCH')"
            />
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_DIALER.FORM.COUNTRIES_HINT') }}
            </p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_DIALER.FORM.AFFILIATES') }}
              </label>
              <TagMultiSelectComboBox
                v-model="form.affiliate_ids_jabvox"
                :options="affiliateOptions"
                :placeholder="t('JABVOX_DIALER.FORM.AFFILIATES')"
                :search-placeholder="t('JABVOX_DIALER.FORM.AFFILIATES')"
              />
            </div>
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_DIALER.FORM.INBOXES') }}
              </label>
              <TagMultiSelectComboBox
                v-model="form.inbox_ids_jabvox"
                :options="inboxOptions"
                :placeholder="t('JABVOX_DIALER.FORM.INBOXES')"
                :search-placeholder="t('JABVOX_DIALER.FORM.INBOXES')"
              />
            </div>
          </div>
          <!-- Management states -->
          <div class="flex flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.MANAGEMENT_STATES') }}
            </label>
            <p class="text-xs text-n-slate-10 -mt-1">
              {{ t('JABVOX_DIALER.FORM.MANAGEMENT_STATES_HINT') }}
            </p>
            <div
              class="flex flex-col gap-1 max-h-44 overflow-y-auto rounded-xl border border-n-weak p-2"
            >
              <label
                class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
              >
                <input
                  type="checkbox"
                  :checked="stateChecked('none')"
                  class="rounded accent-n-brand"
                  @change="toggleManagementState('none')"
                />
                {{ t('JABVOX_DIALER.FORM.NO_MANAGEMENT_STATE') }}
              </label>
              <label
                v-for="ms in managementStates"
                :key="ms.id"
                class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
              >
                <input
                  type="checkbox"
                  :checked="stateChecked(ms.id)"
                  class="rounded accent-n-brand"
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
        </div>
      </section>

      <!-- Group: lead field filters -->
      <section class="rounded-xl border border-n-weak">
        <button
          type="button"
          class="flex w-full items-center justify-between px-4 py-3"
          @click="toggleSection('leadFilters')"
        >
          <span
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_LEAD_FILTERS') }}
          </span>
          <span
            :class="
              openSections.leadFilters
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            class="size-4 text-n-slate-10"
          />
        </button>
        <div
          v-show="openSections.leadFilters"
          class="flex flex-col gap-4 px-4 pb-4"
        >
          <!-- Column layout configurator: which 6 fields the leads table shows -->
          <div class="flex flex-col gap-3">
            <button
              type="button"
              class="h-9 flex w-fit items-center gap-1.5 rounded-lg border px-3 text-sm font-medium transition-colors"
              :class="
                showColumnConfig
                  ? 'border-n-brand/40 bg-n-alpha-2 text-n-brand'
                  : 'border-n-weak bg-n-solid-1 text-n-slate-11 hover:bg-n-alpha-1'
              "
              @click="showColumnConfig = !showColumnConfig"
            >
              <span class="i-lucide-columns-3 size-3.5" />
              {{ t('JABVOX_DIALER.FORM.COLUMNS_BUTTON') }}
            </button>
            <div
              v-if="showColumnConfig"
              class="rounded-xl border border-n-weak bg-n-solid-1 p-4 space-y-3 shadow-sm"
            >
              <div class="flex items-center justify-between gap-3">
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_DIALER.FORM.COLUMNS_HINT') }}
                </p>
                <button
                  type="button"
                  class="h-8 shrink-0 flex items-center gap-1.5 rounded-lg border border-n-weak bg-n-solid-1 text-xs text-n-slate-10 px-2.5 hover:bg-n-alpha-1 transition-colors"
                  @click="resetColumns"
                >
                  <span class="i-lucide-rotate-ccw size-3" />
                  {{ t('JABVOX_DIALER.FORM.COLUMNS_RESET') }}
                </button>
              </div>
              <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                <div
                  v-for="(entry, i) in columnConfig"
                  :key="`slot-${i}`"
                  class="flex flex-col gap-1"
                >
                  <label
                    class="text-[11px] font-medium text-n-slate-10 select-none"
                  >
                    {{ t('JABVOX_DIALER.FORM.COLUMNS_SLOT', { n: i + 1 }) }}
                  </label>
                  <select
                    v-model="columnConfig[i]"
                    class="reset-base h-9 w-full rounded-lg border border-n-weak bg-n-background text-sm text-n-slate-12 px-2 focus:outline-none focus:border-n-slate-7 transition-colors"
                    @change="saveColumnConfig"
                  >
                    <option
                      v-for="opt in columnOptions"
                      :key="opt.value"
                      :value="opt.value"
                    >
                      {{ opt.label }}
                    </option>
                  </select>
                </div>
              </div>
            </div>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <Input
              v-model="form.lead_filters_jabvox.q"
              :label="t('JABVOX_DIALER.FORM.FILTER_NAME')"
              :placeholder="t('JABVOX_DIALER.FORM.FILTER_NAME')"
            />
            <Input
              v-model="form.lead_filters_jabvox.email"
              :label="t('JABVOX_DIALER.FORM.FILTER_EMAIL')"
              :placeholder="t('JABVOX_DIALER.FORM.FILTER_EMAIL')"
            />
            <Input
              v-model="form.lead_filters_jabvox.phone"
              :label="t('JABVOX_DIALER.FORM.FILTER_PHONE')"
              :placeholder="t('JABVOX_DIALER.FORM.FILTER_PHONE')"
            />
          </div>
          <div
            v-if="customColumns.length"
            class="grid grid-cols-1 sm:grid-cols-3 gap-4"
          >
            <div
              v-for="col in customColumns"
              :key="col.key"
              class="flex flex-col gap-1.5"
            >
              <label class="text-sm font-medium text-n-slate-12">
                {{ col.label }}
              </label>

              <!-- Todos los campos: elegir una o varias opciones (checkboxes) -->
              <details
                v-if="!isTextOnlyField(col)"
                class="group rounded-lg border border-n-weak bg-n-alpha-1"
              >
                <summary
                  class="flex items-center justify-between gap-2 px-3 py-2 text-sm cursor-pointer select-none list-none"
                >
                  <span class="truncate text-n-slate-12">
                    {{
                      selectedValues(col.key).length
                        ? t('JABVOX_DIALER.FORM.FILTER_SELECTED_COUNT', {
                            count: selectedValues(col.key).length,
                          })
                        : t('JABVOX_DIALER.FORM.FILTER_ALL')
                    }}
                  </span>
                  <span
                    class="i-lucide-chevron-down size-4 text-n-slate-10 group-open:rotate-180 transition-transform"
                  />
                </summary>
                <div class="border-t border-n-weak">
                  <div
                    v-if="(col.options || []).length > 8 || col.truncated"
                    class="p-2"
                  >
                    <input
                      v-model="optionSearch[col.key]"
                      type="search"
                      :placeholder="
                        t('JABVOX_DIALER.FORM.FILTER_SEARCH_OPTION')
                      "
                      class="reset-base w-full text-sm rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5"
                      @click.stop
                      @input="onOptionSearch(col)"
                    />
                  </div>
                  <div
                    class="max-h-40 overflow-y-auto px-3 pb-2 flex flex-col gap-1.5"
                  >
                    <label
                      v-for="opt in filteredOptions(col)"
                      :key="opt"
                      class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer"
                    >
                      <input
                        type="checkbox"
                        class="rounded accent-n-brand shrink-0"
                        :checked="selectedValues(col.key).includes(opt)"
                        @change="toggleCustomOption(col.key, opt)"
                      />
                      <span class="truncate">{{ opt }}</span>
                    </label>
                    <p
                      v-if="!filteredOptions(col).length"
                      class="text-xs text-n-slate-10 py-1"
                    >
                      {{ t('JABVOX_DIALER.FORM.FILTER_NO_OPTIONS') }}
                    </p>
                  </div>
                </div>
              </details>

              <!-- Sin opciones: texto libre -->
              <input
                v-else
                v-model="form.lead_filters_jabvox.custom[col.key]"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
                :placeholder="col.label"
              />
            </div>
          </div>
        </div>
      </section>

      <!-- Group: leads preview + select/deselect (shown for any filter set,
           even with no lead campaign selected) -->
      <section class="rounded-xl border border-n-weak">
        <div class="flex items-center justify-between px-4 py-3 gap-3">
          <button
            type="button"
            class="flex flex-1 items-center justify-between"
            @click="toggleSection('leads')"
          >
            <span
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            >
              {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_LEADS') }}
            </span>
            <span
              :class="
                openSections.leads
                  ? 'i-lucide-chevron-up'
                  : 'i-lucide-chevron-down'
              "
              class="size-4 text-n-slate-10"
            />
          </button>
          <div class="flex items-center gap-3 shrink-0">
            <button
              type="button"
              class="text-xs text-n-brand hover:underline disabled:opacity-40"
              :disabled="selectingAll"
              @click="selectAllLeads"
            >
              {{ t('JABVOX_DIALER.FORM.SELECT_ALL') }}
            </button>
            <button
              type="button"
              class="text-xs text-n-slate-11 hover:underline disabled:opacity-40"
              :disabled="selectingAll"
              @click="deselectAllLeads"
            >
              {{ t('JABVOX_DIALER.FORM.DESELECT_ALL') }}
            </button>
          </div>
        </div>
        <div v-show="openSections.leads" class="flex flex-col gap-2 px-4 pb-4">
          <div class="rounded-xl border border-n-weak overflow-hidden">
            <div class="max-h-96 overflow-y-auto">
              <table class="w-full text-sm">
                <thead
                  class="bg-n-alpha-1 text-n-slate-11 sticky top-0 backdrop-blur"
                >
                  <tr>
                    <th class="w-9 px-2 py-2">
                      <input
                        type="checkbox"
                        class="rounded accent-n-brand"
                        :checked="pageAllIncluded"
                        @change="togglePage"
                      />
                    </th>
                    <th
                      v-for="colDef in visibleColumns"
                      :key="colDef.uid"
                      class="text-left px-2 py-2 font-medium"
                    >
                      {{ colDef.label }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-if="loadingPreview">
                    <td
                      :colspan="visibleColumns.length + 1"
                      class="px-3 py-5 text-center text-n-slate-10"
                    >
                      <Spinner :size="14" class="inline-block" />
                    </td>
                  </tr>
                  <tr v-else-if="!previewLeads.length">
                    <td
                      :colspan="visibleColumns.length + 1"
                      class="px-3 py-5 text-center text-n-slate-10"
                    >
                      {{ t('JABVOX_DIALER.FORM.LEADS_EMPTY') }}
                    </td>
                  </tr>
                  <template v-else>
                    <tr
                      v-for="lead in previewLeads"
                      :key="lead.id"
                      class="border-t border-n-weak"
                      :class="
                        leadIncluded(lead.id)
                          ? 'text-n-slate-12'
                          : 'text-n-slate-9 opacity-60'
                      "
                    >
                      <td class="px-2 py-1.5">
                        <input
                          type="checkbox"
                          class="rounded accent-n-brand"
                          :checked="leadIncluded(lead.id)"
                          @change="toggleLead(lead.id)"
                        />
                      </td>
                      <td
                        v-for="colDef in visibleColumns"
                        :key="colDef.uid"
                        class="px-2 py-1.5 truncate max-w-40"
                        :title="cellValue(lead, colDef)"
                      >
                        {{ cellValue(lead, colDef) }}
                      </td>
                    </tr>
                  </template>
                </tbody>
              </table>
            </div>
            <div
              v-if="previewPages > 1"
              class="flex items-center justify-center gap-2 border-t border-n-weak px-3 py-2 text-xs text-n-slate-11"
            >
              <button
                type="button"
                class="px-2 py-1 rounded border border-n-weak disabled:opacity-40"
                :disabled="previewPage <= 1"
                @click="goToPreviewPage(previewPage - 1)"
              >
                <span class="i-lucide-chevron-left size-3.5" />
              </button>
              {{
                t('JABVOX_DIALER.FORM.LEADS_PAGE', {
                  page: previewPage,
                  pages: previewPages,
                })
              }}
              <button
                type="button"
                class="px-2 py-1 rounded border border-n-weak disabled:opacity-40"
                :disabled="previewPage >= previewPages"
                @click="goToPreviewPage(previewPage + 1)"
              >
                <span class="i-lucide-chevron-right size-3.5" />
              </button>
            </div>
          </div>
        </div>
      </section>

      <!-- Group: schedule -->
      <section class="rounded-xl border border-n-weak">
        <button
          type="button"
          class="flex w-full items-center justify-between px-4 py-3"
          @click="toggleSection('schedule')"
        >
          <span
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_SCHEDULE') }}
          </span>
          <span
            :class="
              openSections.schedule
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            class="size-4 text-n-slate-10"
          />
        </button>
        <div
          v-show="openSections.schedule"
          class="flex flex-col gap-4 px-4 pb-4"
        >
          <p class="text-xs text-n-slate-10 -mt-2">
            {{ t('JABVOX_DIALER.FORM.SCHEDULE_HINT') }}
          </p>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_DIALER.FORM.SCHEDULE_DATE_FROM') }}
              </label>
              <input
                v-model="form.schedule_start_date_jabvox"
                type="date"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              />
            </div>
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_DIALER.FORM.SCHEDULE_DATE_TO') }}
              </label>
              <input
                v-model="form.schedule_end_date_jabvox"
                type="date"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              />
            </div>
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_DIALER.FORM.SCHEDULE_HOUR_FROM') }}
              </label>
              <input
                v-model="form.calling_hours_start_jabvox"
                type="time"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              />
            </div>
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_DIALER.FORM.SCHEDULE_HOUR_TO') }}
              </label>
              <input
                v-model="form.calling_hours_end_jabvox"
                type="time"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              />
            </div>
          </div>
        </div>
      </section>

      <!-- Group: dialing -->
      <section class="rounded-xl border border-n-weak">
        <button
          type="button"
          class="flex w-full items-center justify-between px-4 py-3"
          @click="toggleSection('dialing')"
        >
          <span
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_DIALING') }}
          </span>
          <span
            :class="
              openSections.dialing
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            class="size-4 text-n-slate-10"
          />
        </button>
        <div
          v-show="openSections.dialing"
          class="flex flex-col gap-4 px-4 pb-4"
        >
          <!-- Dial mode: last-state vs one-by-one (never repeats a lead) -->
          <div class="flex flex-col gap-2">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.DIAL_MODE') }}
            </label>
            <label
              v-for="mode in ['last_state', 'one_by_one']"
              :key="mode"
              class="flex items-start gap-2 cursor-pointer rounded-lg border p-2.5"
              :class="
                form.dial_mode_jabvox === mode
                  ? 'border-n-brand bg-n-alpha-1'
                  : 'border-n-weak'
              "
            >
              <input
                v-model="form.dial_mode_jabvox"
                type="radio"
                :value="mode"
                class="mt-0.5 accent-n-brand"
              />
              <span class="flex flex-col">
                <span class="text-sm text-n-slate-12">
                  {{ t(`JABVOX_DIALER.FORM.DIAL_MODE_${mode.toUpperCase()}`) }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{
                    t(`JABVOX_DIALER.FORM.DIAL_MODE_${mode.toUpperCase()}_HINT`)
                  }}
                </span>
              </span>
            </label>
          </div>

          <!-- Dial field: which number to dial (required, one per campaign) -->
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_DIALER.FORM.DIAL_FIELD') }}
                <span class="text-n-ruby-11">*</span>
              </label>
              <ComboBox
                v-model="form.dial_field_jabvox"
                :options="dialFieldOptions"
                :placeholder="t('JABVOX_DIALER.FORM.DIAL_FIELD_PHONE')"
                :search-placeholder="t('JABVOX_DIALER.FORM.DIAL_FIELD_SEARCH')"
                :empty-state="t('JABVOX_DIALER.FORM.DIAL_FIELD_NO_RESULTS')"
              />
              <span class="text-xs text-n-slate-10">
                {{ t('JABVOX_DIALER.FORM.DIAL_FIELD_HINT') }}
              </span>
            </div>
            <Input
              v-model="form.dial_prefix_jabvox"
              :label="t('JABVOX_DIALER.FORM.DIAL_PREFIX')"
              placeholder="57"
              :message="t('JABVOX_DIALER.FORM.DIAL_PREFIX_HINT')"
              custom-input-class="font-mono"
            />
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              v-model.number="form.wrapup_time_jabvox"
              type="number"
              min="0"
              :label="t('JABVOX_DIALER.FORM.WRAPUP_TIME')"
              :message="t('JABVOX_DIALER.FORM.WRAPUP_TIME_HINT')"
            />
            <Input
              v-model.number="form.lines_per_agent_jabvox"
              type="number"
              min="1"
              max="10"
              :label="t('JABVOX_DIALER.FORM.LINES_PER_AGENT')"
              :message="t('JABVOX_DIALER.FORM.LINES_PER_AGENT_HINT')"
            />
          </div>
          <div
            class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
          >
            <div class="flex flex-col">
              <span class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_DIALER.FORM.WAIT_IN_QUEUE') }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{ t('JABVOX_DIALER.FORM.WAIT_IN_QUEUE_HINT') }}
              </span>
            </div>
            <Switch v-model="form.wait_in_queue_jabvox" />
          </div>

          <!-- Retry rules: only meaningful in one-by-one mode -->
          <div
            v-if="form.dial_mode_jabvox === 'one_by_one'"
            class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_DIALER.FORM.RETRY_TITLE') }}
            </span>
            <div class="flex flex-col gap-2">
              <label
                v-for="status in RETRY_STATUS_OPTIONS"
                :key="status"
                class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none"
              >
                <input
                  type="checkbox"
                  class="rounded accent-n-brand"
                  :checked="retryStatusChecked(status)"
                  @change="toggleRetryStatus(status)"
                />
                {{
                  t(`JABVOX_DIALER.FORM.RETRY_STATUS_${status.toUpperCase()}`)
                }}
              </label>
            </div>
            <Input
              v-model.number="form.max_retries_jabvox"
              type="number"
              min="0"
              :label="t('JABVOX_DIALER.FORM.RETRY_MAX')"
            />
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_DIALER.FORM.RETRY_HINT') }}
            </p>
          </div>
        </div>
      </section>

      <!-- Group: assignment -->
      <section class="rounded-xl border border-n-weak">
        <button
          type="button"
          class="flex w-full items-center justify-between px-4 py-3"
          @click="toggleSection('assignment')"
        >
          <span
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t('JABVOX_DIALER.CAMPAIGN.GROUP_ASSIGNMENT') }}
          </span>
          <span
            :class="
              openSections.assignment
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            class="size-4 text-n-slate-10"
          />
        </button>
        <div
          v-show="openSections.assignment"
          class="flex flex-col gap-2 px-4 pb-4"
        >
          <p class="text-xs text-n-slate-10">
            {{ t('JABVOX_DIALER.FORM.AGENTS_HINT') }}
          </p>
          <div
            class="flex flex-col gap-1 max-h-44 overflow-y-auto rounded-xl border border-n-weak p-2"
          >
            <label
              v-for="agent in agents"
              :key="agent.id"
              class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                :checked="agentChecked(agent.id)"
                class="rounded accent-n-brand"
                @change="toggleAgent(agent.id)"
              />
              <span class="truncate">{{ agent.name }}</span>
              <span class="text-xs text-n-slate-10 truncate">{{
                agent.email
              }}</span>
            </label>
          </div>
        </div>
      </section>

      <!-- Lead count preview (total matching the current filters) -->
      <div
        class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <span class="flex items-center gap-2 text-sm text-n-slate-12">
          <span class="i-lucide-users size-4 text-n-brand" />
          {{ t('JABVOX_DIALER.FORM.LEAD_COUNT_LABEL') }}
        </span>
        <span
          v-if="loadingLeadCount"
          class="flex items-center gap-1.5 text-sm text-n-slate-10"
        >
          <Spinner :size="14" />
        </span>
        <span
          v-else-if="leadCount != null"
          class="text-sm font-semibold text-n-brand tabular-nums"
        >
          {{ leadCount.toLocaleString() }}
          {{ t('JABVOX_DIALER.FORM.LEAD_COUNT_UNIT') }}
        </span>
        <span v-else class="text-sm text-n-slate-10">—</span>
      </div>
    </div>
  </Dialog>
</template>
