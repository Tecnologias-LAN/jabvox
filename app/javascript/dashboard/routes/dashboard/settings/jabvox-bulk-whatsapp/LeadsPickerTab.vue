<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import leadsAPI from 'dashboard/api/jabvox/leads';
import bulkWhatsappAPI from 'dashboard/api/jabvox/bulkWhatsapp';
import { processVariable } from 'dashboard/helper/templateHelper';
import TemplatePreview from './components/TemplatePreview.vue';
import TemplateExtraFields from './components/TemplateExtraFields.vue';

const props = defineProps({
  inboxId: { type: [Number, String], default: '' },
  senderUserId: { type: [Number, String], default: '' },
  // 'template' | 'text' | null — derived from the inbox by the parent.
  mode: { type: String, default: null },
  configReady: { type: Boolean, default: false },
  // Wizard step driven by the parent: 2 template, 3 audience, 4 variables, 5 preview.
  step: { type: Number, default: 2 },
  // "Reenviar a esta audiencia": respuesta de reuseBatch con los lead_ids ya
  // filtrados por estado + plantilla/idioma/variables del envío original. Cuando
  // llega, precarga la selección y el mensaje en vez de partir de cero.
  preselect: { type: Object, default: null },
});

const emit = defineEmits(['sent', 'validity', 'hasVariables']);

const { t } = useI18n();
const rootStore = useStore();

const PER_PAGE = 25;

// ── Filters ────────────────────────────────────────────────────────────────
// Mirrors every filter the leads list supports (Jabvox::LeadsFilterService).
const filters = ref({
  q: '',
  email: '',
  phone: '',
  document: '',
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

// EVERY custom field is a checkbox selector — no text-input fallback. Options
// come from the field definition plus the distinct values discovered in the
// leads; when a field's base list is truncated (discovery cap), the search box
// also queries the server so every value stays findable.
const optionSearch = ref({});
const remoteOptions = ref({}); // key => values fetched by server-side search
const searchTimers = {};

const onOptionSearch = cf => {
  if (!cf.truncated) return; // local list is complete; local filtering suffices
  clearTimeout(searchTimers[cf.key]);
  const q = (optionSearch.value[cf.key] || '').trim();
  if (!q) {
    remoteOptions.value[cf.key] = [];
    return;
  }
  searchTimers[cf.key] = setTimeout(async () => {
    try {
      const { data } = await bulkWhatsappAPI.searchFieldValues(cf.key, q);
      remoteOptions.value[cf.key] = data.values || [];
    } catch {
      remoteOptions.value[cf.key] = [];
    }
  }, 300);
};

// Sentinel entendido por el backend (LeadCustomFilter) como "campo vacío o sin
// valor". Se pinta como fila fija propia, nunca dentro de la lista de valores.
const EMPTY_VALUE = '__empty__';

// Local base options ∪ server search results ∪ already-selected values (so a
// checked value never disappears from the list), filtered by the search text.
const filteredOptions = cf => {
  const q = (optionSearch.value[cf.key] || '').trim().toLowerCase();
  const selected = Array.isArray(customValues.value[cf.key])
    ? customValues.value[cf.key]
    : [];
  const base = [
    ...new Set([
      ...(cf.options || []),
      ...(remoteOptions.value[cf.key] || []),
      ...selected,
    ]),
  ].filter(o => o !== EMPTY_VALUE);
  if (!q) return base;
  return base.filter(o => String(o).toLowerCase().includes(q));
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

// Batch de origen cuando la audiencia viene de "Reenviar a esta audiencia".
// Se manda al backend para registrar la trazabilidad del reenvío.
const sourceBatchId = ref(null);

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

// ── Template variables ({{n}}) → lead field mapping ─────────────────────────
// Which {{n}} placeholder must be filled for the chosen template. Each entry is
// mapped by the user to a lead field (or a fixed text) before the send.
const variableMap = ref({});

// Plantilla seleccionada completa (para la previa con media/header/footer/botones).
const selectedTemplate = computed(() =>
  inboxTemplates.value.find(tp => tp.name === templateName.value)
);

// Campos de los tipos de plantilla no estándar (código OTP, ubicación,
// carrusel, oferta, cupón). Fijos para toda la audiencia, igual que el media
// del header. Se descartan al cambiar de plantilla.
const templateExtras = ref({});
watch(templateName, () => {
  templateExtras.value = {};
});

// Tipo de header de la plantilla (para el resumen del paso 2).
const templateHeader = computed(() => {
  const comps = Array.isArray(selectedTemplate.value?.components)
    ? selectedTemplate.value.components
    : [];
  const h = comps.find(c => (c.type || '').toUpperCase() === 'HEADER');
  return h ? (h.format || 'TEXT').toUpperCase() : '';
});

// Media de EJEMPLO del header (image/video/document) que Meta guarda en la
// plantilla aprobada — mismo criterio que csvHeaderMedia en BulkWhatsappSettings.
const templateHeaderMedia = computed(() => {
  const fmt = templateHeader.value;
  if (!['IMAGE', 'VIDEO', 'DOCUMENT'].includes(fmt)) return null;

  const comps = Array.isArray(selectedTemplate.value?.components)
    ? selectedTemplate.value.components
    : [];
  const h = comps.find(c => (c.type || '').toUpperCase() === 'HEADER');
  const ex = h?.example || {};
  const handle = ex.header_handle || ex.header_url || ex.header_handle_url;
  const url = Array.isArray(handle) ? handle[0] || '' : handle || '';
  if (!url) return null;

  return { media_url: url, media_type: fmt.toLowerCase() };
});

// Botón FLOW de la plantilla (si tiene uno): { index, flow_id }. Meta exige el
// componente button/flow siempre que la plantilla lo tenga.
const templateFlowButton = computed(() => {
  const comps = Array.isArray(selectedTemplate.value?.components)
    ? selectedTemplate.value.components
    : [];
  const buttonsComponent = comps.find(
    c => (c.type || '').toUpperCase() === 'BUTTONS'
  );
  if (!buttonsComponent?.buttons) return null;

  const index = buttonsComponent.buttons.findIndex(
    b => (b.type || '').toUpperCase() === 'FLOW'
  );
  if (index === -1) return null;

  const flowId = buttonsComponent.buttons[index].flow_id;
  if (!flowId) return null;

  return { index, flow_id: flowId };
});

// Body text of the currently selected template.
const selectedTemplateBody = computed(() => {
  const tpl = inboxTemplates.value.find(tp => tp.name === templateName.value);
  if (!tpl) return '';
  const comps = Array.isArray(tpl.components) ? tpl.components : [];
  const body = comps.find(c => (c.type || '').toUpperCase() === 'BODY');
  return body?.text || '';
});

// Variables del cuerpo de la plantilla. Soporta posicional ({{1}}) y NAMED
// ({{var1}}, {{nombre}}), con el MISMO criterio que el editor oficial (processVariable).
const templateVariables = computed(() => {
  const found = selectedTemplateBody.value.match(/\{\{([^}]+)\}\}/g) || [];
  const keys = found.map(v => processVariable(v));
  return [...new Set(keys)];
});

// Options offered for each variable: default lead fields + every custom field.
const variableFieldOptions = computed(() => {
  const base = [
    { value: 'nombre', label: t('JABVOX_BULK_WA.VARS.FIELD_NAME') },
    { value: 'telefono', label: t('JABVOX_BULK_WA.VARS.FIELD_PHONE') },
    { value: 'email', label: t('JABVOX_BULK_WA.VARS.FIELD_EMAIL') },
    { value: 'country', label: t('JABVOX_BULK_WA.VARS.FIELD_COUNTRY') },
    { value: 'campaign', label: t('JABVOX_BULK_WA.VARS.FIELD_CAMPAIGN') },
    { value: 'afiliado', label: t('JABVOX_BULK_WA.VARS.FIELD_AFFILIATE') },
    { value: 'assignee_name', label: t('JABVOX_BULK_WA.VARS.FIELD_ASSIGNEE') },
  ];
  const custom = (customFields.value || []).map(cf => ({
    value: `custom:${cf.key}`,
    label: cf.label || cf.key,
  }));
  return [...base, ...custom];
});

// Valores de ejemplo para la previa: cada {{n}} se muestra con la ETIQUETA del campo
// del lead al que se mapeó (p.ej. «Nombre»), ya que no hay un lead concreto elegido.
const previewSampleValues = computed(() => {
  const out = {};
  templateVariables.value.forEach(n => {
    const opt = variableFieldOptions.value.find(
      o => o.value === variableMap.value[n]
    );
    if (opt) out[String(n)] = `«${opt.label}»`;
  });
  return out;
});

// Reset the mapping whenever the set of variables changes (new template).
watch(templateVariables, vars => {
  const next = {};
  vars.forEach(n => {
    next[n] = variableMap.value[n] || '';
  });
  variableMap.value = next;
});

// Every {{n}} must be mapped to a field before sending.
const allVariablesMapped = computed(() =>
  templateVariables.value.every(n => !!variableMap.value[n])
);

// Renders the placeholder label (e.g. "{{1}}") without confusing the template parser.
const varLabel = n => `{{${n}}}`;

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
    !!props.inboxId &&
    !!props.senderUserId &&
    !!props.mode &&
    selectedCount.value > 0 &&
    (props.mode === 'template'
      ? !!templateName.value && !!language.value && allVariablesMapped.value
      : !!text.value.trim())
);

// 5 pasos: 2 plantilla · 3 audiencia · 4 variables · 5 previa.
// Paso 2 (plantilla): plantilla+idioma elegidos, o texto (modo text). Las variables
// se validan aparte en el paso 4.
const templateChosen = computed(() =>
  props.mode === 'template'
    ? !!templateName.value && !!language.value
    : !!text.value.trim()
);
const audienceValid = computed(() => selectedCount.value > 0);
// Paso 4 (variables): cada {{n}} mapeada. Si la plantilla no tiene variables, es válido.
const variablesValid = computed(
  () => props.mode !== 'template' || allVariablesMapped.value
);
// ¿La plantilla elegida tiene variables? (el padre lo usa para saltar el paso 4).
const hasVariables = computed(
  () => props.mode === 'template' && templateVariables.value.length > 0
);

// Preview of what will be sent (step 4): the template + how each variable maps
// to a lead field, or the plain text. No real send — display only.
const previewLines = computed(() => {
  if (props.mode === 'template') {
    return templateVariables.value.map(n => ({
      var: varLabel(n),
      field:
        variableFieldOptions.value.find(o => o.value === variableMap.value[n])
          ?.label || '—',
    }));
  }
  return [];
});

// Tell the parent whether the current step lets "Next"/"Send" proceed.
// 5 pasos: 2 = plantilla · 3 = audiencia · 4 = variables · 5 = previa/enviar.
const stepValidity = () => {
  if (props.step === 2) return templateChosen.value;
  if (props.step === 3) return audienceValid.value;
  if (props.step === 4) return variablesValid.value;
  return canSend.value; // step 5
};
watch(
  [
    () => props.step,
    audienceValid,
    templateChosen,
    variablesValid,
    canSend,
    hasVariables,
  ],
  () => {
    emit('validity', stepValidity());
    emit('hasVariables', hasVariables.value);
  },
  { immediate: true }
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
  sourceBatchId.value = null;
};

// Precarga la audiencia y el mensaje desde la respuesta de reuseBatch: fija la
// selección a los lead_ids devueltos (nunca "todos"), y copia plantilla/idioma/
// variables del envío original para que el usuario solo confirme.
const applyPreselect = data => {
  if (!data) return;
  selectAll.value = false;
  excludedIds.value = new Set();
  selectedIds.value = new Set(data.lead_ids || []);
  sourceBatchId.value = data.source_batch_id ?? null;
  if (data.template_name) templateName.value = data.template_name;
  if (data.language) language.value = data.language;
  if (data.variable_map && typeof data.variable_map === 'object') {
    variableMap.value = { ...data.variable_map };
  }
};

const onSend = async () => {
  if (!canSend.value) return;
  sending.value = true;
  try {
    await bulkWhatsappAPI.sendLeads({
      inboxId: props.inboxId,
      senderUserId: props.senderUserId,
      all: selectAll.value,
      leadIds: selectAll.value ? [] : [...selectedIds.value],
      excludedIds: selectAll.value ? [...excludedIds.value] : [],
      filters: activeFilters.value,
      templateName: props.mode === 'template' ? templateName.value : undefined,
      language: props.mode === 'template' ? language.value : undefined,
      text: props.mode === 'text' ? text.value : undefined,
      variableMap:
        props.mode === 'template' && templateVariables.value.length
          ? variableMap.value
          : undefined,
      sourceBatchId: sourceBatchId.value || undefined,
      headerMedia:
        props.mode === 'template' ? templateHeaderMedia.value : undefined,
      flowButton:
        props.mode === 'template' ? templateFlowButton.value : undefined,
      extras: props.mode === 'template' ? templateExtras.value : undefined,
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

// Exposed so the parent wizard's step-4 Send button can trigger the leads send.
defineExpose({ send: () => onSend() });

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

// Cuando el padre entrega una audiencia a reenviar, precárgala. Registrado tras
// el watcher de inboxId para ganarle: el padre fija bandeja y preselect en el
// mismo tick, y no queremos que el reset de plantilla/idioma pise el preselect.
watch(
  () => props.preselect,
  data => applyPreselect(data),
  { immediate: true }
);

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

    <!-- Filters (collapsible) — Paso 3: audiencia -->
    <section
      v-show="step === 3"
      class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
    >
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
              {{ t('JABVOX_BULK_WA.LEADS.FILTER_DOCUMENT') }}
            </label>
            <input
              v-model="filters.document"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="t('JABVOX_BULK_WA.LEADS.FILTER_DOCUMENT')"
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

            <!-- TODOS los campos son seleccionables (uno o varios valores) -->
            <details class="group rounded-lg border border-n-weak bg-n-alpha-1">
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
                <!-- Buscador interno: filtra localmente y, en campos truncados
                     (lista base al tope), también consulta al servidor -->
                <!-- Búsqueda siempre visible al abrir el selector -->
                <div class="p-2">
                  <input
                    v-model="optionSearch[cf.key]"
                    type="search"
                    :placeholder="t('JABVOX_BULK_WA.LEADS.SEARCH_OPTION')"
                    class="reset-base w-full text-sm rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5"
                    @click.stop
                    @input="onOptionSearch(cf)"
                  />
                </div>
                <div
                  class="max-h-40 overflow-y-auto px-3 pb-2 flex flex-col gap-1.5"
                >
                  <!-- Opción fija: leads con el campo vacío / sin valor -->
                  <label
                    class="flex items-center gap-2 text-sm text-n-slate-11 italic cursor-pointer"
                  >
                    <input
                      type="checkbox"
                      class="rounded accent-n-brand shrink-0"
                      :checked="
                        (customValues[cf.key] || []).includes(EMPTY_VALUE)
                      "
                      @change="toggleCustomOption(cf.key, EMPTY_VALUE)"
                    />
                    <span class="truncate">
                      {{ t('JABVOX_BULK_WA.LEADS.FILTER_EMPTY') }}
                    </span>
                  </label>
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
          </div>
        </div>
      </div>
    </section>

    <!-- Aviso: audiencia precargada desde "Reenviar a esta audiencia" -->
    <div
      v-if="preselect && step === 3"
      class="flex items-center gap-2 rounded-xl border border-n-teal-6 bg-n-teal-3 px-4 py-2.5 text-sm text-n-teal-12"
    >
      <span
        class="i-lucide-repeat size-4 text-n-teal-11 shrink-0"
        aria-hidden="true"
      />
      {{
        t('JABVOX_BULK_WA.LEADS.PRESELECTED', {
          count: preselect.lead_count ?? selectedCount,
        })
      }}
    </div>

    <!-- Selection summary -->
    <div
      v-show="step === 3"
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
    <div
      v-show="step === 3"
      class="overflow-x-auto rounded-2xl border border-n-weak bg-n-solid-1"
    >
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
      v-if="step === 3 && totalPages > 1"
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

    <!-- Message body — Paso 2: plantilla + variables / texto -->
    <section
      v-show="step === 2"
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

        <!-- Resumen de la plantilla: idioma · header · nº de variables -->
        <div v-if="selectedTemplate" class="flex flex-wrap items-center gap-2">
          <span
            v-if="templateHeader"
            class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] font-medium text-n-slate-11"
          >
            <span
              :class="{
                'i-lucide-image': templateHeader === 'IMAGE',
                'i-lucide-video': templateHeader === 'VIDEO',
                'i-lucide-file-text': templateHeader === 'DOCUMENT',
                'i-lucide-heading': templateHeader === 'TEXT',
              }"
              class="size-3"
              aria-hidden="true"
            />
            {{ t(`JABVOX_BULK_WA.SEND.HEADER_${templateHeader}`) }}
          </span>
          <span
            class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium"
            :class="
              templateVariables.length
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-11'
            "
          >
            <span class="i-lucide-braces size-3" aria-hidden="true" />
            {{ t('JABVOX_BULK_WA.SEND.VARS_COUNT', templateVariables.length) }}
          </span>
        </div>

        <!-- Campos que exigen los tipos de plantilla no estándar (código OTP,
             ubicación, carrusel, oferta, cupón). Se auto-oculta si la plantilla
             elegida no necesita ninguno. -->
        <TemplateExtraFields
          v-if="selectedTemplate"
          v-model="templateExtras"
          :template="selectedTemplate"
          class="mt-3"
        />
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

    <!-- Variables — Paso 4: mapear cada {{n}} a un campo del lead -->
    <section
      v-show="step === 4 && mode === 'template' && templateVariables.length"
      class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm space-y-3"
    >
      <div class="flex flex-col gap-0.5">
        <label class="text-xs font-medium text-n-slate-12">
          {{ t('JABVOX_BULK_WA.VARS.TITLE') }}
        </label>
        <span class="text-[11px] text-n-slate-9">
          {{ t('JABVOX_BULK_WA.VARS.HELP') }}
        </span>
      </div>
      <div
        v-for="n in templateVariables"
        :key="`var-${n}`"
        class="flex items-center gap-2"
      >
        <span
          class="shrink-0 text-xs font-mono rounded-md bg-n-alpha-2 px-2 py-1.5 text-n-slate-12"
        >
          {{ varLabel(n) }}
        </span>
        <select
          v-model="variableMap[n]"
          class="reset-base flex-1 text-sm rounded-lg border px-3 py-2 bg-n-alpha-1"
          :class="variableMap[n] ? 'border-n-weak' : 'border-n-ruby-6'"
        >
          <option value="">
            {{ t('JABVOX_BULK_WA.VARS.PLACEHOLDER') }}
          </option>
          <option
            v-for="opt in variableFieldOptions"
            :key="opt.value"
            :value="opt.value"
          >
            {{ opt.label }}
          </option>
        </select>
      </div>
      <span v-if="!allVariablesMapped" class="text-[11px] text-n-ruby-9">
        {{ t('JABVOX_BULK_WA.VARS.INCOMPLETE') }}
      </span>
    </section>

    <!-- Preview — Paso 5: previsualización (no envía) -->
    <section
      v-show="step === 5"
      class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm space-y-3"
    >
      <p class="text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_BULK_WA.PREVIEW.TITLE') }}
      </p>
      <ul class="text-sm text-n-slate-11 space-y-1">
        <li>
          {{ t('JABVOX_BULK_WA.PREVIEW.RECIPIENTS', { count: selectedCount }) }}
        </li>
        <li v-if="mode === 'template'">
          {{
            t('JABVOX_BULK_WA.PREVIEW.TEMPLATE', {
              name: templateName,
              lang: language,
            })
          }}
        </li>
      </ul>
      <!-- Previa real de la plantilla (header con media, cuerpo, footer, botones) -->
      <TemplatePreview
        v-if="mode === 'template' && selectedTemplate"
        :template="selectedTemplate"
        :sample-values="previewSampleValues"
      />
      <div
        v-if="mode === 'template' && previewLines.length"
        class="rounded-lg bg-n-alpha-1 p-3 space-y-1"
      >
        <p class="text-[11px] text-n-slate-9">
          {{ t('JABVOX_BULK_WA.PREVIEW.VARS') }}
        </p>
        <div
          v-for="(line, idx) in previewLines"
          :key="`prev-${idx}`"
          class="flex items-center gap-2 text-xs"
        >
          <span class="font-mono rounded bg-n-alpha-2 px-1.5 py-0.5">{{
            line.var
          }}</span>
          <span class="i-lucide-arrow-right size-3" aria-hidden="true" />
          <span class="text-n-slate-12">{{ line.field }}</span>
        </div>
      </div>
      <div v-else-if="mode === 'text'" class="rounded-lg bg-n-alpha-1 p-3">
        <p class="text-sm text-n-slate-12 whitespace-pre-wrap">{{ text }}</p>
      </div>
    </section>
  </div>
</template>
