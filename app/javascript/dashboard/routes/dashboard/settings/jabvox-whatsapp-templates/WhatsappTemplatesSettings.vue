<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import {
  wtInboxesAPI,
  wtTemplatesAPI,
  wtExportAPI,
  wtImportAPI,
  wtPermissionsAPI,
} from 'dashboard/api/jabvox/whatsappTemplates';

const { t } = useI18n();

// ─── Tabs ────────────────────────────────────────────────────────────────────
const activeTab = ref('templates');
const stickyHeaderRef = ref(null);

// ─── Inboxes ─────────────────────────────────────────────────────────────────
const inboxes = ref([]);
const selectedInboxId = ref(null);
const syncing = ref(false);

const loadInboxes = async () => {
  try {
    const { data } = await wtInboxesAPI.getAll();
    inboxes.value = data.inboxes || [];
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

// ─── Metrics ─────────────────────────────────────────────────────────────────
const metrics = ref({});

const loadMetrics = async () => {
  try {
    const { data } = await wtInboxesAPI.metrics(selectedInboxId.value);
    metrics.value = data;
  } catch {
    /* non-blocking */
  }
};

// ─── Filters ─────────────────────────────────────────────────────────────────
const filters = ref({
  q: '',
  meta_id: '',
  status: '',
  category: '',
  language: '',
  date_from: '',
  date_to: '',
});
const page = ref(1);
const perPage = 50;

const apiFilters = computed(() => {
  const f = { page: page.value, per_page: perPage };
  if (selectedInboxId.value) f.inbox_id = selectedInboxId.value;
  Object.entries(filters.value).forEach(([k, v]) => {
    if (v) f[k] = v;
  });
  return f;
});

// ─── Templates list ──────────────────────────────────────────────────────────
const templates = ref([]);
const totalTemplates = ref(0);
const loadingTemplates = ref(false);

const totalPages = computed(
  () => Math.ceil(totalTemplates.value / perPage) || 1
);

const loadTemplates = async () => {
  loadingTemplates.value = true;
  try {
    const { data } = await wtTemplatesAPI.getAll(apiFilters.value);
    templates.value = data.templates || [];
    totalTemplates.value = data.total || 0;
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    loadingTemplates.value = false;
  }
};

const syncInbox = async () => {
  if (!selectedInboxId.value) return;
  syncing.value = true;
  try {
    await wtInboxesAPI.sync(selectedInboxId.value);
    useAlert(t('JABVOX_WA_TEMPLATES.SYNCED'));
    await loadTemplates();
    await loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    syncing.value = false;
  }
};

const clearFilters = () => {
  filters.value = {
    q: '',
    meta_id: '',
    status: '',
    category: '',
    language: '',
    date_from: '',
    date_to: '',
  };
  page.value = 1;
  loadTemplates();
};

const summaryKpis = computed(() => {
  const m = metrics.value || {};
  const usage = m.usage_this_month || m.sent_this_month || m.sent || 0;
  return [
    {
      key: 'total',
      label: t('JABVOX_WA_TEMPLATES.METRICS.TOTAL'),
      value: m.total ?? 0,
      icon: 'i-lucide-layout-template',
      accent: 'text-n-brand',
    },
    {
      key: 'approved',
      label: t('JABVOX_WA_TEMPLATES.METRICS.APPROVED'),
      value: m.approved ?? 0,
      icon: 'i-lucide-badge-check',
      accent: 'text-n-teal-11',
    },
    {
      key: 'pending',
      label: t('JABVOX_WA_TEMPLATES.METRICS.PENDING'),
      value: m.pending ?? 0,
      icon: 'i-lucide-clock-3',
      accent: 'text-n-amber-11',
    },
    {
      key: 'rejected',
      label: t('JABVOX_WA_TEMPLATES.METRICS.REJECTED'),
      value: m.rejected ?? 0,
      icon: 'i-lucide-shield-x',
      accent: 'text-n-ruby-11',
    },
    {
      key: 'disabled',
      label: t('JABVOX_WA_TEMPLATES.METRICS.DISABLED'),
      value: m.disabled ?? 0,
      icon: 'i-lucide-pause-circle',
      accent: 'text-n-slate-11',
    },
    {
      key: 'usage_month',
      label: t('JABVOX_WA_TEMPLATES.METRICS.USAGE_MONTH'),
      value: usage,
      icon: 'i-lucide-chart-column',
      accent: 'text-n-brand',
    },
  ];
});

const statusQuickFilters = [
  'APPROVED',
  'PENDING',
  'REJECTED',
  'DISABLED',
  'PAUSED',
];

const categoryQuickFilters = [
  'MARKETING',
  'UTILITY',
  'AUTHENTICATION',
  'SERVICE',
];

const selectedTemplateIds = ref([]);
const allVisibleSelected = computed(
  () =>
    templates.value.length > 0 &&
    selectedTemplateIds.value.length === templates.value.length
);

const toggleSelectAll = checked => {
  selectedTemplateIds.value = checked ? templates.value.map(tpl => tpl.id) : [];
};

const toggleSelectOne = (id, checked) => {
  if (checked) {
    if (!selectedTemplateIds.value.includes(id)) {
      selectedTemplateIds.value = [...selectedTemplateIds.value, id];
    }
    return;
  }
  selectedTemplateIds.value = selectedTemplateIds.value.filter(v => v !== id);
};

const selectedTemplates = computed(() =>
  templates.value.filter(tpl => selectedTemplateIds.value.includes(tpl.id))
);

const selectedCount = computed(() => selectedTemplateIds.value.length);

const filterChipActive = (kind, value) => {
  if (kind === 'status') return filters.value.status === value;
  return filters.value.category === value;
};

const categoryLabel = c => t(`JABVOX_WA_TEMPLATES.CATEGORIES.${c}`);

const applyFilters = () => {
  page.value = 1;
  loadTemplates();
};
const changePage = delta => {
  const n = page.value + delta;
  if (n < 1 || n > totalPages.value) return;
  page.value = n;
  loadTemplates();
};

const applyQuickFilter = (kind, value) => {
  const key = kind === 'status' ? 'status' : 'category';
  filters.value[key] = filters.value[key] === value ? '' : value;
  applyFilters();
};

const bulkSync = async () => {
  if (!selectedTemplates.value.length) return;
  try {
    await Promise.all(
      selectedTemplates.value.map(tpl => wtTemplatesAPI.sync(tpl.id))
    );
    useAlert(t('JABVOX_WA_TEMPLATES.SYNCED'));
    selectedTemplateIds.value = [];
    await loadTemplates();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const bulkDuplicate = async () => {
  if (!selectedTemplates.value.length) return;
  try {
    await Promise.all(
      selectedTemplates.value.map(tpl =>
        wtTemplatesAPI.duplicate(tpl.id, `${tpl.name}_copy_${Date.now()}`)
      )
    );
    useAlert(t('JABVOX_WA_TEMPLATES.DUPLICATED'));
    selectedTemplateIds.value = [];
    await loadTemplates();
    await loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const bulkDelete = async () => {
  if (!selectedTemplates.value.length) return;
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('JABVOX_WA_TEMPLATES.BULK.DELETE_CONFIRM', {
        count: selectedTemplates.value.length,
      })
    )
  )
    return;

  try {
    await Promise.all(
      selectedTemplates.value.map(tpl => wtTemplatesAPI.destroy(tpl.id))
    );
    useAlert(t('JABVOX_WA_TEMPLATES.DELETED'));
    selectedTemplateIds.value = [];
    await loadTemplates();
    await loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const bulkExportSelected = () => {
  if (!selectedTemplates.value.length) return;
  const payload = selectedTemplates.value.map(tpl => ({
    id: tpl.id,
    name: tpl.name,
    category: tpl.category,
    language: tpl.language,
    status: tpl.status,
    meta_template_id: tpl.meta_template_id,
  }));
  const blob = new Blob([JSON.stringify(payload, null, 2)], {
    type: 'application/json',
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'wa_templates_selected.json';
  a.click();
  URL.revokeObjectURL(url);
};

// ─── Status / quality helpers ────────────────────────────────────────────────
// Design-system status tokens (theme-aware, no hardcoded palette colors).
const statusClass = s => {
  switch ((s || '').toUpperCase()) {
    case 'APPROVED':
      return 'bg-n-teal-3 text-n-teal-11';
    case 'PENDING':
      return 'bg-n-amber-3 text-n-amber-11';
    case 'REJECTED':
      return 'bg-n-ruby-3 text-n-ruby-11';
    case 'PAUSED':
      return 'bg-n-amber-3 text-n-amber-11';
    default:
      return 'bg-n-alpha-2 text-n-slate-11';
  }
};
const qualityClass = q => {
  switch ((q || '').toUpperCase()) {
    case 'GREEN':
      return 'text-n-teal-11';
    case 'YELLOW':
      return 'text-n-amber-11';
    case 'RED':
      return 'text-n-ruby-11';
    default:
      return 'text-n-slate-10';
  }
};
// ─── Template actions ─────────────────────────────────────────────────────────
const deleteTemplate = async tpl => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(t('JABVOX_WA_TEMPLATES.DELETE_CONFIRM', { name: tpl.name }))
  )
    return;
  try {
    await wtTemplatesAPI.destroy(tpl.id);
    useAlert(t('JABVOX_WA_TEMPLATES.DELETED'));
    loadTemplates();
    loadMetrics();
  } catch (err) {
    useAlert(err?.response?.data?.error || t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const syncTemplate = async tpl => {
  try {
    await wtTemplatesAPI.sync(tpl.id);
    useAlert(t('JABVOX_WA_TEMPLATES.SYNCED'));
    loadTemplates();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const exportJson = async () => {
  try {
    const { data } = await wtExportAPI.exportJson(selectedInboxId.value);
    const url = URL.createObjectURL(
      new Blob([data], { type: 'application/json' })
    );
    const a = document.createElement('a');
    a.href = url;
    a.download = 'wa_templates.json';
    a.click();
    URL.revokeObjectURL(url);
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

// ─── Import ──────────────────────────────────────────────────────────────────
const showImport = ref(false);
const importJsonText = ref('');
const importing = ref(false);

const submitImport = async () => {
  if (!selectedInboxId.value) {
    useAlert('Selecciona una bandeja primero');
    return;
  }
  importing.value = true;
  try {
    const parsed = JSON.parse(importJsonText.value);
    const { data } = await wtImportAPI.importJson(
      selectedInboxId.value,
      parsed
    );
    useAlert(t('JABVOX_WA_TEMPLATES.IMPORT.SUCCESS', { count: data.imported }));
    showImport.value = false;
    importJsonText.value = '';
    loadTemplates();
    loadMetrics();
  } catch (err) {
    useAlert(err?.response?.data?.error || 'JSON inválido');
  } finally {
    importing.value = false;
  }
};

// ─── Create / Edit form ──────────────────────────────────────────────────────
const showForm = ref(false);
const editingTemplate = ref(null);
const formInboxId = ref(null);
const saving = ref(false);

const LANGUAGES = [
  { value: 'es', label: 'Español' },
  { value: 'es_CO', label: 'Español (Colombia)' },
  { value: 'es_MX', label: 'Español (México)' },
  { value: 'es_AR', label: 'Español (Argentina)' },
  { value: 'en_US', label: 'English (US)' },
  { value: 'en_GB', label: 'English (UK)' },
  { value: 'pt_BR', label: 'Português (Brasil)' },
  { value: 'pt_PT', label: 'Português (Portugal)' },
  { value: 'fr', label: 'Français' },
  { value: 'de', label: 'Deutsch' },
];
const CATEGORIES = ['MARKETING', 'UTILITY', 'AUTHENTICATION'];
const BUTTON_TYPES = ['QUICK_REPLY', 'URL', 'PHONE_NUMBER'];
const HEADER_FORMATS = ['NONE', 'TEXT', 'IMAGE', 'VIDEO', 'DOCUMENT'];

const emptyForm = () => ({
  name: '',
  category: 'UTILITY',
  language: 'es',
  header_type: 'NONE',
  header_content: '',
  body: '',
  footer: '',
  buttons: [],
  var_descriptions: {},
});
const form = ref(emptyForm());

const detectedVars = computed(() => {
  const matches = (form.value.body || '').match(/\{\{(\d+)\}\}/g) || [];
  const nums = [
    ...new Set(matches.map(m => parseInt(m.replace(/[{}]/g, ''), 10))),
  ].sort((a, b) => a - b);
  return nums;
});

const addButton = () => {
  if (form.value.buttons.length >= 3) return;
  form.value.buttons.push({
    type: 'QUICK_REPLY',
    text: '',
    url: '',
    phone_number: '',
  });
};
const removeButton = i => form.value.buttons.splice(i, 1);

const openCreate = () => {
  editingTemplate.value = null;
  form.value = emptyForm();
  formInboxId.value = selectedInboxId.value || (inboxes.value[0]?.id ?? null);
  // eslint-disable-next-line no-use-before-define
  wizardStep.value = 1;
  showForm.value = true;
};

const openEdit = tpl => {
  editingTemplate.value = tpl;
  form.value = {
    name: tpl.name,
    category: tpl.category,
    language: tpl.language,
    header_type: tpl.header_type || 'NONE',
    header_content: tpl.header_content || '',
    body: tpl.body_content || '',
    footer: tpl.footer_content || '',
    buttons: (tpl.buttons_json || []).map(b => ({ ...b })),
    var_descriptions: Object.fromEntries(
      Object.entries(tpl.variables_json || {}).map(([k, v]) => [k, v])
    ),
  };
  formInboxId.value = tpl.inbox_id;
  // eslint-disable-next-line no-use-before-define
  wizardStep.value = 1;
  showForm.value = true;
};

const submitForm = async () => {
  saving.value = true;
  const payload = {
    name: form.value.name,
    category: form.value.category,
    language: form.value.language,
    header_type:
      form.value.header_type !== 'NONE' ? form.value.header_type : null,
    header_content: form.value.header_content,
    body: form.value.body,
    footer: form.value.footer,
    buttons: form.value.buttons.filter(b => b.text),
    inbox_id: formInboxId.value,
  };
  try {
    if (editingTemplate.value) {
      await wtTemplatesAPI.update(editingTemplate.value.id, payload);
      useAlert(t('JABVOX_WA_TEMPLATES.UPDATED'));
    } else {
      await wtTemplatesAPI.create(payload);
      useAlert(t('JABVOX_WA_TEMPLATES.CREATED'));
    }
    showForm.value = false;
    form.value = emptyForm();
    loadTemplates();
    loadMetrics();
  } catch (err) {
    useAlert(err?.response?.data?.error || t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    saving.value = false;
  }
};

const wizardStep = ref(1);
const wizardSteps = [
  { id: 1, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.BASIC') },
  { id: 2, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.CONTENT') },
  { id: 3, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.VARIABLES') },
  { id: 4, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.BUTTONS') },
  { id: 5, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.PREVIEW') },
  { id: 6, label: t('JABVOX_WA_TEMPLATES.CREATE.STEPS.SUBMIT') },
];

const nextWizardStep = () => {
  if (wizardStep.value < 6) wizardStep.value += 1;
};

const previousWizardStep = () => {
  if (wizardStep.value > 1) wizardStep.value -= 1;
};

const templateAnalytics = computed(() => {
  // eslint-disable-next-line no-use-before-define
  const raw = detailTemplate.value?.meta_json?.analytics || {};
  return {
    sent: raw.sent || 0,
    delivered: raw.delivered || 0,
    read: raw.read || 0,
    replied: raw.replied || 0,
    failed: raw.failed || 0,
    blocked: raw.blocked || 0,
  };
});

// ─── Detail / History / Versions ────────────────────────────────────────────
const detailTemplate = ref(null);
const detailHistory = ref([]);
const detailVersions = ref([]);
const detailTab = ref('components');
const loadingDetail = ref(false);

const openDetail = async tpl => {
  loadingDetail.value = true;
  detailTab.value = 'components';
  try {
    const [{ data: d }, { data: h }, { data: v }] = await Promise.all([
      wtTemplatesAPI.get(tpl.id),
      wtTemplatesAPI.history(tpl.id),
      wtTemplatesAPI.versions(tpl.id),
    ]);
    detailTemplate.value = d;
    detailHistory.value = h.history || [];
    detailVersions.value = v.versions || [];
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    loadingDetail.value = false;
  }
};

const closeDetail = () => {
  detailTemplate.value = null;
};

const restoreVersion = async ver => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('JABVOX_WA_TEMPLATES.DETAIL.RESTORE_CONFIRM', { v: ver.version })
    )
  )
    return;
  try {
    await wtTemplatesAPI.restoreVersion(detailTemplate.value.id, ver.id);
    useAlert(t('JABVOX_WA_TEMPLATES.RESTORED'));
    openDetail(detailTemplate.value);
    loadTemplates();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const duplicateTemplate = async tpl => {
  // eslint-disable-next-line no-alert
  const newName = window.prompt(
    t('JABVOX_WA_TEMPLATES.DETAIL.DUPLICATE_NAME'),
    `${tpl.name}_copy`
  );
  if (!newName) return;
  try {
    await wtTemplatesAPI.duplicate(tpl.id, newName);
    useAlert(t('JABVOX_WA_TEMPLATES.DUPLICATED'));
    loadTemplates();
    loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

// ─── Permissions ─────────────────────────────────────────────────────────────
const permissions = ref([]);
const loadPermissions = async () => {
  try {
    const { data } = await wtPermissionsAPI.getAll();
    permissions.value = data.permissions || [];
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};
const savePermissions = async () => {
  const ids = permissions.value.filter(p => p.can_manage).map(p => p.user_id);
  try {
    await wtPermissionsAPI.bulk(ids);
    useAlert(t('JABVOX_WA_TEMPLATES.PERMISSIONS.SAVED'));
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  }
};

const switchTab = async key => {
  activeTab.value = key;
  if (key === 'permissions' && !permissions.value.length)
    await loadPermissions();
  if (key === 'templates') {
    selectedTemplateIds.value = [];
  }
};

watch(selectedInboxId, () => {
  page.value = 1;
  loadTemplates();
  loadMetrics();
});

onMounted(async () => {
  await loadInboxes();
  await Promise.all([loadTemplates(), loadMetrics()]);
});
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="flex flex-col flex-1 h-full overflow-hidden bg-n-bg-1">
    <div
      ref="stickyHeaderRef"
      class="sticky top-0 z-20 border-b border-n-weak bg-n-surface-1/95 backdrop-blur"
    >
      <div class="flex flex-col gap-4 px-4 sm:px-6 py-4">
        <div
          class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4"
        >
          <div>
            <h1 class="text-xl sm:text-2xl font-semibold text-n-slate-12">
              {{ t('JABVOX_WA_TEMPLATES.HEADER.TITLE') }}
            </h1>
            <p class="text-xs sm:text-sm text-n-slate-10 mt-1 max-w-2xl">
              {{ t('JABVOX_WA_TEMPLATES.HEADER.SUBTITLE') }}
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <button
              class="px-3 py-1.5 text-xs rounded-lg bg-n-brand text-white hover:opacity-90 flex items-center gap-1.5 transition-opacity"
              @click="openCreate"
            >
              <span class="i-lucide-plus size-3.5" />
              {{ t('JABVOX_WA_TEMPLATES.HEADER.CREATE') }}
            </button>
            <button
              class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 flex items-center gap-1.5 disabled:opacity-50 transition-colors"
              :disabled="syncing || !selectedInboxId"
              @click="syncInbox"
            >
              <span
                :class="
                  syncing
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-refresh-cw'
                "
                class="size-3.5"
              />
              {{ t('JABVOX_WA_TEMPLATES.HEADER.SYNC') }}
            </button>
            <button
              class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 flex items-center gap-1.5 transition-colors"
              @click="showImport = true"
            >
              <span class="i-lucide-upload size-3.5" />
              {{ t('JABVOX_WA_TEMPLATES.HEADER.IMPORT') }}
            </button>
            <button
              class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 flex items-center gap-1.5 transition-colors"
              @click="exportJson"
            >
              <span class="i-lucide-download size-3.5" />
              {{ t('JABVOX_WA_TEMPLATES.HEADER.EXPORT') }}
            </button>
          </div>
        </div>

        <div
          class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-2 sm:gap-3"
        >
          <div
            v-for="kpi in summaryKpis"
            :key="kpi.key"
            class="group rounded-2xl border border-n-weak bg-n-surface-1 px-3 py-3.5 transition-all hover:-translate-y-0.5 hover:shadow-lg"
          >
            <div class="flex items-start justify-between">
              <p class="text-[11px] uppercase tracking-wide text-n-slate-10">
                {{ kpi.label }}
              </p>
              <span :class="[kpi.icon, kpi.accent]" class="size-4" />
            </div>
            <p class="mt-2 text-xl sm:text-2xl font-semibold text-n-slate-12">
              {{ kpi.value }}
            </p>
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <div
        class="flex gap-0 border-t border-n-weak bg-n-surface-1 px-4 sm:px-6 shrink-0"
      >
        <button
          v-for="tab in ['overview', 'templates', 'permissions']"
          :key="tab"
          class="px-4 py-2.5 text-sm -mb-px border-b-2 transition-colors"
          :class="
            activeTab === tab
              ? 'border-n-brand text-n-brand font-medium'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="switchTab(tab)"
        >
          {{ t(`JABVOX_WA_TEMPLATES.TABS.${tab.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <!-- ── OVERVIEW TAB ──────────────────────────────────────────────── -->
    <div v-if="activeTab === 'overview'" class="flex-1 overflow-auto p-6">
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 mb-6">
        <div
          v-for="key in [
            'total',
            'approved',
            'pending',
            'rejected',
            'paused',
            'disabled',
            'quality_high',
            'quality_medium',
            'quality_low',
          ]"
          :key="key"
          class="rounded-xl border border-n-weak bg-n-surface-1 p-4"
        >
          <p class="text-xs text-n-slate-10 mb-1">
            {{ t(`JABVOX_WA_TEMPLATES.METRICS.${key.toUpperCase()}`) }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12">
            {{ metrics[key] ?? 0 }}
          </p>
        </div>
      </div>
      <h2 class="text-sm font-medium text-n-slate-12 mb-3">
        {{ t('JABVOX_WA_TEMPLATES.INBOX.LABEL') }}
      </h2>
      <div v-if="!inboxes.length" class="text-sm text-n-slate-11 py-4">
        {{ t('JABVOX_WA_TEMPLATES.INBOX.NONE') }}
      </div>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <div
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="rounded-xl border border-n-weak bg-n-surface-1 p-4 flex items-center justify-between"
        >
          <div>
            <p class="font-medium text-n-slate-12 text-sm">{{ inbox.name }}</p>
            <p class="text-xs text-n-slate-10">{{ inbox.phone_number }}</p>
            <p class="text-xs text-n-slate-10">
              WABA: {{ inbox.waba_id || '—' }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ inbox.template_count }}
              {{ t('JABVOX_WA_TEMPLATES.INBOX.TEMPLATES') }}
            </p>
          </div>
          <button
            class="px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 flex items-center gap-1"
            :disabled="syncing"
            @click="
              selectedInboxId = inbox.id;
              syncInbox();
            "
          >
            <span class="i-lucide-refresh-cw size-3" />
          </button>
        </div>
      </div>
    </div>

    <!-- ── TEMPLATES TAB ─────────────────────────────────────────────── -->
    <div
      v-else-if="activeTab === 'templates'"
      class="flex-1 overflow-hidden flex flex-col"
    >
      <!-- Advanced search and filters -->
      <div
        class="px-4 sm:px-6 py-4 bg-n-surface-1 border-b border-n-weak shrink-0 space-y-3"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-6 gap-2">
          <div class="xl:col-span-2">
            <input
              v-model="filters.q"
              class="reset-base text-sm w-full"
              :placeholder="t('JABVOX_WA_TEMPLATES.FILTERS.SEARCH_PLACEHOLDER')"
              @keyup.enter="applyFilters"
            />
          </div>
          <div>
            <input
              v-model="filters.meta_id"
              class="reset-base text-sm w-full"
              :placeholder="
                t('JABVOX_WA_TEMPLATES.FILTERS.META_ID_PLACEHOLDER')
              "
              @keyup.enter="applyFilters"
            />
          </div>
          <div>
            <select v-model="selectedInboxId" class="reset-base text-sm w-full">
              <option :value="null">
                {{ t('JABVOX_WA_TEMPLATES.INBOX.ALL') }}
              </option>
              <option v-for="i in inboxes" :key="i.id" :value="i.id">
                {{ i.name }}
              </option>
            </select>
          </div>
          <div>
            <select
              v-model="filters.language"
              class="reset-base text-sm w-full"
            >
              <option value="">
                {{ t('JABVOX_WA_TEMPLATES.FILTERS.ALL_LANGUAGES') }}
              </option>
              <option v-for="l in LANGUAGES" :key="l.value" :value="l.value">
                {{ l.label }}
              </option>
            </select>
          </div>
          <div class="flex items-center gap-2">
            <button
              class="px-3 py-2 text-sm rounded-lg bg-n-brand text-white"
              @click="applyFilters"
            >
              {{ t('JABVOX_WA_TEMPLATES.FILTERS.APPLY') }}
            </button>
            <button
              class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
              @click="clearFilters"
            >
              {{ t('JABVOX_WA_TEMPLATES.FILTERS.CLEAR') }}
            </button>
          </div>
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            v-for="s in statusQuickFilters"
            :key="`status_${s}`"
            class="px-2.5 py-1 rounded-full text-xs border transition-colors"
            :class="
              filterChipActive('status', s)
                ? 'border-n-brand bg-n-brand text-white'
                : 'border-n-weak text-n-slate-11 bg-n-surface-1 hover:bg-n-alpha-1'
            "
            @click="applyQuickFilter('status', s)"
          >
            {{ t(`JABVOX_WA_TEMPLATES.STATUS.${s}`) }}
          </button>
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            v-for="c in categoryQuickFilters"
            :key="`cat_${c}`"
            class="px-2.5 py-1 rounded-full text-xs border transition-colors"
            :class="
              filterChipActive('category', c)
                ? 'border-n-brand bg-n-brand text-white'
                : 'border-n-weak text-n-slate-11 bg-n-surface-1 hover:bg-n-alpha-1'
            "
            @click="applyQuickFilter('category', c)"
          >
            {{ categoryLabel(c) }}
          </button>
        </div>

        <div
          v-if="selectedCount"
          class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2"
        >
          <span class="text-xs text-n-slate-11">
            {{
              t('JABVOX_WA_TEMPLATES.BULK.SELECTED', { count: selectedCount })
            }}
          </span>
          <div class="flex flex-wrap gap-2">
            <button
              class="px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors"
              @click="bulkSync"
            >
              {{ t('JABVOX_WA_TEMPLATES.BULK.SYNC') }}
            </button>
            <button
              class="px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors"
              @click="bulkDuplicate"
            >
              {{ t('JABVOX_WA_TEMPLATES.BULK.DUPLICATE') }}
            </button>
            <button
              class="px-2.5 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors"
              @click="bulkExportSelected"
            >
              {{ t('JABVOX_WA_TEMPLATES.BULK.EXPORT') }}
            </button>
            <button
              class="px-2.5 py-1.5 text-xs rounded-lg bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4 transition-colors"
              @click="bulkDelete"
            >
              {{ t('JABVOX_WA_TEMPLATES.BULK.DELETE') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Cards gallery -->
      <div class="flex-1 overflow-auto px-4 sm:px-6 py-4">
        <div
          v-if="loadingTemplates"
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-4"
        >
          <div
            v-for="n in 8"
            :key="n"
            class="rounded-2xl border border-n-weak bg-n-surface-1 p-4 animate-pulse"
          >
            <div class="h-4 w-2/3 bg-n-alpha-2 rounded mb-2" />
            <div class="h-3 w-1/2 bg-n-alpha-2 rounded mb-4" />
            <div class="h-40 bg-n-alpha-2 rounded-xl mb-3" />
            <div class="h-3 w-1/3 bg-n-alpha-2 rounded" />
          </div>
        </div>

        <div
          v-else-if="!templates.length"
          class="rounded-2xl border border-dashed border-n-weak bg-n-surface-1 py-20 text-center"
        >
          <p class="text-base font-medium text-n-slate-12">
            {{ t('JABVOX_WA_TEMPLATES.GALLERY.EMPTY_TITLE') }}
          </p>
          <p class="text-sm text-n-slate-10 mt-1 max-w-md mx-auto">
            {{ t('JABVOX_WA_TEMPLATES.GALLERY.EMPTY_BODY') }}
          </p>
          <button
            class="mt-4 px-4 py-2 text-sm rounded-lg bg-n-brand text-white hover:opacity-90 transition-opacity"
            @click="openCreate"
          >
            {{ t('JABVOX_WA_TEMPLATES.GALLERY.EMPTY_CTA') }}
          </button>
        </div>

        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-4"
        >
          <label
            class="col-span-full flex items-center gap-2 text-xs text-n-slate-10"
          >
            <input
              :checked="allVisibleSelected"
              type="checkbox"
              class="size-4"
              @change="toggleSelectAll($event.target.checked)"
            />
            {{ t('JABVOX_WA_TEMPLATES.GALLERY.SELECT_ALL') }}
          </label>

          <article
            v-for="tpl in templates"
            :key="tpl.id"
            class="group rounded-2xl border border-n-weak bg-n-surface-1 p-4 transition-all hover:-translate-y-0.5 hover:shadow-lg"
          >
            <div class="flex items-start justify-between gap-2 mb-3">
              <label
                class="inline-flex items-center gap-2 text-xs text-n-slate-11"
              >
                <input
                  :checked="selectedTemplateIds.includes(tpl.id)"
                  type="checkbox"
                  class="size-4"
                  @change="toggleSelectOne(tpl.id, $event.target.checked)"
                />
              </label>
              <span
                class="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-full"
                :class="statusClass(tpl.status)"
              >
                {{ t(`JABVOX_WA_TEMPLATES.STATUS.${tpl.status}`) }}
              </span>
            </div>

            <button class="w-full text-left" @click="openDetail(tpl)">
              <h3 class="text-sm font-semibold text-n-slate-12 truncate">
                {{ tpl.name }}
              </h3>
              <p class="text-xs text-n-slate-10 mt-0.5">
                {{ tpl.language }} · {{ tpl.category }} ·
                {{
                  tpl.meta_template_id ||
                  t('JABVOX_WA_TEMPLATES.GALLERY.NO_META_ID')
                }}
              </p>

              <div class="mt-3 rounded-xl bg-[#0b141a] p-2.5">
                <div
                  class="rounded-lg bg-[#202c33] p-2 text-[11px] text-white/90"
                >
                  <p
                    v-if="tpl.header_type === 'TEXT' && tpl.header_content"
                    class="font-semibold border-b border-white/10 pb-1 mb-1"
                  >
                    {{ tpl.header_content }}
                  </p>
                  <p class="line-clamp-3 whitespace-pre-wrap">
                    {{ tpl.body_content || '…' }}
                  </p>
                  <p
                    v-if="tpl.footer_content"
                    class="text-white/40 mt-1 line-clamp-1"
                  >
                    {{ tpl.footer_content }}
                  </p>
                </div>
                <div v-if="tpl.buttons_json?.length" class="mt-1.5 grid gap-1">
                  <div
                    v-for="btn in tpl.buttons_json.slice(0, 2)"
                    :key="`${tpl.id}_${btn.text}`"
                    class="rounded bg-[#2a3942] py-1 text-center text-[10px] text-[#53bdeb]"
                  >
                    {{ btn.text }}
                  </div>
                </div>
              </div>

              <div class="mt-3 grid grid-cols-2 gap-2 text-xs">
                <div>
                  <p class="text-n-slate-9">
                    {{ t('JABVOX_WA_TEMPLATES.GALLERY.VARIABLES') }}
                  </p>
                  <p class="text-n-slate-12 font-medium">
                    {{ Object.keys(tpl.variables_json || {}).length }}
                  </p>
                </div>
                <div>
                  <p class="text-n-slate-9">
                    {{ t('JABVOX_WA_TEMPLATES.GALLERY.BUTTONS') }}
                  </p>
                  <p class="text-n-slate-12 font-medium">
                    {{ (tpl.buttons_json || []).length }}
                  </p>
                </div>
                <div>
                  <p class="text-n-slate-9">
                    {{ t('JABVOX_WA_TEMPLATES.GALLERY.CREATED') }}
                  </p>
                  <p class="text-n-slate-12 font-medium">
                    {{ new Date(tpl.created_at).toLocaleDateString() }}
                  </p>
                </div>
                <div>
                  <p class="text-n-slate-9">
                    {{ t('JABVOX_WA_TEMPLATES.GALLERY.UPDATED') }}
                  </p>
                  <p class="text-n-slate-12 font-medium">
                    {{ new Date(tpl.updated_at).toLocaleDateString() }}
                  </p>
                </div>
              </div>
            </button>

            <div class="mt-3 flex items-center gap-1.5">
              <button
                class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
                @click="openEdit(tpl)"
              >
                <span class="i-lucide-pencil size-3.5" />
              </button>
              <button
                class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
                @click="duplicateTemplate(tpl)"
              >
                <span class="i-lucide-copy size-3.5" />
              </button>
              <button
                class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
                @click="syncTemplate(tpl)"
              >
                <span class="i-lucide-refresh-cw size-3.5" />
              </button>
              <button
                class="p-1.5 rounded hover:bg-n-alpha-2 text-n-ruby-11"
                @click="deleteTemplate(tpl)"
              >
                <span class="i-lucide-trash-2 size-3.5" />
              </button>
            </div>
          </article>
        </div>

        <!-- Pagination -->
        <div
          v-if="totalPages > 1"
          class="flex items-center justify-center gap-4 pt-4 text-sm text-n-slate-11"
        >
          <button
            class="px-3 py-1 rounded bg-n-alpha-2 disabled:opacity-50"
            :disabled="page <= 1"
            @click="changePage(-1)"
          >
            &#8249;
          </button>
          <span>{{ page }} / {{ totalPages }} ({{ totalTemplates }})</span>
          <button
            class="px-3 py-1 rounded bg-n-alpha-2 disabled:opacity-50"
            :disabled="page >= totalPages"
            @click="changePage(1)"
          >
            &#8250;
          </button>
        </div>
      </div>
    </div>

    <!-- ── PERMISSIONS TAB ───────────────────────────────────────────── -->
    <div v-else class="flex-1 overflow-auto p-6 max-w-2xl">
      <p class="text-sm text-n-slate-11 mb-4">
        {{ t('JABVOX_WA_TEMPLATES.PERMISSIONS.DESCRIPTION') }}
      </p>
      <div
        v-for="perm in permissions"
        :key="perm.user_id"
        class="flex items-center justify-between p-2.5 border-b border-n-weak"
      >
        <div>
          <span class="text-sm text-n-slate-12">{{ perm.name }}</span>
          <span class="ml-2 text-xs text-n-slate-10">{{ perm.email }}</span>
        </div>
        <input v-model="perm.can_manage" type="checkbox" class="size-4" />
      </div>
      <button
        class="mt-4 px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
        @click="savePermissions"
      >
        {{ t('JABVOX_WA_TEMPLATES.PERMISSIONS.SAVE') }}
      </button>
    </div>

    <!-- ── CREATE / EDIT FORM MODAL ──────────────────────────────────── -->
    <div v-if="showForm" class="fixed inset-0 z-50 flex">
      <div class="absolute inset-0 bg-black/50" @click="showForm = false" />
      <div
        class="relative ml-auto w-full md:max-w-[900px] h-full bg-n-surface-1 shadow-xl flex overflow-hidden"
      >
        <!-- Left: form -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <div
            class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak shrink-0"
          >
            <h2 class="font-semibold text-n-slate-12">
              {{
                editingTemplate
                  ? t('JABVOX_WA_TEMPLATES.CREATE.EDIT_TITLE')
                  : t('JABVOX_WA_TEMPLATES.CREATE.TITLE')
              }}
            </h2>
            <button
              class="text-n-slate-11 hover:text-n-slate-12"
              @click="showForm = false"
            >
              <span class="i-lucide-x size-5" />
            </button>
          </div>
          <div
            class="px-5 py-3 border-b border-n-weak shrink-0 overflow-x-auto"
          >
            <div class="flex items-center gap-2 min-w-max">
              <button
                v-for="step in wizardSteps"
                :key="step.id"
                class="inline-flex items-center gap-2 px-2.5 py-1.5 rounded-full text-xs border"
                :class="
                  wizardStep >= step.id
                    ? 'border-n-brand bg-n-brand text-white'
                    : 'border-n-weak text-n-slate-10 bg-n-surface-1'
                "
                @click="wizardStep = step.id"
              >
                <span
                  class="size-4 rounded-full bg-white/20 inline-flex items-center justify-center"
                  >{{ step.id }}</span
                >
                <span>{{ step.label }}</span>
              </button>
            </div>
          </div>

          <div class="flex-1 overflow-auto p-5 space-y-5">
            <section v-if="wizardStep === 1" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.SECTION_BASIC') }}
              </h3>
              <div class="grid grid-cols-2 gap-3">
                <div
                  v-if="!editingTemplate"
                  class="col-span-2 flex flex-col gap-1"
                >
                  <label class="text-xs text-n-slate-11">{{
                    t('JABVOX_WA_TEMPLATES.CREATE.INBOX_LABEL')
                  }}</label>
                  <select v-model="formInboxId" class="reset-base text-sm">
                    <option v-for="i in inboxes" :key="i.id" :value="i.id">
                      {{ i.name }} — {{ i.phone_number }}
                    </option>
                  </select>
                </div>
                <div v-if="!editingTemplate" class="flex flex-col gap-1">
                  <label class="text-xs text-n-slate-11">{{
                    t('JABVOX_WA_TEMPLATES.CREATE.NAME_LABEL')
                  }}</label>
                  <input
                    v-model="form.name"
                    class="reset-base text-sm"
                    :placeholder="
                      t('JABVOX_WA_TEMPLATES.CREATE.NAME_PLACEHOLDER')
                    "
                  />
                  <span class="text-xs text-n-slate-10">{{
                    t('JABVOX_WA_TEMPLATES.CREATE.NAME_HINT')
                  }}</span>
                </div>
                <div class="flex flex-col gap-1">
                  <label class="text-xs text-n-slate-11">{{
                    t('JABVOX_WA_TEMPLATES.CREATE.CATEGORY_LABEL')
                  }}</label>
                  <select v-model="form.category" class="reset-base text-sm">
                    <option v-for="c in CATEGORIES" :key="c" :value="c">
                      {{ t(`JABVOX_WA_TEMPLATES.CATEGORIES.${c}`) }}
                    </option>
                  </select>
                </div>
                <div class="flex flex-col gap-1">
                  <label class="text-xs text-n-slate-11">{{
                    t('JABVOX_WA_TEMPLATES.CREATE.LANGUAGE_LABEL')
                  }}</label>
                  <select v-model="form.language" class="reset-base text-sm">
                    <option
                      v-for="l in LANGUAGES"
                      :key="l.value"
                      :value="l.value"
                    >
                      {{ l.label }}
                    </option>
                  </select>
                </div>
              </div>
            </section>

            <section v-if="wizardStep === 2" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.SECTION_CONTENT') }}
              </h3>
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_WA_TEMPLATES.CREATE.HEADER_TYPE_LABEL')
                }}</label>
                <select
                  v-model="form.header_type"
                  class="reset-base text-sm w-40"
                >
                  <option v-for="f in HEADER_FORMATS" :key="f" :value="f">
                    {{
                      f === 'NONE'
                        ? t('JABVOX_WA_TEMPLATES.CREATE.HEADER_NONE')
                        : f
                    }}
                  </option>
                </select>
              </div>
              <input
                v-if="form.header_type === 'TEXT'"
                v-model="form.header_content"
                class="reset-base text-sm w-full"
                :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.HEADER_TEXT_PH')"
                maxlength="60"
              />
              <p
                v-else-if="form.header_type && form.header_type !== 'NONE'"
                class="text-xs text-n-slate-10"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.HEADER_MEDIA_NOTE') }}
              </p>
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_WA_TEMPLATES.CREATE.BODY_LABEL')
                }}</label>
                <textarea
                  v-model="form.body"
                  rows="5"
                  class="reset-base text-sm w-full resize-none"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.BODY_PH')"
                />
              </div>
              <div class="flex flex-col gap-1">
                <label class="text-xs text-n-slate-11">{{
                  t('JABVOX_WA_TEMPLATES.CREATE.FOOTER_LABEL')
                }}</label>
                <input
                  v-model="form.footer"
                  class="reset-base text-sm w-full"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.FOOTER_PH')"
                />
              </div>
            </section>

            <section v-if="wizardStep === 3" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.VARS_MANAGER') }}
              </h3>
              <div
                v-if="detectedVars.length"
                class="rounded-lg bg-n-alpha-1 p-3 space-y-2"
              >
                <p class="text-xs font-medium text-n-slate-11">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.VARS_TITLE') }}
                </p>
                <div
                  v-for="n in detectedVars"
                  :key="n"
                  class="flex items-center gap-2"
                >
                  <span
                    class="text-xs font-mono bg-n-alpha-2 px-2 py-0.5 rounded text-n-brand"
                  >
                    &#123;&#123;{{ n }}&#125;&#125;
                  </span>
                  <input
                    v-model="form.var_descriptions[n]"
                    class="reset-base text-xs flex-1"
                    :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.VAR_DESC_PH')"
                  />
                </div>
              </div>
              <div
                v-else
                class="rounded-lg border border-dashed border-n-weak p-4 text-sm text-n-slate-10"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.VARS_EMPTY') }}
              </div>
            </section>

            <section v-if="wizardStep === 4" class="space-y-2">
              <div class="flex items-center justify-between">
                <h3
                  class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.BUTTONS_LABEL') }}
                </h3>
                <button
                  v-if="form.buttons.length < 3"
                  class="text-xs text-n-brand hover:underline"
                  @click="addButton"
                >
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.ADD_BUTTON') }}
                </button>
              </div>
              <div
                v-for="(btn, i) in form.buttons"
                :key="i"
                class="flex flex-wrap gap-2 items-center p-2.5 rounded-lg bg-n-alpha-1"
              >
                <select v-model="btn.type" class="reset-base text-xs w-32">
                  <option v-for="bt in BUTTON_TYPES" :key="bt" :value="bt">
                    {{ bt }}
                  </option>
                </select>
                <input
                  v-model="btn.text"
                  class="reset-base text-xs flex-1 min-w-24"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_TEXT')"
                />
                <input
                  v-if="btn.type === 'URL'"
                  v-model="btn.url"
                  class="reset-base text-xs flex-1 min-w-36"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_URL')"
                />
                <input
                  v-if="btn.type === 'PHONE_NUMBER'"
                  v-model="btn.phone_number"
                  class="reset-base text-xs flex-1 min-w-36"
                  :placeholder="t('JABVOX_WA_TEMPLATES.CREATE.BUTTON_PHONE')"
                />
                <button class="text-n-ruby-11 p-1" @click="removeButton(i)">
                  <span class="i-lucide-trash-2 size-3.5" />
                </button>
              </div>
            </section>

            <section v-if="wizardStep === 5" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.PREVIEW_HEADING') }}
              </h3>
              <p class="text-sm text-n-slate-11">
                {{ t('JABVOX_WA_TEMPLATES.CREATE.PREVIEW_NOTE') }}
              </p>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
                <p class="text-xs text-n-slate-10 mb-2">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_TITLE') }}
                </p>
                <div class="grid grid-cols-2 gap-3 text-xs text-n-slate-11">
                  <p>
                    <span class="text-n-slate-9">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_CATEGORY') }}
                    </span>
                    {{ form.category }}
                  </p>
                  <p>
                    <span class="text-n-slate-9">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_LANGUAGE') }}
                    </span>
                    {{ form.language }}
                  </p>
                  <p>
                    <span class="text-n-slate-9">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_VARIABLES') }}
                    </span>
                    {{ detectedVars.length }}
                  </p>
                  <p>
                    <span class="text-n-slate-9">
                      {{ t('JABVOX_WA_TEMPLATES.CREATE.SUMMARY_BUTTONS') }}
                    </span>
                    {{ form.buttons.filter(b => b.text).length }}
                  </p>
                </div>
              </div>
            </section>

            <section v-if="wizardStep === 6" class="space-y-3">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('JABVOX_WA_TEMPLATES.CREATE.SUBMIT_HEADING') }}
              </h3>
              <div
                class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 space-y-2 text-sm text-n-slate-11"
              >
                <p>{{ t('JABVOX_WA_TEMPLATES.CREATE.SUBMIT_NOTE') }}</p>
                <p class="text-xs text-n-slate-10">
                  {{ t('JABVOX_WA_TEMPLATES.CREATE.SUBMIT_HINT') }}
                </p>
              </div>
            </section>
          </div>
          <div class="flex gap-3 px-5 py-3.5 border-t border-n-weak shrink-0">
            <button
              class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
              :disabled="wizardStep === 1"
              @click="previousWizardStep"
            >
              Back
            </button>
            <button
              v-if="wizardStep < 6"
              class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
              @click="nextWizardStep"
            >
              Next
            </button>
            <button
              v-if="wizardStep === 6"
              class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
              :disabled="saving || !form.body"
              @click="submitForm"
            >
              {{
                saving
                  ? t('JABVOX_WA_TEMPLATES.CREATE.SUBMITTING')
                  : editingTemplate
                    ? t('JABVOX_WA_TEMPLATES.CREATE.UPDATE')
                    : t('JABVOX_WA_TEMPLATES.CREATE.SUBMIT')
              }}
            </button>
            <button
              class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
              @click="showForm = false"
            >
              {{ t('JABVOX_WA_TEMPLATES.CREATE.CANCEL') }}
            </button>
          </div>
        </div>
        <!-- Right: live preview -->
        <div
          class="hidden md:flex w-80 border-l border-n-weak bg-n-alpha-1 flex-col overflow-hidden shrink-0"
        >
          <div class="px-4 py-3 border-b border-n-weak">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('JABVOX_WA_TEMPLATES.CREATE.PREVIEW_TITLE') }}
            </p>
          </div>
          <div class="flex-1 overflow-auto p-4 flex items-start justify-center">
            <div
              class="w-full max-w-[200px] bg-[#0b141a] rounded-2xl p-3 shadow-lg"
            >
              <div
                class="bg-[#1f2c33] rounded-xl overflow-hidden text-white text-xs"
              >
                <div
                  class="bg-[#202c33] mx-2 mt-2 rounded-lg p-2.5 space-y-1.5 relative"
                >
                  <div
                    v-if="form.header_type === 'TEXT' && form.header_content"
                    class="font-semibold text-[11px] text-white/90 border-b border-white/10 pb-1.5 mb-1.5"
                  >
                    {{ form.header_content }}
                  </div>
                  <div
                    v-else-if="
                      form.header_type &&
                      form.header_type !== 'NONE' &&
                      form.header_type !== 'TEXT'
                    "
                    class="h-20 bg-white/10 rounded flex items-center justify-center text-white/40 text-[10px]"
                  >
                    {{ form.header_type }}
                  </div>
                  <p
                    class="text-[11px] leading-relaxed text-white/90 whitespace-pre-wrap"
                  >
                    {{ form.body || '…' }}
                  </p>
                  <p
                    v-if="form.footer"
                    class="text-[10px] text-white/40 border-t border-white/10 pt-1 mt-1"
                  >
                    {{ form.footer }}
                  </p>
                  <p class="text-right text-[9px] text-white/30">
                    {{
                      new Date().toLocaleTimeString([], {
                        hour: '2-digit',
                        minute: '2-digit',
                      })
                    }}
                  </p>
                </div>
                <div
                  v-if="form.buttons.filter(b => b.text).length"
                  class="mx-2 mb-2 mt-0.5 space-y-1"
                >
                  <div
                    v-for="btn in form.buttons.filter(b => b.text)"
                    :key="btn.text"
                    class="bg-[#2a3942] rounded py-1.5 text-center text-[11px] text-[#53bdeb] font-medium"
                  >
                    {{ btn.text }}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ── DETAIL DRAWER ──────────────────────────────────────────────── -->
    <div v-if="detailTemplate" class="fixed inset-0 z-50 flex justify-end">
      <div class="absolute inset-0 bg-black/40" @click="closeDetail" />
      <div
        class="relative w-full md:max-w-[900px] h-full bg-n-surface-1 shadow-2xl flex flex-col overflow-hidden"
      >
        <div
          class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak shrink-0"
        >
          <div>
            <h2 class="font-semibold text-n-slate-12">
              {{ detailTemplate.name }}
            </h2>
            <div class="flex items-center gap-2 mt-0.5">
              <span
                class="inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full"
                :class="statusClass(detailTemplate.status)"
              >
                {{ t(`JABVOX_WA_TEMPLATES.STATUS.${detailTemplate.status}`) }}
              </span>
              <span class="text-xs text-n-slate-10">
                {{ detailTemplate.language }} ·
                {{
                  t(`JABVOX_WA_TEMPLATES.CATEGORIES.${detailTemplate.category}`)
                }}
              </span>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <button
              class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3"
              @click="
                openEdit(detailTemplate);
                closeDetail();
              "
            >
              {{ t('JABVOX_WA_TEMPLATES.ACTIONS.EDIT') }}
            </button>
            <button class="text-n-slate-11" @click="closeDetail">
              <span class="i-lucide-x size-5" />
            </button>
          </div>
        </div>
        <div class="flex gap-0 border-b border-n-weak px-5 shrink-0">
          <button
            v-for="dt in [
              'components',
              'variables',
              'analytics',
              'history',
              'versions',
              'meta_json',
            ]"
            :key="dt"
            class="px-3 py-2 text-xs -mb-px border-b-2 transition-colors"
            :class="
              detailTab === dt
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-11'
            "
            @click="detailTab = dt"
          >
            {{ t(`JABVOX_WA_TEMPLATES.DETAIL.${dt.toUpperCase()}`) }}
          </button>
        </div>
        <div class="flex-1 overflow-auto p-5">
          <div v-if="detailTab === 'components'" class="space-y-4">
            <div
              v-if="detailTemplate.rejected_reason"
              class="p-3 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-400 text-sm"
            >
              <span class="font-medium">Razón de rechazo:</span>
              {{ detailTemplate.rejected_reason }}
            </div>
            <div class="grid grid-cols-2 gap-3 text-xs">
              <div>
                <span class="text-n-slate-10">Meta ID</span>
                <p class="font-mono text-n-slate-12 mt-0.5">
                  {{ detailTemplate.meta_template_id || '—' }}
                </p>
              </div>
              <div>
                <span class="text-n-slate-10">WABA ID</span>
                <p class="font-mono text-n-slate-12 mt-0.5">
                  {{ detailTemplate.waba_id || '—' }}
                </p>
              </div>
              <div>
                <span class="text-n-slate-10">Inbox</span>
                <p class="text-n-slate-12 mt-0.5">
                  {{ detailTemplate.inbox_name }}
                </p>
              </div>
              <div>
                <span class="text-n-slate-10">Calidad</span>
                <p
                  class="mt-0.5"
                  :class="qualityClass(detailTemplate.quality_score)"
                >
                  {{
                    t(
                      `JABVOX_WA_TEMPLATES.QUALITY.${detailTemplate.quality_score || 'UNKNOWN'}`
                    )
                  }}
                </p>
              </div>
            </div>
            <div
              v-if="detailTemplate.header_type"
              class="rounded-lg bg-n-alpha-1 p-3"
            >
              <p class="text-xs font-medium text-n-slate-10 mb-1">
                HEADER ({{ detailTemplate.header_type }})
              </p>
              <p class="text-sm text-n-slate-12">
                {{ detailTemplate.header_content || '(multimedia)' }}
              </p>
            </div>
            <div
              v-if="detailTemplate.body_content"
              class="rounded-lg bg-n-alpha-1 p-3"
            >
              <p class="text-xs font-medium text-n-slate-10 mb-1">BODY</p>
              <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
                {{ detailTemplate.body_content }}
              </p>
            </div>
            <div
              v-if="detailTemplate.footer_content"
              class="rounded-lg bg-n-alpha-1 p-3"
            >
              <p class="text-xs font-medium text-n-slate-10 mb-1">FOOTER</p>
              <p class="text-sm text-n-slate-12">
                {{ detailTemplate.footer_content }}
              </p>
            </div>
            <div v-if="detailTemplate.buttons_json?.length" class="space-y-1.5">
              <p class="text-xs font-medium text-n-slate-10">BUTTONS</p>
              <div
                v-for="btn in detailTemplate.buttons_json"
                :key="btn.text"
                class="flex items-center gap-2 text-xs p-2 rounded bg-n-alpha-1"
              >
                <span
                  class="font-mono bg-n-alpha-2 px-1.5 py-0.5 rounded text-n-brand"
                >
                  {{ btn.type }}
                </span>
                <span class="text-n-slate-12">{{ btn.text }}</span>
                <span v-if="btn.url" class="text-n-slate-10 truncate">{{
                  btn.url
                }}</span>
              </div>
            </div>
          </div>
          <div v-else-if="detailTab === 'variables'" class="space-y-2">
            <div
              v-if="!Object.keys(detailTemplate.variables_json || {}).length"
              class="text-sm text-n-slate-11"
            >
              —
            </div>
            <div
              v-for="(desc, n) in detailTemplate.variables_json"
              :key="n"
              class="flex items-center gap-3 p-2.5 rounded-lg bg-n-alpha-1"
            >
              <span
                class="font-mono text-sm text-n-brand bg-n-alpha-2 px-2 py-0.5 rounded"
              >
                &#123;&#123;{{ n }}&#125;&#125;
              </span>
              <span class="text-sm text-n-slate-11">{{ desc || '—' }}</span>
            </div>
          </div>
          <div v-else-if="detailTab === 'analytics'" class="space-y-3">
            <div class="grid grid-cols-2 md:grid-cols-3 gap-3">
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">Sent</p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.sent }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">Delivered</p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.delivered }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">Read</p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.read }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">Replied</p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.replied }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">Failed</p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.failed }}
                </p>
              </div>
              <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
                <p class="text-xs text-n-slate-10">Blocked</p>
                <p class="text-xl font-semibold text-n-slate-12">
                  {{ templateAnalytics.blocked }}
                </p>
              </div>
            </div>
          </div>
          <div v-else-if="detailTab === 'history'" class="space-y-2">
            <div v-if="!detailHistory.length" class="text-sm text-n-slate-11">
              —
            </div>
            <div
              v-for="log in detailHistory"
              :key="log.id"
              class="flex items-start gap-3 p-2.5 rounded-lg bg-n-alpha-1"
            >
              <span
                class="i-lucide-history size-4 text-n-slate-10 mt-0.5 shrink-0"
              />
              <div>
                <p class="text-sm text-n-slate-12">{{ log.description }}</p>
                <p class="text-xs text-n-slate-10">
                  {{ log.user_name }} ·
                  {{ new Date(log.created_at).toLocaleString() }}
                </p>
              </div>
            </div>
          </div>
          <div v-else-if="detailTab === 'versions'" class="space-y-2">
            <div v-if="!detailVersions.length" class="text-sm text-n-slate-11">
              —
            </div>
            <div
              v-for="ver in detailVersions"
              :key="ver.id"
              class="p-3 rounded-lg bg-n-alpha-1 space-y-1"
            >
              <div class="flex items-center justify-between">
                <span class="font-medium text-sm text-n-slate-12">
                  v{{ ver.version }}
                </span>
                <button
                  class="text-xs text-n-brand hover:underline"
                  @click="restoreVersion(ver)"
                >
                  {{ t('JABVOX_WA_TEMPLATES.DETAIL.RESTORE') }}
                </button>
              </div>
              <p class="text-xs text-n-slate-10">
                {{ ver.created_by_name }} ·
                {{ new Date(ver.created_at).toLocaleString() }}
              </p>
              <p class="text-xs text-n-slate-11 line-clamp-2">
                {{ ver.payload?.body_content }}
              </p>
            </div>
          </div>
          <div v-else-if="detailTab === 'meta_json'">
            <pre
              class="text-xs bg-n-alpha-1 rounded-lg p-3 overflow-auto text-n-slate-11 max-h-[500px]"
              >{{ JSON.stringify(detailTemplate.meta_json, null, 2) }}</pre
            >
          </div>
        </div>
      </div>
    </div>

    <!-- ── IMPORT MODAL ──────────────────────────────────────────────── -->
    <div
      v-if="showImport"
      class="fixed inset-0 z-50 flex items-center justify-center"
    >
      <div class="absolute inset-0 bg-black/50" @click="showImport = false" />
      <div
        class="relative bg-n-surface-1 rounded-xl shadow-2xl w-full max-w-lg p-5 space-y-4"
      >
        <div class="flex items-center justify-between">
          <h2 class="font-semibold text-n-slate-12">
            {{ t('JABVOX_WA_TEMPLATES.IMPORT.TITLE') }}
          </h2>
          <button @click="showImport = false">
            <span class="i-lucide-x size-5 text-n-slate-11" />
          </button>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">{{
            t('JABVOX_WA_TEMPLATES.INBOX.LABEL')
          }}</label>
          <select v-model="selectedInboxId" class="reset-base text-sm">
            <option v-for="i in inboxes" :key="i.id" :value="i.id">
              {{ i.name }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">{{
            t('JABVOX_WA_TEMPLATES.IMPORT.JSON_LABEL')
          }}</label>
          <textarea
            v-model="importJsonText"
            rows="10"
            class="reset-base text-xs font-mono w-full resize-none"
            :placeholder="t('JABVOX_WA_TEMPLATES.IMPORT.JSON_PH')"
          />
        </div>
        <div class="flex gap-3">
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
            :disabled="importing || !importJsonText.trim() || !selectedInboxId"
            @click="submitImport"
          >
            {{
              importing
                ? t('JABVOX_WA_TEMPLATES.LOADING')
                : t('JABVOX_WA_TEMPLATES.IMPORT.SUBMIT')
            }}
          </button>
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
            @click="showImport = false"
          >
            {{ t('JABVOX_WA_TEMPLATES.CREATE.CANCEL') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
