<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { campaignsAPI } from 'dashboard/api/jabvox/campaigns';
import ContactAPI from 'dashboard/api/contacts';
import {
  buildPreviewRows,
  importableCount as computeImportable,
  rowsWithPrefix,
  rowsAlreadyExisting,
} from './importPreviewHelper';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import countries from 'shared/constants/countries.js';

const emit = defineEmits(['import']);
const { t } = useI18n();
const route = useRoute();

const uiFlags = useMapGetter('contacts/getUIFlags');
const isImportingContact = computed(() => uiFlags.value.isImporting);

const dialogRef = ref(null);
const fileInput = ref(null);

// ── step: 'select' | 'mapping' | 'preview' ────────────────────────────
const currentStep = ref('select');

// ── preview state ─────────────────────────────────────────────────────
// Resumen que devuelve el backend antes de importar: qué se crearía, qué ya
// existe en la cuenta y qué filas traen ya el prefijo internacional.
const preview = ref(null);
const previewError = ref('');
// 'skip' = no tocar los leads que ya existen; 'update' = el archivo manda.
const duplicatePolicy = ref('skip');
// El CSV ya normalizado que se enviará si el usuario confirma tras la vista previa.
const preparedFile = ref(null);

// ── file state ────────────────────────────────────────────────────────
const selectedFile = ref(null);
const selectedFileName = ref('');
const importCountry = ref('');
const isParsing = ref(false);
const campaigns = ref([]);

onMounted(async () => {
  try {
    const { data } = await campaignsAPI.getAll();
    campaigns.value = data;
  } catch {
    // module not enabled
  }
});

const importCampaignName = ref('');

// ── mapping state ─────────────────────────────────────────────────────
const fileHeaders = ref([]);
const previewRows = ref([]);
const columnMapping = ref({});

// ── contact field definitions ─────────────────────────────────────────
const CONTACT_FIELDS = [
  {
    value: '__skip',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_SKIP'),
  },
  {
    value: 'name',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_NAME'),
  },
  {
    value: 'first_name',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_FIRST_NAME'),
  },
  {
    value: 'last_name',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_LAST_NAME'),
  },
  {
    value: 'email',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_EMAIL'),
  },
  {
    value: 'phone_number',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_PHONE'),
  },
  {
    value: 'identifier',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_IDENTIFIER'),
  },
  {
    value: 'company',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_COMPANY'),
  },
  {
    value: 'location',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_LOCATION'),
  },
  {
    value: 'campaign',
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FIELD_CAMPAIGN'),
  },
];

const FIELD_SYNONYMS = {
  name: [
    'name',
    'nombre',
    'full name',
    'nombre completo',
    'nombre_completo',
    'fullname',
  ],
  first_name: [
    'first_name',
    'firstname',
    'first name',
    'nombres',
    'primer nombre',
    'given name',
  ],
  last_name: [
    'last_name',
    'lastname',
    'last name',
    'apellido',
    'apellidos',
    'surname',
  ],
  email: [
    'email',
    'correo',
    'mail',
    'e-mail',
    'correo electronico',
    'correo electrónico',
    'email address',
  ],
  phone_number: [
    'phone_number',
    'phone',
    'telefono',
    'teléfono',
    'celular',
    'movil',
    'móvil',
    'cel',
    'tel',
    'mobile',
    'phone number',
    'numero',
    'número',
  ],
  identifier: [
    'identifier',
    'identificador',
    'codigo',
    'código',
    'external_id',
    'id',
  ],
  company: [
    'company',
    'empresa',
    'compania',
    'compañía',
    'organization',
    'org',
  ],
  location: [
    'location',
    'ubicacion',
    'ubicación',
    'ciudad',
    'city',
    'direccion',
    'dirección',
  ],
  campaign: ['campaign', 'campaña', 'campaing', 'lead_campaign'],
};

const autoDetectField = header => {
  const normalized = header.toLowerCase().trim();
  const match = Object.entries(FIELD_SYNONYMS).find(([, synonyms]) =>
    synonyms.includes(normalized)
  );
  return match ? match[0] : '__skip';
};

// ── file parsing ──────────────────────────────────────────────────────
const parseFile = async file => {
  const { read, utils } = await import('xlsx');
  const arrayBuffer = await file.arrayBuffer();
  const workbook = read(arrayBuffer, { type: 'array' });
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  const rows = utils.sheet_to_json(sheet, { header: 1, defval: '' });
  return rows;
};

const buildAndEmit = async () => {
  const { read, utils } = await import('xlsx');
  const arrayBuffer = await selectedFile.value.arrayBuffer();
  const workbook = read(arrayBuffer, { type: 'array' });
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  const rows = utils.sheet_to_json(sheet, { header: 1, defval: '' });

  if (!rows.length) return null;

  const headers = (rows[0] || []).map(String);
  const dataRows = rows.slice(1);

  // active = columns that are not skipped
  const activeCols = headers
    .map((h, i) => ({ i, field: columnMapping.value[h] }))
    .filter(x => x.field && x.field !== '__skip');

  let outHeaders = activeCols.map(x => x.field);
  let outRows = dataRows
    .filter(row => row.some(cell => cell !== ''))
    .map(row => activeCols.map(x => row[x.i] ?? ''));

  // Inject country from dialog selection — overrides any file country column
  if (importCountry.value) {
    const countryObj = countries.find(c => c.id === importCountry.value);
    if (countryObj) {
      const countryColIdx = outHeaders.indexOf('country');
      if (countryColIdx >= 0) {
        outRows = outRows.map(row => {
          const r = [...row];
          r[countryColIdx] = countryObj.name;
          return r;
        });
      } else {
        outHeaders = [...outHeaders, 'country'];
        outRows = outRows.map(row => [...row, countryObj.name]);
      }
    }
  }

  // Inject campaign from dialog selection — overrides any file campaign column
  if (importCampaignName.value) {
    const campaignColIdx = outHeaders.indexOf('campaign');
    if (campaignColIdx >= 0) {
      outRows = outRows.map(row => {
        const r = [...row];
        r[campaignColIdx] = importCampaignName.value;
        return r;
      });
    } else {
      outHeaders = [...outHeaders, 'campaign'];
      outRows = outRows.map(row => [...row, importCampaignName.value]);
    }
  }

  const ws = utils.aoa_to_sheet([outHeaders, ...outRows]);
  const csv = utils.sheet_to_csv(ws);

  const blob = new Blob([csv], { type: 'text/csv' });
  const csvFile = new File([blob], 'import.csv', { type: 'text/csv' });
  return { csvFile, headers: outHeaders, rows: outRows };
};

const runPreview = async () => {
  previewError.value = '';
  const built = await buildAndEmit();
  if (!built) return false;

  preparedFile.value = built.csvFile;
  try {
    const { data } = await ContactAPI.importPreview({
      rows: buildPreviewRows(built.headers, built.rows),
      country: importCountry.value,
    });
    preview.value = data;
    return true;
  } catch (error) {
    previewError.value =
      error.response?.data?.error ??
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREVIEW_ERROR');
    return false;
  }
};

// ── confirm dialog → step transitions ────────────────────────────────
const onConfirm = async () => {
  if (currentStep.value === 'select') {
    if (!selectedFile.value) return;
    isParsing.value = true;
    try {
      const rows = await parseFile(selectedFile.value);
      fileHeaders.value = (rows[0] || []).map(String);
      previewRows.value = rows.slice(1, 4);
      columnMapping.value = Object.fromEntries(
        fileHeaders.value.map(h => [h, autoDetectField(h)])
      );
      currentStep.value = 'mapping';
    } finally {
      isParsing.value = false;
    }
    return;
  }

  if (currentStep.value === 'mapping') {
    isParsing.value = true;
    try {
      if (await runPreview()) currentStep.value = 'preview';
    } finally {
      isParsing.value = false;
    }
    return;
  }

  // Paso 'preview': el usuario ya vio qué se crearía y qué ya existe.
  if (preparedFile.value) {
    emit('import', {
      file: preparedFile.value,
      country: importCountry.value,
      duplicatePolicy: duplicatePolicy.value,
    });
  }
};

const onBack = () => {
  currentStep.value = currentStep.value === 'preview' ? 'mapping' : 'select';
};

// ── file input handlers ───────────────────────────────────────────────
const handleFileClick = () => fileInput.value?.click();

const processFileName = fileName => {
  const lastDotIndex = fileName.lastIndexOf('.');
  const ext = fileName.slice(lastDotIndex);
  const base = fileName.slice(0, lastDotIndex);
  return base.length > 20 ? `${base.slice(0, 20)}...${ext}` : fileName;
};

// Cualquier cambio de archivo invalida la vista previa ya calculada.
const resetPreview = () => {
  preview.value = null;
  previewError.value = '';
  preparedFile.value = null;
  duplicatePolicy.value = 'skip';
};

const handleFileChange = () => {
  const file = fileInput.value?.files[0];
  selectedFile.value = file ?? null;
  selectedFileName.value = file ? processFileName(file.name) : '';
  currentStep.value = 'select';
  resetPreview();
};

const handleRemoveFile = () => {
  selectedFile.value = null;
  selectedFileName.value = '';
  if (fileInput.value) fileInput.value.value = null;
  currentStep.value = 'select';
  resetPreview();
};

// ── computed ──────────────────────────────────────────────────────────
const confirmLabel = computed(() => {
  if (currentStep.value === 'preview') {
    return t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.IMPORT');
  }
  return t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.NEXT');
});

const counts = computed(() => preview.value?.counts ?? {});

// Cuántas filas entrarían realmente con la política elegida.
const importableCount = computed(() =>
  computeImportable(counts.value, duplicatePolicy.value)
);

const isConfirmDisabled = computed(() => {
  if (isImportingContact.value || isParsing.value) return true;
  if (currentStep.value === 'select')
    return !selectedFile.value || !importCountry.value;
  // Nada que importar: todas las filas son duplicadas o inválidas.
  if (currentStep.value === 'preview') return !importableCount.value;
  return false;
});

// Filas cuyo teléfono ya venía con prefijo en el archivo. Se muestran para que
// el usuario las suba sin él: el prefijo lo pone el país seleccionado.
const prefixRows = computed(() => rowsWithPrefix(preview.value));

const duplicateRows = computed(() => rowsAlreadyExisting(preview.value));

const selectedCountryLabel = computed(() => {
  const found = countries.find(c => c.id === importCountry.value);
  return found ? `${found.emoji} ${found.name} ${found.dial_code}` : '';
});

const sampleUrl = computed(
  () => `/api/v1/accounts/${route.params.accountId}/contacts/sample_import`
);

// expose for parent
defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.TITLE')"
    :confirm-button-label="confirmLabel"
    :is-loading="isImportingContact || isParsing"
    :disable-confirm-button="isConfirmDisabled"
    @confirm="onConfirm"
  >
    <template #description>
      <p class="mb-0 text-sm text-n-slate-11">
        {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DESCRIPTION') }}
        <a
          :href="sampleUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="text-n-blue-11"
        >
          {{
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DOWNLOAD_LABEL')
          }}
        </a>
      </p>
    </template>

    <!-- Step 1: file selection -->
    <div v-if="currentStep === 'select'" class="flex flex-col gap-2">
      <div class="flex items-center gap-2">
        <label class="text-sm text-n-slate-12 whitespace-nowrap">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.LABEL') }}
        </label>
        <div class="flex items-center justify-between w-full gap-2">
          <span v-if="selectedFile" class="text-sm text-n-slate-12">
            {{ selectedFileName }}
          </span>
          <Button
            v-if="!selectedFile"
            :label="
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CHOOSE_FILE')
            "
            icon="i-lucide-upload"
            color="slate"
            variant="ghost"
            size="sm"
            class="!w-fit"
            @click="handleFileClick"
          />
          <div v-else class="flex items-center gap-1">
            <Button
              :label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CHANGE')"
              color="slate"
              variant="ghost"
              size="sm"
              @click="handleFileClick"
            />
            <div class="w-px h-3 bg-n-strong" />
            <Button
              icon="i-lucide-trash"
              color="slate"
              variant="ghost"
              size="sm"
              @click="handleRemoveFile"
            />
          </div>
        </div>
      </div>
      <p class="text-xs text-n-slate-10">
        {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.FILE_HINT') }}
      </p>

      <!-- Required country selector -->
      <div class="flex flex-col gap-1 mt-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COUNTRY_LABEL') }}
        </label>
        <select
          v-model="importCountry"
          class="w-full rounded-lg border border-n-weak bg-white dark:bg-n-solid-2 text-sm text-n-slate-12 px-3 py-2 focus:outline-none focus:ring-1 focus:ring-n-brand"
        >
          <option value="" disabled>
            {{
              t(
                'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COUNTRY_PLACEHOLDER'
              )
            }}
          </option>
          <option
            v-for="country in countries"
            :key="country.id"
            :value="country.id"
          >
            {{ country.emoji }} {{ country.name }}
          </option>
        </select>
      </div>

      <!-- Optional campaign selector (only shown when campaigns are available) -->
      <div v-if="campaigns.length" class="flex flex-col gap-1 mt-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CAMPAIGN_LABEL')
          }}
        </label>
        <select
          v-model="importCampaignName"
          class="w-full rounded-lg border border-n-weak bg-white dark:bg-n-solid-2 text-sm text-n-slate-12 px-3 py-2 focus:outline-none focus:ring-1 focus:ring-n-brand"
        >
          <option value="">
            {{
              t(
                'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.CAMPAIGN_PLACEHOLDER'
              )
            }}
          </option>
          <option v-for="c in campaigns" :key="c.id" :value="c.name">
            {{ c.name }}
          </option>
        </select>
      </div>
    </div>

    <!-- Step 2: column mapping -->
    <div v-else-if="currentStep === 'mapping'" class="flex flex-col gap-3">
      <div class="flex items-center gap-2 mb-1">
        <button
          class="flex items-center gap-1 text-xs text-n-slate-11 hover:text-n-slate-12 transition-colors"
          @click="onBack"
        >
          <span class="i-lucide-arrow-left w-3 h-3" />
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.BACK') }}
        </button>
        <span class="text-xs text-n-slate-10">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.MAPPING_HINT') }}
        </span>
      </div>

      <div
        class="max-h-64 overflow-y-auto border border-n-weak rounded-lg divide-y divide-n-weak"
      >
        <!-- Header row -->
        <div class="grid grid-cols-2 gap-3 px-3 py-2 bg-n-alpha-1 sticky top-0">
          <span
            class="text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
          >
            {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COL_FILE') }}
          </span>
          <span
            class="text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
          >
            {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.COL_FIELD') }}
          </span>
        </div>

        <!-- Mapping rows -->
        <div
          v-for="(header, idx) in fileHeaders"
          :key="header"
          class="grid grid-cols-2 gap-3 px-3 py-2 items-center hover:bg-n-alpha-1"
        >
          <div class="min-w-0">
            <p class="text-sm font-medium text-n-slate-12 truncate">
              {{ header }}
            </p>
            <p class="text-xs text-n-slate-10 truncate">
              {{
                previewRows
                  .map(row => row[idx])
                  .filter(v => v !== '' && v != null)
                  .slice(0, 2)
                  .join(', ')
              }}
            </p>
          </div>
          <select
            v-model="columnMapping[header]"
            class="w-full rounded-md border border-n-weak bg-white dark:bg-n-solid-2 text-sm text-n-slate-12 px-2 py-1 focus:outline-none focus:ring-1 focus:ring-n-brand"
          >
            <option
              v-for="field in CONTACT_FIELDS"
              :key="field.value"
              :value="field.value"
            >
              {{ field.label }}
            </option>
          </select>
        </div>
      </div>
    </div>

    <!-- Step 3: preview — qué se crearía y qué ya existe -->
    <div v-else-if="currentStep === 'preview'" class="flex flex-col gap-3">
      <div class="flex items-center gap-2 mb-1">
        <button
          class="flex items-center gap-1 text-xs text-n-slate-11 hover:text-n-slate-12 transition-colors"
          @click="onBack"
        >
          <span class="i-lucide-arrow-left w-3 h-3" />
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.BACK') }}
        </button>
        <span class="text-xs text-n-slate-10">{{ selectedCountryLabel }}</span>
      </div>

      <p v-if="previewError" class="text-sm text-n-ruby-11">
        {{ previewError }}
      </p>

      <!-- Resumen -->
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <div class="rounded-lg border border-n-weak px-3 py-2">
          <p class="text-xs text-n-slate-10">
            {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREVIEW_NEW') }}
          </p>
          <p class="text-lg font-semibold text-n-teal-11">
            {{ counts.nuevas ?? 0 }}
          </p>
        </div>
        <div class="rounded-lg border border-n-weak px-3 py-2">
          <p class="text-xs text-n-slate-10">
            {{
              t(
                'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREVIEW_EXISTING'
              )
            }}
          </p>
          <p class="text-lg font-semibold text-n-amber-11">
            {{ counts.duplicadas_bd ?? 0 }}
          </p>
        </div>
        <div class="rounded-lg border border-n-weak px-3 py-2">
          <p class="text-xs text-n-slate-10">
            {{
              t(
                'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREVIEW_DUP_FILE'
              )
            }}
          </p>
          <p class="text-lg font-semibold text-n-slate-12">
            {{ counts.duplicadas_archivo ?? 0 }}
          </p>
        </div>
        <div class="rounded-lg border border-n-weak px-3 py-2">
          <p class="text-xs text-n-slate-10">
            {{
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREVIEW_INVALID')
            }}
          </p>
          <p class="text-lg font-semibold text-n-ruby-11">
            {{ counts.invalidas ?? 0 }}
          </p>
        </div>
      </div>

      <!-- Aviso de prefijo: el prefijo lo pone el país, no el archivo -->
      <div
        v-if="prefixRows.length"
        class="rounded-lg border border-n-amber-6 bg-n-amber-2 px-3 py-2"
      >
        <p class="text-sm font-medium text-n-amber-11">
          {{
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREFIX_WARNING', {
              count: prefixRows.length,
            })
          }}
        </p>
        <p class="text-xs text-n-slate-11 mt-1">
          {{ t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREFIX_HINT') }}
        </p>
        <ul class="mt-2 space-y-0.5">
          <li
            v-for="row in prefixRows.slice(0, 5)"
            :key="`p-${row.index}`"
            class="text-xs text-n-slate-11 font-mono"
          >
            {{ `${row.phone_original} → ${row.phone}` }}
          </li>
        </ul>
      </div>

      <!-- Qué hacer con los que ya existen -->
      <div v-if="counts.duplicadas_bd" class="flex flex-col gap-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DUPLICATE_LABEL')
          }}
        </label>
        <label class="flex items-start gap-2 text-sm text-n-slate-11">
          <input v-model="duplicatePolicy" type="radio" value="skip" />
          <span>
            {{
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DUPLICATE_SKIP')
            }}
          </span>
        </label>
        <label class="flex items-start gap-2 text-sm text-n-slate-11">
          <input v-model="duplicatePolicy" type="radio" value="update" />
          <span>
            {{
              t(
                'CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.DUPLICATE_UPDATE'
              )
            }}
          </span>
        </label>

        <div
          class="max-h-40 overflow-y-auto border border-n-weak rounded-lg divide-y divide-n-weak"
        >
          <div
            v-for="row in duplicateRows.slice(0, 50)"
            :key="`d-${row.index}`"
            class="px-3 py-1.5 flex items-center justify-between gap-2"
          >
            <span class="text-xs text-n-slate-12 truncate">
              {{ row.name || row.phone || row.email }}
            </span>
            <span class="text-xs text-n-slate-10 font-mono shrink-0">
              {{ row.phone || row.email }}
            </span>
          </div>
        </div>
      </div>

      <p class="text-sm text-n-slate-11">
        {{
          t('CONTACTS_LAYOUT.HEADER.ACTIONS.IMPORT_CONTACT.PREVIEW_SUMMARY', {
            count: importableCount,
          })
        }}
      </p>
    </div>

    <input
      ref="fileInput"
      type="file"
      accept=".xlsx,.xls,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,text/csv"
      class="hidden"
      @change="handleFileChange"
    />
  </Dialog>
</template>
