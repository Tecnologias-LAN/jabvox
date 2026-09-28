<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { stageClass } from 'dashboard/helper/jabvox/lifecycleStage';
import { useAlert } from 'dashboard/composables';
import contactsListAPI from 'dashboard/api/jabvox/contactsList';
import countries from 'shared/constants/countries.js';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

// Tabla de contactos al estilo de la antigua pantalla de Leads: columnas intercambiables,
// filtros por cada campo (incluidos los personalizados, solo seleccionables) y etapa del
// ciclo de vida editable en la propia fila.
//
// Mantiene el contrato de ContactsList (contacts + selectedContactIds + toggleContact) para
// que la pantalla de Contactos siga funcionando igual alrededor: importar, exportar,
// segmentos, borrado masivo.
const props = defineProps({
  contacts: { type: Array, required: true },
  selectedContactIds: { type: Array, default: () => [] },
});
const emit = defineEmits(['toggleContact']);

const router = useRouter();
const route = useRoute();
const { t } = useI18n();

// Datos comerciales por id de contacto (etapa, campaña, afiliado, responsable, campos
// personalizados). La lista base de Chatwoot no los trae: se piden en UNA sola consulta
// para las filas visibles, no una por fila.
const enrichment = ref({});
const filterOptions = ref({});
const showColumns = ref(false);
const showFilters = ref(false);

// --- Filtros ---------------------------------------------------------------
// Texto primero (id, nombre, correo, teléfono, documento) y el resto seleccionable, en el
// mismo orden que tenía la pantalla de Leads. Los selectores aceptan VARIOS valores, así
// que su estado es un array.
const TEXT_FIELDS = [
  'contact_id',
  'q',
  'email',
  'phone',
  'document',
  'country',
];
const MULTI_FIELDS = [
  'lifecycle_stage',
  'campaign_id',
  'affiliate_id',
  'assignee_id',
  'inbox_id',
  'management_state',
  'labels',
];

const emptyFilters = () => ({
  ...Object.fromEntries(TEXT_FIELDS.map(k => [k, ''])),
  ...Object.fromEntries(MULTI_FIELDS.map(k => [k, []])),
  // Rango de GESTIONES: acota cuántas y cuáles gestiones tuvo cada contacto.
  date_from: '',
  date_to: '',
});
const filters = ref(emptyFilters());
// Campos personalizados: { clave: [valores] }. Solo seleccionables, nunca texto libre.
const customFilters = ref({});
// Ids que pasan los filtros; null = sin filtrar (se muestran todos los de la página).
const filteredIds = ref(null);

const customFieldDefs = computed(() => filterOptions.value.custom_fields || []);

const activeFilterCount = computed(
  () =>
    Object.values(filters.value).filter(v =>
      Array.isArray(v) ? v.length > 0 : v !== ''
    ).length + Object.values(customFilters.value).filter(v => v?.length).length
);

// Alterna un valor en un filtro de selección múltiple.
function toggleFilterValue(key, value) {
  const current = filters.value[key] || [];
  filters.value = {
    ...filters.value,
    [key]: current.includes(value)
      ? current.filter(v => v !== value)
      : [...current, value],
  };
}

const isFilterSelected = (key, value) =>
  (filters.value[key] || []).includes(value);

// Qué desplegable está abierto (solo uno a la vez, como una lista normal).
const openDropdown = ref('');
const toggleDropdown = key => {
  openDropdown.value = openDropdown.value === key ? '' : key;
};

// Resumen que se lee en el botón del desplegable: "Etapa", "Etapa: Cliente" o "Etapa: 2".
// Resumen del desplegable de un campo personalizado.
function customSummary(field) {
  const selected = customFilters.value[field.key] || [];
  if (!selected.length) return field.label;
  return selected.length === 1
    ? `${field.label}: ${selected[0]}`
    : `${field.label}: ${selected.length}`;
}

function filterSummary(group) {
  const selected = filters.value[group.key] || [];
  if (!selected.length) return group.label;
  if (selected.length === 1) {
    const opt = group.options.find(o => String(o.id) === String(selected[0]));
    return `${group.label}: ${opt?.name ?? selected[0]}`;
  }
  return `${group.label}: ${selected.length}`;
}

// Etiqueta de cada campo de texto. Se resuelve por mapa para no repetir el t() en plantilla.
const TEXT_LABELS = {
  contact_id: 'JABVOX_CONTACTS.FILTERS.ID',
  q: 'JABVOX_CONTACTS.FILTERS.NAME',
  email: 'JABVOX_CONTACTS.FILTERS.EMAIL',
  phone: 'JABVOX_CONTACTS.FILTERS.PHONE',
  document: 'JABVOX_CONTACTS.FILTERS.DOCUMENT',
  country: 'JABVOX_CONTACTS.FILTERS.COUNTRY',
};
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const textFieldLabel = field => t(TEXT_LABELS[field] || field);

// Grupos de selección múltiple, con sus opciones del backend.
const multiFilterGroups = computed(() => [
  {
    key: 'lifecycle_stage',
    label: t('JABVOX_CONTACTS.COLUMNS.STAGE'),
    options: filterOptions.value.lifecycle_stages || [],
  },
  {
    key: 'labels',
    label: t('JABVOX_CONTACTS.COLUMNS.LABELS'),
    options: filterOptions.value.labels || [],
  },
  {
    key: 'campaign_id',
    label: t('JABVOX_CONTACTS.FILTERS.CAMPAIGN'),
    options: filterOptions.value.campaigns || [],
  },
  {
    key: 'assignee_id',
    label: t('JABVOX_CONTACTS.FILTERS.ASSIGNEE'),
    options: filterOptions.value.assignees || [],
  },
  {
    key: 'affiliate_id',
    label: t('JABVOX_CONTACTS.FILTERS.AFFILIATE'),
    options: filterOptions.value.affiliates || [],
  },
  {
    key: 'inbox_id',
    label: t('JABVOX_CONTACTS.FILTERS.INBOX'),
    options: filterOptions.value.inboxes || [],
  },
  {
    key: 'management_state',
    label: t('JABVOX_CONTACTS.FILTERS.MANAGEMENT'),
    options: filterOptions.value.management_states || [],
  },
]);

// --- Carga de datos comerciales ---------------------------------------------
async function loadEnrichment() {
  const ids = props.contacts.map(c => c.id);
  if (!ids.length) {
    enrichment.value = {};
    return;
  }
  try {
    const { data } = await contactsListAPI.getAll({
      per_page: 100,
      contact_ids: ids,
    });
    const map = {};
    (data.contacts || []).forEach(row => {
      map[row.id] = row;
    });
    enrichment.value = map;
    if (data.filter_options) filterOptions.value = data.filter_options;
  } catch {
    // Sin estos datos la tabla sigue mostrando los campos base del contacto.
    enrichment.value = {};
  }
}

const extra = contact => enrichment.value[contact.id] || {};

// Pide al backend qué contactos pasan los filtros y se cruza con la página actual.
async function applyFilters() {
  if (!activeFilterCount.value) {
    filteredIds.value = null;
    showFilters.value = false;
    return;
  }
  const params = { per_page: 100 };
  Object.entries(filters.value).forEach(([key, value]) => {
    if (Array.isArray(value)) {
      if (value.length) params[key] = value;
    } else if (value !== '') {
      params[key] = value;
    }
  });
  Object.entries(customFilters.value).forEach(([key, values]) => {
    if (values?.length) params[`custom[${key}]`] = values;
  });
  try {
    const { data } = await contactsListAPI.getAll(params);
    filteredIds.value = (data.contacts || []).map(c => c.id);
    showFilters.value = false;
  } catch (error) {
    useAlert(error?.response?.data?.error || t('JABVOX_CONTACTS.ERROR.LOAD'));
  }
}

function clearFilters() {
  filters.value = emptyFilters();
  customFilters.value = {};
  filteredIds.value = null;
}

function toggleCustomValue(key, value) {
  const current = customFilters.value[key] || [];
  customFilters.value = {
    ...customFilters.value,
    [key]: current.includes(value)
      ? current.filter(v => v !== value)
      : [...current, value],
  };
}

// --- Columnas intercambiables ----------------------------------------------
const DEFAULT_COLUMNS = [
  { id: 'name', labelKey: 'JABVOX_CONTACTS.COLUMNS.NAME' },
  { id: 'lifecycle', labelKey: 'JABVOX_CONTACTS.COLUMNS.STAGE' },
  { id: 'phone', labelKey: 'JABVOX_CONTACTS.COLUMNS.PHONE' },
  { id: 'email', labelKey: 'JABVOX_CONTACTS.COLUMNS.EMAIL' },
  { id: 'country', labelKey: 'JABVOX_CONTACTS.COLUMNS.COUNTRY' },
  { id: 'campaign', labelKey: 'JABVOX_CONTACTS.COLUMNS.CAMPAIGN' },
  { id: 'affiliate', labelKey: 'JABVOX_CONTACTS.COLUMNS.AFFILIATE' },
  { id: 'assignee', labelKey: 'JABVOX_CONTACTS.COLUMNS.ASSIGNEE' },
  { id: 'labels', labelKey: 'JABVOX_CONTACTS.COLUMNS.LABELS' },
  { id: 'managements', labelKey: 'JABVOX_CONTACTS.COLUMNS.MANAGEMENTS' },
];
const columnConfig = ref(DEFAULT_COLUMNS.map(c => `d:${c.id}`));
const storageKey = () => `jabvox_contact_columns_${route.params.accountId}`;

function loadColumnConfig() {
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey()) || 'null');
    if (Array.isArray(saved) && saved.length === DEFAULT_COLUMNS.length) {
      columnConfig.value = saved;
    }
  } catch {
    // Un valor corrupto no debe impedir abrir la pantalla.
  }
}

function saveColumnConfig() {
  try {
    localStorage.setItem(storageKey(), JSON.stringify(columnConfig.value));
  } catch {
    // Sin localStorage la elección dura lo que la sesión.
  }
}

function setColumn(index, value) {
  columnConfig.value[index] = value;
  saveColumnConfig();
}

function resetColumns() {
  columnConfig.value = DEFAULT_COLUMNS.map(c => `d:${c.id}`);
  saveColumnConfig();
}

const columnOptions = computed(() => [
  // Clave dinámica a propósito: las columnas se declaran en DEFAULT_COLUMNS.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  ...DEFAULT_COLUMNS.map(c => ({ value: `d:${c.id}`, label: t(c.labelKey) })),
  ...customFieldDefs.value.map(f => ({ value: `c:${f.key}`, label: f.label })),
]);

const visibleColumns = computed(() =>
  columnConfig.value.map((cfg, i) => {
    const [kind, id] = cfg.split(':');
    if (kind === 'c') {
      const def = customFieldDefs.value.find(f => f.key === id);
      return { key: cfg, custom: id, label: def?.label || id };
    }
    const col = DEFAULT_COLUMNS.find(c => c.id === id) || DEFAULT_COLUMNS[i];
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    return { key: cfg, id: col.id, label: t(col.labelKey) };
  })
);

// Orden local de la página por la columna pulsada (a-z / z-a).
const sortBy = ref('');
const sortAsc = ref(true);

function toggleSort(column) {
  if (column.id === 'lifecycle') return;
  if (sortBy.value === column.key) {
    sortAsc.value = !sortAsc.value;
  } else {
    sortBy.value = column.key;
    sortAsc.value = true;
  }
}

const countryName = code =>
  countries.find(c => c.id === code || c.name === code)?.name || code || '—';

// Resolución de celda por mapa: evita una cadena de v-if por columna y fila.
const CELL = {
  name: c => c.name || '—',
  phone: c => c.phone_number || '—',
  email: c => c.email || '—',
  country: (c, x) => countryName(x.country || c.additional_attributes?.country),
  campaign: (c, x) => x.campaign?.name || '—',
  affiliate: (c, x) => x.affiliate?.name || '—',
  assignee: (c, x) => x.assignee?.name || '—',
  labels: (c, x) => (x.labels?.length ? x.labels.join(', ') : '—'),
  // Sin rango de fechas: el título de la última gestión. Con rango: cuántas hubo y cuáles.
  managements: (c, x) => {
    const m = x.managements;
    if (!m?.count) return '—';
    const hasRange = filters.value.date_from || filters.value.date_to;
    if (!hasRange) return m.last?.name || `${m.count}`;
    return `${m.count} · ${m.names.join(', ')}`;
  },
};

function cellValue(contact, column) {
  const x = extra(contact);
  if (column.custom) return x.custom_fields?.[column.custom] || '—';
  return CELL[column.id]?.(contact, x) ?? '—';
}

// Etapa: pastilla plana y ancha, no un círculo. Los colores salen del helper compartido
// para que el detalle del Kanban pinte exactamente la misma pastilla.
const stageOf = contact => extra(contact).lifecycle_stage || 'prospecto';

async function changeStage(contact, stage) {
  if (stage === stageOf(contact)) return;
  try {
    const { data } = await contactsListAPI.updateLifecycle(contact.id, stage);
    enrichment.value = { ...enrichment.value, [contact.id]: data };
  } catch (error) {
    useAlert(error?.response?.data?.error || t('JABVOX_CONTACTS.ERROR.STAGE'));
  }
}

// Filas visibles: todas, o solo las que pasan el filtro aplicado.
const visibleContacts = computed(() => {
  let rows = props.contacts;
  if (filteredIds.value !== null) {
    const allowed = new Set(filteredIds.value);
    rows = rows.filter(c => allowed.has(c.id));
  }
  if (!sortBy.value) return rows;

  // Orden por la columna pulsada. Se compara el texto que se ve, para que a-z signifique
  // lo mismo que el usuario está leyendo.
  const col = visibleColumns.value.find(c => c.key === sortBy.value);
  if (!col) return rows;

  const dir = sortAsc.value ? 1 : -1;
  return [...rows].sort(
    (a, b) =>
      dir *
      String(cellValue(a, col)).localeCompare(String(cellValue(b, col)), 'es', {
        numeric: true,
      })
  );
});

// --- Selección --------------------------------------------------------------
const visibleIds = computed(() => visibleContacts.value.map(c => c.id));
const selectedVisibleCount = computed(
  () =>
    visibleIds.value.filter(id => props.selectedContactIds.includes(id)).length
);
const allVisibleSelected = computed(
  () =>
    visibleIds.value.length > 0 &&
    selectedVisibleCount.value === visibleIds.value.length
);
const someVisibleSelected = computed(
  () => selectedVisibleCount.value > 0 && !allVisibleSelected.value
);

const isSelected = id => props.selectedContactIds.includes(id);

// El padre espera { id, value }: `value` fija el estado en vez de alternarlo, que es lo
// que necesita "seleccionar todos" para no invertir los ya marcados.
function toggleOne(id, value) {
  emit('toggleContact', { id, value });
}

function toggleAllVisible() {
  const value = !allVisibleSelected.value;
  visibleIds.value.forEach(id => emit('toggleContact', { id, value }));
}

function clearSelection() {
  props.selectedContactIds.forEach(id =>
    emit('toggleContact', { id, value: false })
  );
}

// Clic en la fila (fuera del checkbox y de la etapa) abre el detalle del contacto.
function openContact(contact) {
  // `contacts_edit` es la ruta real del detalle (contacts_dashboard_show no existe, por eso
  // el clic no hacía nada).
  router.push({
    name: 'contacts_edit',
    params: { accountId: route.params.accountId, contactId: contact.id },
  });
}

// Al cambiar de página se recargan los datos comerciales de las nuevas filas.
watch(() => props.contacts.map(c => c.id).join(','), loadEnrichment);

onMounted(() => {
  loadColumnConfig();
  loadEnrichment();
});
</script>

<template>
  <div class="flex flex-col w-full gap-2">
    <!-- Barra de herramientas -->
    <div class="flex items-center gap-2 px-1">
      <span v-if="selectedVisibleCount" class="text-xs text-n-slate-11">
        {{
          t('JABVOX_CONTACTS.SELECTION.COUNT', { count: selectedVisibleCount })
        }}
      </span>
      <Button
        v-if="selectedVisibleCount"
        variant="ghost"
        size="sm"
        :label="t('JABVOX_CONTACTS.SELECTION.CLEAR')"
        @click="clearSelection"
      />
      <div class="flex-1" />
      <Button
        icon="i-lucide-filter"
        variant="ghost"
        size="sm"
        :label="t('JABVOX_CONTACTS.FILTERS.TITLE')"
        @click="showFilters = !showFilters"
      />
      <span
        v-if="activeFilterCount"
        class="text-xs rounded-full bg-n-brand text-white px-1.5 py-0.5 tabular-nums"
      >
        {{ activeFilterCount }}
      </span>
      <Button
        icon="i-lucide-columns-3"
        variant="ghost"
        size="sm"
        :label="t('JABVOX_CONTACTS.COLUMNS.TITLE')"
        @click="showColumns = !showColumns"
      />
    </div>

    <!-- Panel de filtros -->
    <div
      v-if="showFilters"
      class="rounded-xl border border-n-weak bg-n-alpha-1 p-3 max-h-80 overflow-y-auto"
    >
      <!-- Texto: id, nombre, correo, teléfono, documento, país -->
      <div class="grid grid-cols-2 md:grid-cols-3 gap-2">
        <input
          v-for="field in TEXT_FIELDS"
          :key="field"
          v-model="filters[field]"
          class="reset-base text-xs rounded-lg border border-n-weak bg-n-background px-2.5 py-1.5 text-n-slate-12"
          :placeholder="textFieldLabel(field)"
        />
      </div>

      <!-- Rango de GESTIONES: de qué fecha a qué fecha contar las gestiones -->
      <div class="mt-3 flex items-center gap-2 flex-wrap">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_CONTACTS.FILTERS.MANAGEMENT_RANGE') }}
        </span>
        <input
          v-model="filters.date_from"
          type="date"
          class="reset-base text-xs rounded-lg border border-n-weak bg-n-background px-2 py-1.5 text-n-slate-11"
        />
        <span class="text-xs text-n-slate-10">{{ '\u2014' }}</span>
        <input
          v-model="filters.date_to"
          type="date"
          class="reset-base text-xs rounded-lg border border-n-weak bg-n-background px-2 py-1.5 text-n-slate-11"
        />
      </div>

      <!-- Selecciones múltiples: cada filtro es una lista desplegable donde se marcan
           uno o varios valores -->
      <div class="mt-3 grid grid-cols-2 md:grid-cols-4 gap-2">
        <div
          v-for="group in multiFilterGroups"
          :key="group.key"
          class="relative"
        >
          <button
            class="reset-base w-full text-xs rounded-lg border border-n-weak bg-n-background px-2.5 py-1.5 text-left flex items-center justify-between gap-1"
            :class="
              (filters[group.key] || []).length
                ? 'text-n-slate-12 border-n-brand'
                : 'text-n-slate-11'
            "
            @click="toggleDropdown(group.key)"
          >
            <span class="truncate">{{ filterSummary(group) }}</span>
            <span class="i-lucide-chevron-down size-3 shrink-0 opacity-60" />
          </button>
          <div
            v-if="openDropdown === group.key"
            class="absolute z-20 mt-1 w-full max-h-52 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 shadow-lg p-1"
          >
            <label
              v-for="opt in group.options"
              :key="opt.id"
              class="flex items-center gap-2 px-2 py-1 rounded-md hover:bg-n-alpha-1 cursor-pointer"
            >
              <input
                type="checkbox"
                class="cursor-pointer"
                :checked="isFilterSelected(group.key, opt.id)"
                @change="toggleFilterValue(group.key, opt.id)"
              />
              <span class="text-xs text-n-slate-11 truncate">
                {{ opt.name }}
              </span>
            </label>
            <p
              v-if="!group.options.length"
              class="text-xs text-n-slate-9 px-2 py-1"
            >
              {{ t('JABVOX_CONTACTS.FILTERS.NO_VALUES') }}
            </p>
          </div>
        </div>
      </div>

      <!-- Campos personalizados: solo seleccionables -->
      <!-- Campos personalizados: desplegables con selección múltiple, nunca texto libre -->
      <div
        v-if="customFieldDefs.length"
        class="mt-3 grid grid-cols-2 md:grid-cols-4 gap-2"
      >
        <div v-for="field in customFieldDefs" :key="field.key" class="relative">
          <button
            class="reset-base w-full text-xs rounded-lg border border-n-weak bg-n-background px-2.5 py-1.5 text-left flex items-center justify-between gap-1"
            :class="
              (customFilters[field.key] || []).length
                ? 'text-n-slate-12 border-n-brand'
                : 'text-n-slate-11'
            "
            @click="toggleDropdown(`c:${field.key}`)"
          >
            <span class="truncate">{{ customSummary(field) }}</span>
            <span class="i-lucide-chevron-down size-3 shrink-0 opacity-60" />
          </button>
          <div
            v-if="openDropdown === `c:${field.key}`"
            class="absolute z-20 mt-1 w-full max-h-52 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-1 shadow-lg p-1"
          >
            <label
              v-for="opt in field.options"
              :key="opt"
              class="flex items-center gap-2 px-2 py-1 rounded-md hover:bg-n-alpha-1 cursor-pointer"
            >
              <input
                type="checkbox"
                class="cursor-pointer"
                :checked="(customFilters[field.key] || []).includes(opt)"
                @change="toggleCustomValue(field.key, opt)"
              />
              <span class="text-xs text-n-slate-11 truncate">{{ opt }}</span>
            </label>
            <p
              v-if="!field.options.length"
              class="text-xs text-n-slate-9 px-2 py-1"
            >
              {{ t('JABVOX_CONTACTS.FILTERS.NO_VALUES') }}
            </p>
          </div>
        </div>
      </div>

      <div class="flex justify-end gap-2 mt-3">
        <Button
          variant="ghost"
          size="sm"
          :label="t('JABVOX_CONTACTS.FILTERS.CLEAR')"
          @click="clearFilters"
        />
        <Button
          size="sm"
          :label="t('JABVOX_CONTACTS.FILTERS.APPLY')"
          @click="applyFilters"
        />
      </div>
    </div>

    <!-- Panel de columnas -->
    <div
      v-if="showColumns"
      class="rounded-xl border border-n-weak bg-n-alpha-1 p-3"
    >
      <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
        <div
          v-for="(cfg, index) in columnConfig"
          :key="index"
          class="flex items-center gap-1.5"
        >
          <span class="text-xs text-n-slate-10 tabular-nums w-4">
            {{ index + 1 }}
          </span>
          <select
            :value="cfg"
            class="reset-base flex-1 text-xs rounded-lg border border-n-weak bg-n-background px-2 py-1.5 text-n-slate-11"
            @change="setColumn(index, $event.target.value)"
          >
            <option v-for="o in columnOptions" :key="o.value" :value="o.value">
              {{ o.label }}
            </option>
          </select>
        </div>
      </div>
      <div class="flex justify-end mt-2">
        <Button
          variant="ghost"
          size="sm"
          :label="t('JABVOX_CONTACTS.COLUMNS.RESET')"
          @click="resetColumns"
        />
      </div>
    </div>

    <!-- Tabla -->
    <div class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1">
      <table class="w-full text-sm border-collapse">
        <thead class="border-b border-n-weak text-xs text-n-slate-10">
          <tr>
            <th class="w-10 px-3 py-2.5">
              <input
                type="checkbox"
                class="cursor-pointer"
                :checked="allVisibleSelected"
                :indeterminate="someVisibleSelected"
                :title="t('JABVOX_CONTACTS.SELECTION.ALL')"
                @change="toggleAllVisible"
              />
            </th>
            <th
              v-for="col in visibleColumns"
              :key="col.key"
              class="text-left font-medium px-3 py-2.5 whitespace-nowrap select-none"
              :class="
                col.id === 'lifecycle'
                  ? ''
                  : 'cursor-pointer hover:text-n-slate-12'
              "
              @click="toggleSort(col)"
            >
              {{ col.label }}
              <span
                v-if="sortBy === col.key"
                class="ml-0.5 align-middle size-3 inline-block"
                :class="
                  sortAsc ? 'i-lucide-arrow-up-a-z' : 'i-lucide-arrow-down-z-a'
                "
              />
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="contact in visibleContacts"
            :key="contact.id"
            class="border-b border-n-weak last:border-0 hover:bg-n-alpha-1 cursor-pointer transition-colors"
            :class="isSelected(contact.id) ? 'bg-n-alpha-2' : ''"
            @click="openContact(contact)"
          >
            <td class="px-3 py-2" @click.stop>
              <input
                type="checkbox"
                class="cursor-pointer"
                :checked="isSelected(contact.id)"
                @change="toggleOne(contact.id, $event.target.checked)"
              />
            </td>
            <td
              v-for="col in visibleColumns"
              :key="col.key"
              class="px-3 py-2 text-n-slate-11 max-w-[240px] truncate"
            >
              <div v-if="col.id === 'name'" class="flex items-center gap-2.5">
                <Avatar :name="contact.name" :size="26" />
                <span class="truncate text-n-slate-12">{{ contact.name }}</span>
              </div>
              <select
                v-else-if="col.id === 'lifecycle'"
                :value="stageOf(contact)"
                class="reset-base w-full max-w-[130px] text-xs rounded-md border px-2 py-1 cursor-pointer"
                :class="stageClass(stageOf(contact))"
                @click.stop
                @change="changeStage(contact, $event.target.value)"
              >
                <option
                  v-for="s in filterOptions.lifecycle_stages || []"
                  :key="s.id"
                  :value="s.id"
                >
                  {{ s.name }}
                </option>
              </select>
              <span v-else>{{ cellValue(contact, col) }}</span>
            </td>
          </tr>
          <tr v-if="!visibleContacts.length">
            <td
              :colspan="visibleColumns.length + 1"
              class="px-3 py-8 text-center text-sm text-n-slate-10"
            >
              {{ t('JABVOX_CONTACTS.FILTERS.NO_MATCHES') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
