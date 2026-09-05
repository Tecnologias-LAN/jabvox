<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import allCountries from 'shared/constants/countries.js';
import voiceBroadcastAPI from 'dashboard/api/jabvox/voiceBroadcast';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import FieldLabel from './FieldLabel.vue';

// Crear/editar una campaña de voz. Módulo INDEPENDIENTE del marcador: filtra los leads
// de la cuenta con su set completo de filtros (nombre, correo, teléfono, documento, país,
// estado de gestión, afiliado, bandeja y campos personalizados). El conteo/preview usan
// los endpoints PROPIOS del Voice Broadcast (misma fuente de verdad, LeadsFilterService
// del VB), así funcionan en vivo al crear sin necesidad de guardar antes.
const emit = defineEmits(['saved']);
const { t } = useI18n();
const store = useStore();

const show = ref(false);
const saving = ref(false);
const editingId = ref(null);

const HOUR_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
// Sentinel entendido por el backend (LeadCustomFilter) como "campo vacío/sin valor".
const EMPTY_VALUE = '__empty__';

const emptyForm = () => ({
  name_jabvox: '',
  caller_id_jabvox: '',
  max_concurrent_jabvox: 5,
  cps_jabvox: 1,
  max_retries_jabvox: 0,
  retry_interval_jabvox: 300,
  amd_enabled_jabvox: true,
  dtmf_enabled_jabvox: false,
  dtmf_optout_digit_jabvox: '9',
  calling_hours_start_jabvox: '',
  calling_hours_end_jabvox: '',
  // Filtros de leads — set completo, propio del módulo.
  countries_jabvox: [],
  management_state_ids_jabvox: [],
  affiliate_ids_jabvox: [],
  inbox_ids_jabvox: [],
  excluded_lead_ids_jabvox: [],
  lead_filters_jabvox: {
    q: '',
    email: '',
    phone: '',
    document: '',
    custom: {},
  },
});
const form = ref(emptyForm());

// ── Catálogos de filtros (fuentes propias de la cuenta) ────────────────────
const managementStates = useMapGetter('jabvoxManagementStates/getStates');
const affiliates = useMapGetter('jabvoxAffiliates/getAffiliates');
const inboxes = useMapGetter('inboxes/getInboxes');
const countryOptions = computed(() =>
  allCountries.map(c => ({ value: c.name, label: c.name }))
);

// Definiciones de campos personalizados del lead (endpoint propio del VB).
const customColumns = ref([]);
const loadCustomColumns = async () => {
  try {
    const { data } = await voiceBroadcastAPI.leadFields();
    customColumns.value = data.custom || [];
  } catch (e) {
    customColumns.value = [];
  }
};

// Campos de identidad que se filtran como texto libre (tienen su propio input arriba);
// el resto de campos personalizados se filtran por selección de valores.
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
    .replace(/[̀-ͯ]/g, '')
    .replace(/(_c|_jabvox)$/, '');
const isTextOnlyField = col =>
  TEXT_ONLY_FIELDS.has(normalizeKey(col.key)) ||
  TEXT_ONLY_FIELDS.has(normalizeKey(col.label));

// Valores seleccionados de un campo personalizado (siempre array).
const selectedValues = key => {
  const v = form.value.lead_filters_jabvox.custom[key];
  return Array.isArray(v) ? v : [];
};
const toggleCustomOption = (key, option) => {
  const current = selectedValues(key);
  form.value.lead_filters_jabvox.custom[key] = current.includes(option)
    ? current.filter(o => o !== option)
    : [...current, option];
};

// Búsqueda por campo (para campos con muchos valores, consulta también al servidor).
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
      const { data } = await voiceBroadcastAPI.fieldValues(col.key, q);
      remoteOptions.value[col.key] = data.values || [];
    } catch (e) {
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
  ].filter(o => o !== EMPTY_VALUE);
  if (!q) return base;
  return base.filter(o => String(o).toLowerCase().includes(q));
};

// Toggle de país / bandeja (arrays de checkboxes).
const toggleArrayValue = (arr, value) => {
  const i = arr.indexOf(value);
  if (i >= 0) arr.splice(i, 1);
  else arr.push(value);
};

const isEditing = computed(() => editingId.value != null);

const hoursValid = computed(() => {
  const { calling_hours_start_jabvox: s, calling_hours_end_jabvox: e } =
    form.value;
  return (!s || HOUR_RE.test(s)) && (!e || HOUR_RE.test(e));
});

const canSubmit = computed(() => {
  const f = form.value;
  return (
    f.name_jabvox.trim() &&
    Number(f.max_concurrent_jabvox) > 0 &&
    Number(f.cps_jabvox) > 0 &&
    hoursValid.value &&
    !saving.value
  );
});

// ── Conteo + preview en vivo por payload (endpoints propios del VB) ────────
const leadCount = ref(null);
const loadingCount = ref(false);
let countTimer = null;

// Payload de filtros que comparten el conteo y el preview.
const filterParams = () => ({
  countries: form.value.countries_jabvox,
  management_state_ids: form.value.management_state_ids_jabvox,
  affiliate_ids: form.value.affiliate_ids_jabvox,
  inbox_ids: form.value.inbox_ids_jabvox,
  q: form.value.lead_filters_jabvox.q || undefined,
  email: form.value.lead_filters_jabvox.email || undefined,
  phone: form.value.lead_filters_jabvox.phone || undefined,
  document: form.value.lead_filters_jabvox.document || undefined,
  custom: form.value.lead_filters_jabvox.custom,
});

const fetchLeadCount = async () => {
  loadingCount.value = true;
  try {
    const { data } = await voiceBroadcastAPI.filterLeadCount({
      ...filterParams(),
      excluded_lead_ids: form.value.excluded_lead_ids_jabvox,
    });
    leadCount.value = data.count;
  } catch (e) {
    leadCount.value = null;
  } finally {
    loadingCount.value = false;
  }
};
// Campos personalizados SOLO seleccionables (excluye los de identidad, que ya tienen
// su propio input arriba). El usuario pidió que estos nunca sean de texto libre.
const selectableCustomColumns = computed(() =>
  customColumns.value.filter(col => !isTextOnlyField(col))
);

// ── Preview paginado de leads (lista + exclusión individual) ───────────────
const showPreview = ref(false);
const previewLeads = ref([]);
const previewTotal = ref(0);
const previewPage = ref(1);
const previewPerPage = ref(25);
const loadingPreview = ref(false);
const previewPages = computed(() =>
  Math.max(1, Math.ceil(previewTotal.value / previewPerPage.value))
);

const fetchPreviewLeads = async () => {
  loadingPreview.value = true;
  try {
    const { data } = await voiceBroadcastAPI.filterPreviewLeads({
      ...filterParams(),
      page: previewPage.value,
    });
    previewLeads.value = data.leads || [];
    previewTotal.value = data.total || 0;
    previewPerPage.value = data.per_page || 25;
  } catch (e) {
    previewLeads.value = [];
    previewTotal.value = 0;
  } finally {
    loadingPreview.value = false;
  }
};
const togglePreview = () => {
  showPreview.value = !showPreview.value;
  if (showPreview.value && !previewLeads.value.length) fetchPreviewLeads();
};
const goToPreviewPage = p => {
  if (p < 1 || p > previewPages.value) return;
  previewPage.value = p;
  fetchPreviewLeads();
};

// Exclusión individual (excluded_lead_ids): incluido = NO está en la lista de excluidos.
const leadIncluded = id => !form.value.excluded_lead_ids_jabvox.includes(id);
const toggleLead = id => {
  const arr = form.value.excluded_lead_ids_jabvox;
  const i = arr.indexOf(id);
  if (i >= 0) arr.splice(i, 1);
  else arr.push(id);
};
// Seleccionar todo = vaciar exclusiones.
const selectAllLeads = () => {
  form.value.excluded_lead_ids_jabvox = [];
};
// Deseleccionar todo = excluir todos los que matchean (IDs los da el backend).
const deselectAllLeads = async () => {
  try {
    const { data } = await voiceBroadcastAPI.matchingLeadIds(filterParams());
    form.value.excluded_lead_ids_jabvox = data.ids || [];
  } catch (e) {
    // sin cambios si falla
  }
};

const refreshLeadCount = () => {
  clearTimeout(countTimer);
  countTimer = setTimeout(() => {
    previewPage.value = 1;
    fetchLeadCount();
    if (showPreview.value) fetchPreviewLeads();
  }, 400);
};

// Recalcula el conteo/preview cuando cambia cualquier filtro.
watch(
  () => [
    form.value.countries_jabvox.length,
    form.value.management_state_ids_jabvox.length,
    form.value.affiliate_ids_jabvox.length,
    form.value.inbox_ids_jabvox.length,
    form.value.lead_filters_jabvox.q,
    form.value.lead_filters_jabvox.email,
    form.value.lead_filters_jabvox.phone,
    form.value.lead_filters_jabvox.document,
    JSON.stringify(form.value.lead_filters_jabvox.custom),
  ],
  refreshLeadCount
);

// Al cambiar exclusiones, solo refresca el conteo (la lista se queda para seguir marcando).
watch(() => form.value.excluded_lead_ids_jabvox.length, fetchLeadCount);

onMounted(() => {
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('jabvoxAffiliates/fetchAffiliates');
  store.dispatch('inboxes/get');
  loadCustomColumns();
});

const open = row => {
  editingId.value = row?.id ?? null;
  const lf = row?.lead_filters || {};
  form.value = {
    ...emptyForm(),
    name_jabvox: row?.name || '',
    caller_id_jabvox: row?.caller_id || '',
    max_concurrent_jabvox: row?.max_concurrent ?? 5,
    cps_jabvox: row?.cps ?? 1,
    max_retries_jabvox: row?.max_retries ?? 0,
    retry_interval_jabvox: row?.retry_interval ?? 300,
    amd_enabled_jabvox: row?.amd_enabled ?? true,
    dtmf_enabled_jabvox: row?.dtmf_enabled ?? false,
    dtmf_optout_digit_jabvox: row?.dtmf_optout_digit || '9',
    calling_hours_start_jabvox: row?.calling_hours_start || '',
    calling_hours_end_jabvox: row?.calling_hours_end || '',
    countries_jabvox: [...(row?.countries || [])],
    management_state_ids_jabvox: [...(row?.management_state_ids || [])],
    affiliate_ids_jabvox: [...(row?.affiliate_ids || [])],
    inbox_ids_jabvox: [...(row?.inbox_ids || [])],
    excluded_lead_ids_jabvox: [...(row?.excluded_lead_ids || [])],
    lead_filters_jabvox: {
      q: lf.q || '',
      email: lf.email || '',
      phone: lf.phone || '',
      document: lf.document || '',
      custom: { ...(lf.custom || {}) },
    },
  };
  optionSearch.value = {};
  remoteOptions.value = {};
  previewLeads.value = [];
  previewTotal.value = 0;
  previewPage.value = 1;
  showPreview.value = false;
  show.value = true;
  fetchLeadCount();
};

const close = () => {
  show.value = false;
};

const submit = async () => {
  if (!canSubmit.value) return;
  saving.value = true;
  try {
    if (isEditing.value) {
      await voiceBroadcastAPI.update(editingId.value, form.value);
    } else {
      await voiceBroadcastAPI.create(form.value);
    }
    useAlert(t('JABVOX_VOICE_BROADCAST.FORM.SAVED'));
    emit('saved');
    close();
  } catch (e) {
    const msg =
      e?.response?.data?.error ||
      e?.response?.data?.errors?.join(', ') ||
      t('JABVOX_VOICE_BROADCAST.FORM.ERROR');
    useAlert(msg);
  } finally {
    saving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      @click.self="close"
    >
      <div
        class="flex flex-col w-full max-w-2xl max-h-[90vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
      >
        <!-- Header -->
        <div
          class="flex items-center justify-between gap-3 px-5 py-4 border-b border-n-weak"
        >
          <div class="flex items-center gap-2.5 min-w-0">
            <span
              class="i-lucide-megaphone size-8 shrink-0 rounded-lg bg-n-alpha-2 p-1.5 text-n-brand"
            />
            <h3 class="text-base font-semibold text-n-slate-12 truncate">
              {{
                isEditing
                  ? t('JABVOX_VOICE_BROADCAST.FORM.EDIT_TITLE')
                  : t('JABVOX_VOICE_BROADCAST.FORM.NEW_TITLE')
              }}
            </h3>
          </div>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            @click="close"
          />
        </div>

        <div class="flex-1 overflow-y-auto px-5 py-5 flex flex-col gap-5">
          <!-- Sección: General -->
          <section class="flex flex-col gap-4">
            <h4
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
            >
              {{ t('JABVOX_VOICE_BROADCAST.FORM.SECTION_GENERAL') }}
            </h4>
            <div class="flex flex-col gap-1.5">
              <FieldLabel
                :text="t('JABVOX_VOICE_BROADCAST.FORM.NAME')"
                :hint="t('JABVOX_VOICE_BROADCAST.HINT.NAME')"
              />
              <Input
                v-model="form.name_jabvox"
                :placeholder="t('JABVOX_VOICE_BROADCAST.FORM.NAME')"
              />
            </div>
          </section>

          <!-- Sección: Filtros de leads — set completo, propio del módulo -->
          <section class="rounded-xl border border-n-weak">
            <div
              class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
            >
              <span
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTERS_TITLE') }}
              </span>
              <span
                v-if="leadCount != null"
                class="inline-flex items-center gap-1 text-xs text-n-slate-11"
              >
                <Spinner v-if="loadingCount" :size="12" />
                <span class="i-lucide-users size-3.5 text-n-brand" />
                <span class="font-semibold text-n-brand tabular-nums">{{
                  leadCount
                }}</span>
                {{ t('JABVOX_VOICE_BROADCAST.FORM.LEADS_WITH_PHONE') }}
              </span>
            </div>
            <div class="flex flex-col gap-4 px-4 py-4">
              <!-- Identidad: nombre / correo / teléfono / documento -->
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <Input
                  v-model="form.lead_filters_jabvox.q"
                  :label="t('JABVOX_VOICE_BROADCAST.FORM.FILTER_NAME')"
                  :placeholder="t('JABVOX_VOICE_BROADCAST.FORM.FILTER_NAME')"
                />
                <Input
                  v-model="form.lead_filters_jabvox.email"
                  :label="t('JABVOX_VOICE_BROADCAST.FORM.FILTER_EMAIL')"
                  :placeholder="t('JABVOX_VOICE_BROADCAST.FORM.FILTER_EMAIL')"
                />
                <Input
                  v-model="form.lead_filters_jabvox.phone"
                  :label="t('JABVOX_VOICE_BROADCAST.FORM.FILTER_PHONE')"
                  :placeholder="t('JABVOX_VOICE_BROADCAST.FORM.FILTER_PHONE')"
                />
                <Input
                  v-model="form.lead_filters_jabvox.document"
                  :label="t('JABVOX_VOICE_BROADCAST.FORM.FILTER_DOCUMENT')"
                  :placeholder="
                    t('JABVOX_VOICE_BROADCAST.FORM.FILTER_DOCUMENT')
                  "
                />
              </div>

              <!-- País / Bandeja: multiselección desplegable -->
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="flex flex-col gap-1.5">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_COUNTRIES') }}
                  </span>
                  <details
                    class="group rounded-lg border border-n-weak bg-n-alpha-1"
                  >
                    <summary
                      class="flex items-center justify-between gap-2 px-3 py-2 text-sm cursor-pointer select-none list-none"
                    >
                      <span class="truncate text-n-slate-12">
                        {{
                          form.countries_jabvox.length
                            ? t('JABVOX_VOICE_BROADCAST.FORM.FILTER_SELECTED', {
                                count: form.countries_jabvox.length,
                              })
                            : t('JABVOX_VOICE_BROADCAST.FORM.FILTER_ALL')
                        }}
                      </span>
                      <span
                        class="i-lucide-chevron-down size-4 text-n-slate-10 group-open:rotate-180 transition-transform"
                      />
                    </summary>
                    <div class="border-t border-n-weak p-2">
                      <input
                        v-model="optionSearch.__countries"
                        type="search"
                        :placeholder="
                          t('JABVOX_VOICE_BROADCAST.FORM.FILTER_SEARCH_OPTION')
                        "
                        class="reset-base w-full text-sm rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5"
                        @click.stop
                      />
                      <div
                        class="mt-2 max-h-40 overflow-y-auto flex flex-col gap-1.5"
                      >
                        <label
                          v-for="opt in countryOptions.filter(
                            o =>
                              !optionSearch.__countries ||
                              o.label
                                .toLowerCase()
                                .includes(
                                  optionSearch.__countries.toLowerCase()
                                )
                          )"
                          :key="opt.value"
                          class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer"
                        >
                          <input
                            type="checkbox"
                            class="rounded accent-n-brand shrink-0"
                            :checked="form.countries_jabvox.includes(opt.value)"
                            @change="
                              toggleArrayValue(form.countries_jabvox, opt.value)
                            "
                          />
                          <span class="truncate">{{ opt.label }}</span>
                        </label>
                      </div>
                    </div>
                  </details>
                </div>

                <div class="flex flex-col gap-1.5">
                  <span class="text-sm font-medium text-n-slate-12">
                    {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_INBOXES') }}
                  </span>
                  <details
                    class="group rounded-lg border border-n-weak bg-n-alpha-1"
                  >
                    <summary
                      class="flex items-center justify-between gap-2 px-3 py-2 text-sm cursor-pointer select-none list-none"
                    >
                      <span class="truncate text-n-slate-12">
                        {{
                          form.inbox_ids_jabvox.length
                            ? t('JABVOX_VOICE_BROADCAST.FORM.FILTER_SELECTED', {
                                count: form.inbox_ids_jabvox.length,
                              })
                            : t('JABVOX_VOICE_BROADCAST.FORM.FILTER_ALL')
                        }}
                      </span>
                      <span
                        class="i-lucide-chevron-down size-4 text-n-slate-10 group-open:rotate-180 transition-transform"
                      />
                    </summary>
                    <div
                      class="border-t border-n-weak p-2 max-h-44 overflow-y-auto flex flex-col gap-1.5"
                    >
                      <label
                        v-for="i in inboxes"
                        :key="i.id"
                        class="flex items-center gap-2 text-sm text-n-slate-12 cursor-pointer"
                      >
                        <input
                          type="checkbox"
                          class="rounded accent-n-brand shrink-0"
                          :checked="form.inbox_ids_jabvox.includes(i.id)"
                          @change="
                            toggleArrayValue(form.inbox_ids_jabvox, i.id)
                          "
                        />
                        <span class="truncate">{{ i.name }}</span>
                      </label>
                      <p
                        v-if="!inboxes.length"
                        class="text-xs text-n-slate-9 py-1"
                      >
                        —
                      </p>
                    </div>
                  </details>
                </div>
              </div>

              <!-- Estados de gestión: lista de checkboxes (con "sin estado") -->
              <div class="flex flex-col gap-1.5">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_STATES') }}
                </span>
                <div
                  class="flex flex-col gap-1 max-h-40 overflow-y-auto rounded-xl border border-n-weak p-2"
                >
                  <label
                    class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-11 italic select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
                  >
                    <input
                      v-model="form.management_state_ids_jabvox"
                      type="checkbox"
                      value="none"
                      class="rounded accent-n-brand"
                    />
                    {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_NO_STATE') }}
                  </label>
                  <label
                    v-for="s in managementStates"
                    :key="s.id"
                    class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
                  >
                    <input
                      v-model="form.management_state_ids_jabvox"
                      type="checkbox"
                      :value="s.id"
                      class="rounded accent-n-brand"
                    />
                    <span
                      v-if="s.color_jabvox || s.color"
                      class="w-2.5 h-2.5 rounded-full shrink-0"
                      :style="{ backgroundColor: s.color_jabvox || s.color }"
                    />
                    {{ s.name_jabvox || s.name }}
                  </label>
                  <p
                    v-if="!managementStates.length"
                    class="text-xs text-n-slate-9 px-2 py-1.5"
                  >
                    —
                  </p>
                </div>
              </div>

              <!-- Afiliados: lista de checkboxes -->
              <div class="flex flex-col gap-1.5">
                <span class="text-sm font-medium text-n-slate-12">
                  {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_AFFILIATES') }}
                </span>
                <div
                  class="flex flex-col gap-1 max-h-40 overflow-y-auto rounded-xl border border-n-weak p-2"
                >
                  <label
                    v-for="a in affiliates"
                    :key="a.id"
                    class="flex items-center gap-2 cursor-pointer text-sm text-n-slate-12 select-none rounded-lg px-2 py-1.5 hover:bg-n-alpha-1"
                  >
                    <input
                      v-model="form.affiliate_ids_jabvox"
                      type="checkbox"
                      :value="a.id"
                      class="rounded accent-n-brand"
                    />
                    {{ a.name }}
                  </label>
                  <p
                    v-if="!affiliates.length"
                    class="text-xs text-n-slate-9 px-2 py-1.5"
                  >
                    —
                  </p>
                </div>
              </div>

              <!-- Campos personalizados: SOLO seleccionables (multiselección) -->
              <div
                v-if="selectableCustomColumns.length"
                class="grid grid-cols-1 sm:grid-cols-2 gap-4"
              >
                <div
                  v-for="col in selectableCustomColumns"
                  :key="col.key"
                  class="flex flex-col gap-1.5"
                >
                  <label class="text-sm font-medium text-n-slate-12">
                    {{ col.label }}
                  </label>
                  <details
                    class="group rounded-lg border border-n-weak bg-n-alpha-1"
                  >
                    <summary
                      class="flex items-center justify-between gap-2 px-3 py-2 text-sm cursor-pointer select-none list-none"
                    >
                      <span class="truncate text-n-slate-12">
                        {{
                          selectedValues(col.key).length
                            ? t('JABVOX_VOICE_BROADCAST.FORM.FILTER_SELECTED', {
                                count: selectedValues(col.key).length,
                              })
                            : t('JABVOX_VOICE_BROADCAST.FORM.FILTER_ALL')
                        }}
                      </span>
                      <span
                        class="i-lucide-chevron-down size-4 text-n-slate-10 group-open:rotate-180 transition-transform"
                      />
                    </summary>
                    <div class="border-t border-n-weak">
                      <div class="p-2">
                        <input
                          v-model="optionSearch[col.key]"
                          type="search"
                          :placeholder="
                            t(
                              'JABVOX_VOICE_BROADCAST.FORM.FILTER_SEARCH_OPTION'
                            )
                          "
                          class="reset-base w-full text-sm rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5"
                          @click.stop
                          @input="onOptionSearch(col)"
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
                              selectedValues(col.key).includes(EMPTY_VALUE)
                            "
                            @change="toggleCustomOption(col.key, EMPTY_VALUE)"
                          />
                          <span class="truncate">
                            {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_EMPTY') }}
                          </span>
                        </label>
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
                          {{
                            t('JABVOX_VOICE_BROADCAST.FORM.FILTER_NO_OPTIONS')
                          }}
                        </p>
                      </div>
                    </div>
                  </details>
                </div>
              </div>

              <p class="text-xs text-n-slate-10">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_HINT') }}
              </p>
            </div>
          </section>

          <!-- Sección: Vista previa de leads (paginada + exclusión) -->
          <section class="rounded-xl border border-n-weak">
            <button
              type="button"
              class="flex w-full items-center justify-between px-4 py-3"
              @click="togglePreview"
            >
              <span
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ t('JABVOX_VOICE_BROADCAST.FORM.PREVIEW_TITLE') }}
              </span>
              <span
                :class="
                  showPreview ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
                "
                class="size-4 text-n-slate-10"
              />
            </button>
            <div v-show="showPreview" class="flex flex-col gap-3 px-4 pb-4">
              <div
                class="flex items-center justify-between gap-2 flex-wrap text-xs"
              >
                <div class="flex items-center gap-2">
                  <button
                    type="button"
                    class="text-n-brand hover:underline disabled:opacity-40"
                    :disabled="!form.excluded_lead_ids_jabvox.length"
                    @click="selectAllLeads"
                  >
                    {{ t('JABVOX_VOICE_BROADCAST.FORM.PREVIEW_SELECT_ALL') }}
                  </button>
                  <span class="text-n-slate-9">·</span>
                  <button
                    type="button"
                    class="text-n-slate-11 hover:underline"
                    @click="deselectAllLeads"
                  >
                    {{ t('JABVOX_VOICE_BROADCAST.FORM.PREVIEW_DESELECT_ALL') }}
                  </button>
                </div>
                <span class="text-n-slate-10 tabular-nums">
                  {{ previewTotal }}
                  {{ t('JABVOX_VOICE_BROADCAST.FORM.PREVIEW_MATCHES') }}
                </span>
              </div>

              <div class="rounded-xl border border-n-weak overflow-hidden">
                <div class="max-h-72 overflow-y-auto">
                  <table class="w-full text-sm">
                    <thead
                      class="bg-n-alpha-1 text-n-slate-11 sticky top-0 backdrop-blur"
                    >
                      <tr>
                        <th class="w-9 px-2 py-2" />
                        <th class="text-left px-2 py-2 font-medium">
                          {{ t('JABVOX_VOICE_BROADCAST.RECIPIENT.NAME') }}
                        </th>
                        <th class="text-left px-2 py-2 font-medium">
                          {{ t('JABVOX_VOICE_BROADCAST.RECIPIENT.PHONE') }}
                        </th>
                        <th class="text-left px-2 py-2 font-medium">
                          {{ t('JABVOX_VOICE_BROADCAST.FORM.FILTER_EMAIL') }}
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="lead in previewLeads"
                        :key="lead.lead_id || lead.id"
                        class="border-t border-n-weak"
                        :class="
                          leadIncluded(lead.lead_id || lead.id)
                            ? ''
                            : 'text-n-slate-9 opacity-60'
                        "
                      >
                        <td class="px-2 py-1.5 text-center">
                          <input
                            type="checkbox"
                            class="rounded accent-n-brand"
                            :checked="leadIncluded(lead.lead_id || lead.id)"
                            @change="toggleLead(lead.lead_id || lead.id)"
                          />
                        </td>
                        <td class="px-2 py-1.5 truncate max-w-40">
                          {{ lead.name || '—' }}
                        </td>
                        <td class="px-2 py-1.5 font-mono text-xs">
                          {{ lead.phone || '—' }}
                        </td>
                        <td class="px-2 py-1.5 truncate max-w-40">
                          {{ lead.email || '—' }}
                        </td>
                      </tr>
                      <tr v-if="!previewLeads.length && !loadingPreview">
                        <td
                          colspan="4"
                          class="px-2 py-6 text-center text-xs text-n-slate-9"
                        >
                          {{ t('JABVOX_VOICE_BROADCAST.FORM.PREVIEW_EMPTY') }}
                        </td>
                      </tr>
                      <tr v-if="loadingPreview">
                        <td colspan="4" class="px-2 py-6 text-center">
                          <Spinner :size="16" class="mx-auto" />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <!-- Paginación -->
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
                  <span class="tabular-nums">
                    {{ previewPage }} / {{ previewPages }}
                  </span>
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

          <!-- Sección: Marcado -->
          <section class="rounded-xl border border-n-weak">
            <div class="px-4 py-3 border-b border-n-weak">
              <span
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ t('JABVOX_VOICE_BROADCAST.FORM.SECTION_DIALING') }}
              </span>
            </div>
            <div class="flex flex-col gap-4 px-4 py-4">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="flex flex-col gap-1.5">
                  <FieldLabel
                    :text="t('JABVOX_VOICE_BROADCAST.FORM.CALLER_ID')"
                    :hint="t('JABVOX_VOICE_BROADCAST.HINT.CALLER_ID')"
                  />
                  <Input
                    v-model="form.caller_id_jabvox"
                    placeholder="Ej: 6015551234"
                  />
                </div>
                <div class="flex flex-col gap-1.5">
                  <FieldLabel
                    :text="t('JABVOX_VOICE_BROADCAST.FORM.MAX_CONCURRENT')"
                    :hint="t('JABVOX_VOICE_BROADCAST.HINT.MAX_CONCURRENT')"
                  />
                  <Input
                    v-model.number="form.max_concurrent_jabvox"
                    type="number"
                    min="1"
                  />
                </div>
                <div class="flex flex-col gap-1.5">
                  <FieldLabel
                    :text="t('JABVOX_VOICE_BROADCAST.FORM.CPS')"
                    :hint="t('JABVOX_VOICE_BROADCAST.HINT.CPS')"
                  />
                  <Input
                    v-model.number="form.cps_jabvox"
                    type="number"
                    min="1"
                  />
                </div>
                <div class="flex flex-col gap-1.5">
                  <FieldLabel
                    :text="t('JABVOX_VOICE_BROADCAST.FORM.MAX_RETRIES')"
                    :hint="t('JABVOX_VOICE_BROADCAST.HINT.MAX_RETRIES')"
                  />
                  <Input
                    v-model.number="form.max_retries_jabvox"
                    type="number"
                    min="0"
                  />
                </div>
                <div class="flex flex-col gap-1.5">
                  <FieldLabel
                    :text="t('JABVOX_VOICE_BROADCAST.FORM.RETRY_INTERVAL')"
                    :hint="t('JABVOX_VOICE_BROADCAST.HINT.RETRY_INTERVAL')"
                  />
                  <Input
                    v-model.number="form.retry_interval_jabvox"
                    type="number"
                    min="0"
                  />
                </div>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="flex flex-col gap-1.5">
                  <FieldLabel
                    :text="t('JABVOX_VOICE_BROADCAST.FORM.HOURS_START')"
                    :hint="t('JABVOX_VOICE_BROADCAST.HINT.HOURS')"
                  />
                  <input
                    v-model="form.calling_hours_start_jabvox"
                    type="time"
                    class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
                  />
                </div>
                <div class="flex flex-col gap-1.5">
                  <FieldLabel
                    :text="t('JABVOX_VOICE_BROADCAST.FORM.HOURS_END')"
                    :hint="t('JABVOX_VOICE_BROADCAST.HINT.HOURS')"
                  />
                  <input
                    v-model="form.calling_hours_end_jabvox"
                    type="time"
                    class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-n-slate-12"
                  />
                </div>
              </div>
              <p v-if="!hoursValid" class="text-xs text-n-ruby-11">
                {{ t('JABVOX_VOICE_BROADCAST.FORM.HOURS_INVALID') }}
              </p>
            </div>
          </section>

          <!-- Sección: Detección y opt-out -->
          <section class="rounded-xl border border-n-weak">
            <div class="px-4 py-3 border-b border-n-weak">
              <span
                class="text-xs font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ t('JABVOX_VOICE_BROADCAST.FORM.SECTION_DETECTION') }}
              </span>
            </div>
            <div class="flex flex-col gap-3 px-4 py-4">
              <div
                class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
              >
                <FieldLabel
                  :text="t('JABVOX_VOICE_BROADCAST.FORM.AMD')"
                  :hint="t('JABVOX_VOICE_BROADCAST.HINT.AMD')"
                />
                <input
                  v-model="form.amd_enabled_jabvox"
                  type="checkbox"
                  class="rounded accent-n-brand cursor-pointer"
                />
              </div>
              <div
                class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
              >
                <FieldLabel
                  :text="t('JABVOX_VOICE_BROADCAST.FORM.DTMF')"
                  :hint="t('JABVOX_VOICE_BROADCAST.HINT.DTMF')"
                />
                <input
                  v-model="form.dtmf_enabled_jabvox"
                  type="checkbox"
                  class="rounded accent-n-brand cursor-pointer"
                />
              </div>
              <div
                v-if="form.dtmf_enabled_jabvox"
                class="flex flex-col gap-1.5 max-w-[140px]"
              >
                <FieldLabel
                  :text="t('JABVOX_VOICE_BROADCAST.FORM.DTMF_DIGIT')"
                  :hint="t('JABVOX_VOICE_BROADCAST.HINT.DTMF_DIGIT')"
                />
                <Input v-model="form.dtmf_optout_digit_jabvox" maxlength="1" />
              </div>
            </div>
          </section>

          <!-- Nota: dónde se sube el audio -->
          <div
            class="flex items-start gap-2.5 rounded-xl border border-n-blue-6 bg-n-blue-2 px-4 py-3"
          >
            <span class="i-lucide-info size-4 text-n-blue-11 shrink-0 mt-0.5" />
            <p class="text-xs text-n-blue-11 leading-relaxed">
              {{ t('JABVOX_VOICE_BROADCAST.FORM.AUDIO_NOTE') }}
            </p>
          </div>
        </div>

        <!-- Footer: banner de conteo (leads) + acciones -->
        <div class="border-t border-n-weak px-5 py-4 flex flex-col gap-3">
          <div
            v-if="leadCount != null"
            class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
          >
            <span class="flex items-center gap-2 text-sm text-n-slate-12">
              <span class="i-lucide-users size-4 text-n-brand" />
              {{ t('JABVOX_VOICE_BROADCAST.FORM.LEADS_TO_CALL') }}
            </span>
            <span class="text-sm font-semibold text-n-brand tabular-nums">
              {{ leadCount }}
            </span>
          </div>
          <div class="flex items-center justify-end gap-2">
            <Button
              :label="t('JABVOX_VOICE_BROADCAST.FORM.CANCEL')"
              variant="outline"
              color="slate"
              size="sm"
              @click="close"
            />
            <Button
              :label="t('JABVOX_VOICE_BROADCAST.FORM.SAVE')"
              icon="i-lucide-check"
              size="sm"
              :is-loading="saving"
              :disabled="!canSubmit"
              @click="submit"
            />
          </div>
        </div>
      </div>
    </div>
  </teleport>
</template>
