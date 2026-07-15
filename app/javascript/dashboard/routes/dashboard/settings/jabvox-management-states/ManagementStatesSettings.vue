<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { managementStatesAPI } from 'dashboard/api/jabvox/managementStates';
import Button from 'dashboard/components-next/button/Button.vue';
import StateListPanel from './components/StateListPanel.vue';
import ManagementStateDrawer from './components/ManagementStateDrawer.vue';
import SimpleStateDrawer from './components/SimpleStateDrawer.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';
import { DESTROY_KEY } from 'dashboard/helper/jabvox/nestedAttributes';
import { stateGroups } from 'dashboard/composables/jabvox/useManagementState';

const store = useStore();
const { t } = useI18n();

// ─── store ───
const states = useMapGetter('jabvoxManagementStates/getStates');
const uiFlags = useMapGetter('jabvoxManagementStates/getUIFlags');
const appStates = useMapGetter('jabvoxAppStates/getStates');
const appUiFlags = useMapGetter('jabvoxAppStates/getUIFlags');
const campaigns = useMapGetter('jabvoxCampaigns/getCampaigns');
const campaignsUiFlags = useMapGetter('jabvoxCampaigns/getUIFlags');
// Contact custom attributes, used to offer lead-field autofill mappings.
const contactAttributes = useMapGetter('attributes/getContactAttributes');

// Fields a management question can autofill from. Base contact fields are
// fixed; custom attributes come from the account's contact attribute defs.
// The value is a namespaced key the backend whitelists and the typification
// form resolves against the live lead/contact.
const BASE_LEAD_FIELDS = [
  { value: 'contact.name', label: 'Contacto: Nombre' },
  { value: 'contact.email', label: 'Contacto: Email' },
  { value: 'contact.phone_number', label: 'Contacto: Teléfono' },
  { value: 'contact.identifier', label: 'Contacto: Identificador' },
  { value: 'contact.country_code', label: 'Contacto: País (código)' },
  { value: 'contact.additional.country', label: 'Contacto: País' },
  {
    value: 'contact.additional.jabvox_identification_number',
    label: 'Contacto: Documento',
  },
  { value: 'lead.lead_number', label: 'Lead: Número' },
  { value: 'lead.campaign', label: 'Lead: Campaña' },
  { value: 'lead.affiliate_name', label: 'Lead: Afiliado' },
];

const leadFieldOptions = computed(() => [
  ...BASE_LEAD_FIELDS,
  ...(contactAttributes.value || []).map(attr => ({
    value: `contact.custom.${attr.attributeKey}`,
    label: `Atributo: ${attr.attributeDisplayName || attr.attributeKey}`,
  })),
]);

// ─── tabs ───
const activeTab = ref('management');
const tabs = [
  {
    key: 'management',
    label: () => t('JABVOX_MANAGEMENT_STATES.TABS.MANAGEMENT'),
    icon: 'i-lucide-workflow',
  },
  {
    key: 'app',
    label: () => t('JABVOX_MANAGEMENT_STATES.TABS.APP'),
    icon: 'i-lucide-smartphone',
  },
  {
    key: 'campaigns',
    label: () => t('JABVOX_MANAGEMENT_STATES.TABS.CAMPAIGNS'),
    icon: 'i-lucide-megaphone',
  },
];

const totalForActiveTab = computed(() => {
  if (activeTab.value === 'management') return states.value.length;
  if (activeTab.value === 'app') return appStates.value.length;
  return campaigns.value.length;
});

// ─── refs to drawers + dialog ───
const mgmtDrawer = ref(null);
const appDrawer = ref(null);
const campaignDrawer = ref(null);
const deleteDialog = ref(null);
const pendingDelete = ref(null);

const onCreate = () => {
  if (activeTab.value === 'management') mgmtDrawer.value?.openNew();
  else if (activeTab.value === 'app') appDrawer.value?.openNew();
  else campaignDrawer.value?.openNew();
};

// ─── management states ───
// Existing (non-empty) group names offered as suggestions in the drawer.
const existingGroups = computed(() =>
  stateGroups(states.value).filter(Boolean)
);

// Strip empty/incomplete rules before sending; an empty ruleset means the
// question is always visible ({}), matching the backend contract.
const normalizeVisibility = raw => {
  const rules = (raw?.rules || [])
    .map(r => ({
      question: (r.question || '').trim(),
      operator: r.operator || 'equals',
      value: r.operator === 'answered' ? undefined : (r.value ?? '').toString(),
    }))
    .filter(r => r.question);
  if (!rules.length) return {};
  return { logic: raw?.logic === 'or' ? 'or' : 'and', rules };
};

const buildManagementPayload = (form, index) => ({
  name_jabvox: form.name_jabvox,
  state_group_jabvox: form.state_group_jabvox || '',
  usage_info_jabvox: form.usage_info_jabvox || '',
  color_jabvox: form.color_jabvox,
  is_active_jabvox: form.is_active_jabvox,
  note_mode: form.note_mode,
  managed_jabvox: form.managed_jabvox !== false,
  contact_jabvox: form.contact_jabvox === true,
  effective_contact_jabvox: form.effective_contact_jabvox === true,
  advisory_jabvox: form.advisory_jabvox === true,
  service_type_jabvox: form.service_type_jabvox || 'No',
  positivity_level_jabvox: Math.min(
    100,
    Math.max(0, Number(form.positivity_level_jabvox) || 0)
  ),
  position: index,
  questions_attributes: form.questions.map((q, i) => {
    const attrs = {
      label: q.label,
      question_type: q.question_type,
      required: q.required,
      options: q.options || [],
      visibility: normalizeVisibility(q.visibility),
      lead_field: q.lead_field || '',
      lead_field_locked: q.lead_field_locked === true,
      position: i,
    };
    if (q.id) attrs.id = q.id;
    if (q[DESTROY_KEY]) attrs[DESTROY_KEY] = true;
    return attrs;
  }),
});

const onSubmitManagement = async ({ id, form }) => {
  try {
    const found = id ? states.value.findIndex(s => s.id === id) : -1;
    const index = found >= 0 ? found : states.value.length;
    const payload = buildManagementPayload(form, index);
    if (id) {
      await store.dispatch('jabvoxManagementStates/updateState', {
        id,
        ...payload,
      });
      useAlert(t('JABVOX_MANAGEMENT_STATES.UPDATED'));
    } else {
      await store.dispatch('jabvoxManagementStates/createState', payload);
      useAlert(t('JABVOX_MANAGEMENT_STATES.CREATED'));
    }
    mgmtDrawer.value?.close();
  } catch {
    useAlert(t('JABVOX_MANAGEMENT_STATES.ERROR'));
  }
};

// ─── app states ───
const onSubmitApp = async ({ id, form }) => {
  try {
    if (id) {
      await store.dispatch('jabvoxAppStates/updateState', { id, ...form });
      useAlert(t('JABVOX_MANAGEMENT_STATES.APP_STATES.UPDATED'));
    } else {
      await store.dispatch('jabvoxAppStates/createState', form);
      useAlert(t('JABVOX_MANAGEMENT_STATES.APP_STATES.CREATED'));
    }
    appDrawer.value?.close();
  } catch {
    useAlert(t('JABVOX_MANAGEMENT_STATES.APP_STATES.ERROR'));
  }
};

// ─── campaigns ───
const onSubmitCampaign = async ({ id, form }) => {
  try {
    if (id) {
      await store.dispatch('jabvoxCampaigns/updateCampaign', { id, ...form });
      useAlert(t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.UPDATED'));
    } else {
      await store.dispatch('jabvoxCampaigns/createCampaign', form);
      useAlert(t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.CREATED'));
    }
    campaignDrawer.value?.close();
  } catch {
    useAlert(t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.ERROR'));
  }
};

// ─── delete (shared dialog) ───
const askDelete = (item, kind) => {
  const name = item.name_jabvox ?? item.name ?? '';
  pendingDelete.value = { id: item.id, kind };
  deleteDialog.value?.open({
    title: t('JABVOX_MANAGEMENT_STATES.DELETE.TITLE'),
    description: t('JABVOX_MANAGEMENT_STATES.DELETE.BODY', { name }),
    data: item.id,
  });
};

const doDelete = async () => {
  const pending = pendingDelete.value;
  if (!pending) return;
  try {
    if (pending.kind === 'management') {
      await store.dispatch('jabvoxManagementStates/deleteState', pending.id);
      useAlert(t('JABVOX_MANAGEMENT_STATES.DELETED'));
    } else if (pending.kind === 'app') {
      await store.dispatch('jabvoxAppStates/deleteState', pending.id);
      useAlert(t('JABVOX_MANAGEMENT_STATES.APP_STATES.DELETED'));
    } else {
      await store.dispatch('jabvoxCampaigns/deleteCampaign', pending.id);
      useAlert(t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.DELETED'));
    }
  } catch {
    useAlert(t('JABVOX_MANAGEMENT_STATES.ERROR'));
  } finally {
    pendingDelete.value = null;
  }
};

// ─── JSON export / import (management states only) ───
// Security model: the file is DATA only. It's parsed with JSON.parse (which
// never executes code), size/type-checked here, and the backend re-validates
// every field against a strict whitelist before touching the DB.
const MAX_IMPORT_BYTES = 2 * 1024 * 1024; // 2 MB
const importInput = ref(null);
const importing = ref(false);

const onExport = async () => {
  try {
    const { data } = await managementStatesAPI.export();
    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    const stamp = new Date().toISOString().slice(0, 10);
    link.href = url;
    link.download = `jabvox-estados-gestion-${stamp}.json`;
    link.click();
    URL.revokeObjectURL(url);
  } catch {
    useAlert(t('JABVOX_MANAGEMENT_STATES.ERROR'));
  }
};

const onImportClick = () => importInput.value?.click();

const onImportFile = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file) return;
  if (file.size > MAX_IMPORT_BYTES) {
    useAlert(t('JABVOX_MANAGEMENT_STATES.IMPORT.TOO_BIG'));
    return;
  }

  let parsed;
  try {
    parsed = JSON.parse(await file.text());
  } catch {
    useAlert(t('JABVOX_MANAGEMENT_STATES.IMPORT.INVALID_JSON'));
    return;
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    useAlert(t('JABVOX_MANAGEMENT_STATES.IMPORT.INVALID_JSON'));
    return;
  }

  importing.value = true;
  try {
    const { data } = await managementStatesAPI.import(parsed);
    useAlert(
      t('JABVOX_MANAGEMENT_STATES.IMPORT.SUCCESS', {
        created: data.created,
        updated: data.updated,
      })
    );
    store.dispatch('jabvoxManagementStates/fetchStates');
  } catch (error) {
    const serverErrors = error?.response?.data?.errors;
    useAlert(
      Array.isArray(serverErrors) && serverErrors.length
        ? serverErrors.slice(0, 3).join(' · ')
        : t('JABVOX_MANAGEMENT_STATES.IMPORT.ERROR')
    );
  } finally {
    importing.value = false;
  }
};

onMounted(() => {
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('jabvoxAppStates/fetchStates');
  store.dispatch('jabvoxCampaigns/fetchCampaigns');
  // Load contact custom attributes so they can be mapped as autofill sources.
  store.dispatch('attributes/get', 'contact_attribute');
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
            class="i-lucide-workflow size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_MANAGEMENT_STATES.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_MANAGEMENT_STATES.HEADER_DESCRIPTION') }}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span
            class="hidden sm:inline-flex items-center rounded-full bg-n-alpha-2 px-2.5 py-1 text-xs font-medium text-n-slate-11"
          >
            {{
              t('JABVOX_MANAGEMENT_STATES.COUNT', { count: totalForActiveTab })
            }}
          </span>
          <template v-if="activeTab === 'management'">
            <Button
              :label="t('JABVOX_MANAGEMENT_STATES.IMPORT.BUTTON')"
              icon="i-lucide-upload"
              slate
              :is-loading="importing"
              @click="onImportClick"
            />
            <Button
              :label="t('JABVOX_MANAGEMENT_STATES.EXPORT.BUTTON')"
              icon="i-lucide-download"
              slate
              @click="onExport"
            />
            <input
              ref="importInput"
              type="file"
              accept=".json,application/json"
              class="hidden"
              @change="onImportFile"
            />
          </template>
          <Button
            :label="t('JABVOX_MANAGEMENT_STATES.NEW')"
            icon="i-lucide-plus"
            @click="onCreate"
          />
        </div>
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

      <!-- Management tab -->
      <StateListPanel
        v-if="activeTab === 'management'"
        :items="states"
        :loading="uiFlags.isFetching"
        kind="management"
        name-field="name_jabvox"
        color-field="color_jabvox"
        active-field="is_active_jabvox"
        :description="t('JABVOX_MANAGEMENT_STATES.DESCRIPTION')"
        @create="mgmtDrawer?.openNew()"
        @edit="s => mgmtDrawer?.openEdit(s)"
        @delete="s => askDelete(s, 'management')"
      />

      <!-- App states tab -->
      <StateListPanel
        v-else-if="activeTab === 'app'"
        :items="appStates"
        :loading="appUiFlags.isFetching"
        kind="simple"
        name-field="name"
        color-field="color"
        active-field="is_active"
        :description="t('JABVOX_MANAGEMENT_STATES.APP_STATES.DESCRIPTION')"
        @create="appDrawer?.openNew()"
        @edit="s => appDrawer?.openEdit(s)"
        @delete="s => askDelete(s, 'app')"
      />

      <!-- Campaigns tab -->
      <StateListPanel
        v-else
        :items="campaigns"
        :loading="campaignsUiFlags.isFetching"
        kind="simple"
        name-field="name_jabvox"
        :with-color="false"
        :with-active="false"
        :description="t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.DESCRIPTION')"
        @create="campaignDrawer?.openNew()"
        @edit="c => campaignDrawer?.openEdit(c)"
        @delete="c => askDelete(c, 'campaigns')"
      />
    </div>

    <!-- Drawers -->
    <ManagementStateDrawer
      ref="mgmtDrawer"
      :is-saving="uiFlags.isCreating || uiFlags.isUpdating"
      :group-suggestions="existingGroups"
      :lead-field-options="leadFieldOptions"
      @submit="onSubmitManagement"
    />
    <SimpleStateDrawer
      ref="appDrawer"
      :is-saving="appUiFlags.isSaving"
      name-field="name"
      color-field="color"
      active-field="is_active"
      :new-label="t('JABVOX_MANAGEMENT_STATES.APP_STATES.NEW')"
      :edit-label="t('JABVOX_MANAGEMENT_STATES.APP_STATES.EDIT')"
      @submit="onSubmitApp"
    />
    <SimpleStateDrawer
      ref="campaignDrawer"
      :is-saving="campaignsUiFlags.isSaving"
      name-field="name_jabvox"
      :with-color="false"
      :with-active="false"
      :new-label="t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.NEW')"
      :edit-label="t('JABVOX_MANAGEMENT_STATES.CAMPAIGNS.EDIT')"
      @submit="onSubmitCampaign"
    />

    <ConfirmDialog ref="deleteDialog" @confirm="doDelete" />
  </div>
</template>
