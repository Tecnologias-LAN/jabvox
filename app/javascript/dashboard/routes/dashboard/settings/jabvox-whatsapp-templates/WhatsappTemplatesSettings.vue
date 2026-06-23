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

const syncInbox = async () => {
  if (!selectedInboxId.value) return;
  syncing.value = true;
  try {
    await wtInboxesAPI.sync(selectedInboxId.value);
    useAlert(t('JABVOX_WA_TEMPLATES.SYNCED'));
    // eslint-disable-next-line no-use-before-define
    await loadTemplates();
    // eslint-disable-next-line no-use-before-define
    await loadMetrics();
  } catch {
    useAlert(t('JABVOX_WA_TEMPLATES.ERROR'));
  } finally {
    syncing.value = false;
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

const clearFilters = () => {
  filters.value = {
    q: '',
    status: '',
    category: '',
    language: '',
    date_from: '',
    date_to: '',
  };
  page.value = 1;
  // eslint-disable-next-line no-use-before-define
  loadTemplates();
};

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

// ─── Status / quality helpers ────────────────────────────────────────────────
const statusClass = s => {
  switch ((s || '').toUpperCase()) {
    case 'APPROVED':
      return 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400';
    case 'PENDING':
      return 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400';
    case 'REJECTED':
      return 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400';
    case 'PAUSED':
      return 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400';
    default:
      return 'bg-n-alpha-2 text-n-slate-11';
  }
};
const qualityClass = q => {
  switch ((q || '').toUpperCase()) {
    case 'GREEN':
      return 'text-green-600';
    case 'YELLOW':
      return 'text-yellow-600';
    case 'RED':
      return 'text-red-600';
    default:
      return 'text-n-slate-10';
  }
};
const qualityIcon = q => {
  switch ((q || '').toUpperCase()) {
    case 'GREEN':
      return 'i-lucide-trending-up';
    case 'YELLOW':
      return 'i-lucide-minus';
    case 'RED':
      return 'i-lucide-trending-down';
    default:
      return 'i-lucide-help-circle';
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

const exportCsv = async () => {
  try {
    const { data } = await wtExportAPI.exportCsv(selectedInboxId.value);
    const url = URL.createObjectURL(new Blob([data], { type: 'text/csv' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = 'wa_templates.csv';
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
    <!-- Header -->
    <div
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak bg-n-surface-1 shrink-0"
    >
      <div>
        <h1 class="text-xl font-semibold text-n-slate-12">
          {{ t('JABVOX_WA_TEMPLATES.SETTINGS.TITLE') }}
        </h1>
        <p class="text-xs text-n-slate-10 mt-0.5 max-w-xl">
          {{ t('JABVOX_WA_TEMPLATES.SETTINGS.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button
          class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 flex items-center gap-1.5"
          @click="exportJson"
        >
          <span class="i-lucide-download size-3.5" />{{
            t('JABVOX_WA_TEMPLATES.EXPORT.JSON')
          }}
        </button>
        <button
          class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 flex items-center gap-1.5"
          @click="exportCsv"
        >
          <span class="i-lucide-file-spreadsheet size-3.5" />{{
            t('JABVOX_WA_TEMPLATES.EXPORT.CSV')
          }}
        </button>
        <button
          class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 flex items-center gap-1.5"
          @click="showImport = true"
        >
          <span class="i-lucide-upload size-3.5" />{{
            t('JABVOX_WA_TEMPLATES.IMPORT.TITLE')
          }}
        </button>
        <button
          class="px-3 py-2 text-sm rounded-lg bg-n-brand text-white hover:opacity-90 flex items-center gap-1.5"
          @click="openCreate"
        >
          <span class="i-lucide-plus size-4" />{{
            t('JABVOX_WA_TEMPLATES.CREATE.TITLE')
          }}
        </button>
      </div>
    </div>

    <!-- Tabs -->
    <div class="flex gap-0 border-b border-n-weak bg-n-surface-1 px-6 shrink-0">
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
      <!-- Toolbar -->
      <div
        class="flex flex-wrap items-end gap-2 px-6 py-3 bg-n-surface-1 border-b border-n-weak shrink-0"
      >
        <div class="flex flex-col gap-0.5">
          <label class="text-xs text-n-slate-10">{{
            t('JABVOX_WA_TEMPLATES.INBOX.LABEL')
          }}</label>
          <select v-model="selectedInboxId" class="reset-base text-sm min-w-44">
            <option :value="null">
              {{ t('JABVOX_WA_TEMPLATES.INBOX.ALL') }}
            </option>
            <option v-for="i in inboxes" :key="i.id" :value="i.id">
              {{ i.name }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-0.5 flex-1 min-w-48">
          <label class="text-xs text-n-slate-10">{{
            t('JABVOX_WA_TEMPLATES.FILTERS.SEARCH')
          }}</label>
          <input
            v-model="filters.q"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_WA_TEMPLATES.FILTERS.SEARCH')"
            @keyup.enter="applyFilters"
          />
        </div>
        <div class="flex flex-col gap-0.5">
          <label class="text-xs text-n-slate-10">{{
            t('JABVOX_WA_TEMPLATES.FILTERS.STATUS')
          }}</label>
          <select v-model="filters.status" class="reset-base text-sm">
            <option value="">{{ t('JABVOX_WA_TEMPLATES.FILTERS.ALL') }}</option>
            <option
              v-for="s in [
                'APPROVED',
                'PENDING',
                'REJECTED',
                'PAUSED',
                'DISABLED',
              ]"
              :key="s"
              :value="s"
            >
              {{ t(`JABVOX_WA_TEMPLATES.STATUS.${s}`) }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-0.5">
          <label class="text-xs text-n-slate-10">{{
            t('JABVOX_WA_TEMPLATES.FILTERS.CATEGORY')
          }}</label>
          <select v-model="filters.category" class="reset-base text-sm">
            <option value="">{{ t('JABVOX_WA_TEMPLATES.FILTERS.ALL') }}</option>
            <option
              v-for="c in ['MARKETING', 'UTILITY', 'AUTHENTICATION']"
              :key="c"
              :value="c"
            >
              {{ t(`JABVOX_WA_TEMPLATES.CATEGORIES.${c}`) }}
            </option>
          </select>
        </div>
        <button
          class="px-3 py-1.5 text-sm rounded-lg bg-n-brand text-white mt-4"
          @click="applyFilters"
        >
          {{ t('JABVOX_WA_TEMPLATES.FILTERS.APPLY') }}
        </button>
        <button
          class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 mt-4"
          @click="clearFilters"
        >
          {{ t('JABVOX_WA_TEMPLATES.FILTERS.CLEAR') }}
        </button>
        <button
          v-if="selectedInboxId"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 mt-4 flex items-center gap-1.5 disabled:opacity-50"
          :disabled="syncing"
          @click="syncInbox"
        >
          <span
            :class="
              syncing ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-refresh-cw'
            "
            class="size-3.5"
          />
          {{
            syncing
              ? t('JABVOX_WA_TEMPLATES.INBOX.SYNCING')
              : t('JABVOX_WA_TEMPLATES.INBOX.SYNC')
          }}
        </button>
      </div>

      <!-- Table -->
      <div class="flex-1 overflow-auto px-6 py-3">
        <div
          v-if="loadingTemplates"
          class="py-16 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_WA_TEMPLATES.LOADING') }}
        </div>
        <div
          v-else-if="!templates.length"
          class="py-16 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_WA_TEMPLATES.EMPTY') }}
        </div>
        <table v-else class="w-full text-sm">
          <thead>
            <tr class="text-left border-b border-n-weak">
              <th class="py-2 pr-3 text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.TABLE.NAME') }}
              </th>
              <th class="py-2 pr-3 text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.TABLE.META_ID') }}
              </th>
              <th
                v-if="!selectedInboxId"
                class="py-2 pr-3 text-xs font-medium text-n-slate-10"
              >
                {{ t('JABVOX_WA_TEMPLATES.TABLE.INBOX') }}
              </th>
              <th class="py-2 pr-3 text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.TABLE.LANGUAGE') }}
              </th>
              <th class="py-2 pr-3 text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.TABLE.CATEGORY') }}
              </th>
              <th class="py-2 pr-3 text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.TABLE.STATUS') }}
              </th>
              <th class="py-2 pr-3 text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.TABLE.QUALITY') }}
              </th>
              <th class="py-2 pr-3 text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_WA_TEMPLATES.TABLE.UPDATED') }}
              </th>
              <th class="py-2 text-xs font-medium text-n-slate-10" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="tpl in templates"
              :key="tpl.id"
              class="border-b border-n-weak hover:bg-n-alpha-1 cursor-pointer"
              @click="openDetail(tpl)"
            >
              <td class="py-2.5 pr-3">
                <span class="font-medium text-n-slate-12">{{ tpl.name }}</span>
                <p
                  v-if="tpl.body_content"
                  class="text-xs text-n-slate-10 truncate max-w-xs"
                >
                  {{ tpl.body_content }}
                </p>
              </td>
              <td class="py-2.5 pr-3 text-xs text-n-slate-10 font-mono">
                {{ tpl.meta_template_id || '—' }}
              </td>
              <td
                v-if="!selectedInboxId"
                class="py-2.5 pr-3 text-xs text-n-slate-11"
              >
                {{ tpl.inbox_name }}
              </td>
              <td class="py-2.5 pr-3 text-xs text-n-slate-11">
                {{ tpl.language }}
              </td>
              <td class="py-2.5 pr-3 text-xs text-n-slate-11">
                {{ t(`JABVOX_WA_TEMPLATES.CATEGORIES.${tpl.category}`) }}
              </td>
              <td class="py-2.5 pr-3">
                <span
                  class="inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-full"
                  :class="statusClass(tpl.status)"
                >
                  {{ t(`JABVOX_WA_TEMPLATES.STATUS.${tpl.status}`) }}
                </span>
              </td>
              <td class="py-2.5 pr-3">
                <span
                  class="flex items-center gap-1 text-xs"
                  :class="qualityClass(tpl.quality_score)"
                >
                  <span
                    :class="qualityIcon(tpl.quality_score)"
                    class="size-3.5"
                  />
                  {{
                    t(
                      `JABVOX_WA_TEMPLATES.QUALITY.${tpl.quality_score || 'UNKNOWN'}`
                    )
                  }}
                </span>
              </td>
              <td class="py-2.5 pr-3 text-xs text-n-slate-10">
                {{ new Date(tpl.updated_at).toLocaleDateString() }}
              </td>
              <td class="py-2.5" @click.stop>
                <div class="flex items-center gap-1">
                  <button
                    v-tooltip="t('JABVOX_WA_TEMPLATES.ACTIONS.EDIT')"
                    class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
                    @click="openEdit(tpl)"
                  >
                    <span class="i-lucide-pencil size-3.5" />
                  </button>
                  <button
                    v-tooltip="t('JABVOX_WA_TEMPLATES.ACTIONS.DUPLICATE')"
                    class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
                    @click="duplicateTemplate(tpl)"
                  >
                    <span class="i-lucide-copy size-3.5" />
                  </button>
                  <button
                    v-tooltip="t('JABVOX_WA_TEMPLATES.ACTIONS.SYNC')"
                    class="p-1.5 rounded hover:bg-n-alpha-2 text-n-slate-11"
                    @click="syncTemplate(tpl)"
                  >
                    <span class="i-lucide-refresh-cw size-3.5" />
                  </button>
                  <button
                    v-tooltip="t('JABVOX_WA_TEMPLATES.ACTIONS.DELETE')"
                    class="p-1.5 rounded hover:bg-n-alpha-2 text-n-ruby-11"
                    @click="deleteTemplate(tpl)"
                  >
                    <span class="i-lucide-trash-2 size-3.5" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>

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
        class="relative ml-auto w-full max-w-4xl h-full bg-n-surface-1 shadow-xl flex overflow-hidden"
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
          <div class="flex-1 overflow-auto p-5 space-y-5">
            <section class="space-y-3">
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
            <section class="space-y-3">
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
            <section class="space-y-2">
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
          </div>
          <div class="flex gap-3 px-5 py-3.5 border-t border-n-weak shrink-0">
            <button
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
          class="w-72 border-l border-n-weak bg-n-alpha-1 flex flex-col overflow-hidden shrink-0"
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
        class="relative w-full max-w-2xl h-full bg-n-surface-1 shadow-2xl flex flex-col overflow-hidden"
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
