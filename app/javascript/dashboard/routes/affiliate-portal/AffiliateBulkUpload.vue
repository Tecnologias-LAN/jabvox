<script setup>
import { ref, computed, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import affiliatePortalAPI from '../../api/jabvox/affiliatePortal';
import countries from 'shared/constants/countries.js';

const { t } = useI18n();

const isLoading = ref(false);
const successMsg = ref('');
const errorMsg = ref('');
const fileInput = ref(null);
const selectedFile = ref(null);
const result = ref(null);
// País de los números del archivo: de él sale el prefijo. Obligatorio.
const country = ref('');

const dialCode = computed(
  () => countries.find(c => c.id === country.value)?.dial_code ?? ''
);

const onFileChange = e => {
  const file = e.target.files[0];
  if (file && file.name.endsWith('.csv')) {
    selectedFile.value = file;
    errorMsg.value = '';
  } else {
    selectedFile.value = null;
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.BULK_CSV_ONLY');
  }
};

const clearFile = () => {
  selectedFile.value = null;
  result.value = null;
  successMsg.value = '';
  errorMsg.value = '';
  if (fileInput.value) fileInput.value.value = '';
};

let pollTimer = null;

const stopPolling = () => {
  if (pollTimer) clearTimeout(pollTimer);
  pollTimer = null;
};

// Consulta el avance cada 2 s hasta que la importación termina. Se detiene sola
// al salir de la pantalla para no dejar peticiones colgando.
const pollImport = async id => {
  try {
    const { data } = await affiliatePortalAPI.getImport(id);
    result.value = data;
    if (data.status === 'processing') {
      pollTimer = setTimeout(() => pollImport(id), 2000);
      return;
    }
    isLoading.value = false;
    if (data.status === 'failed') {
      errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.BULK_ERROR_DEFAULT');
      return;
    }
    successMsg.value = t('JABVOX_AFFILIATE_PORTAL.BULK_SUCCESS', {
      ok: data.rows_ok,
      duplicated: data.rows_duplicated,
      failed: data.rows_failed,
    });
  } catch {
    isLoading.value = false;
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.BULK_ERROR_DEFAULT');
  }
};

onUnmounted(stopPolling);

const onSubmit = async () => {
  if (!selectedFile.value) {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.BULK_SELECT_FILE');
    return;
  }
  if (!country.value) {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.BULK_SELECT_COUNTRY');
    return;
  }
  errorMsg.value = '';
  successMsg.value = '';
  result.value = null;
  isLoading.value = true;
  try {
    const formData = new FormData();
    formData.append('file', selectedFile.value);
    formData.append('country', country.value);
    const { data } = await affiliatePortalAPI.importCsv(formData);
    // clearFile() borra el resultado, así que el resumen se guarda después.
    clearFile();
    result.value = data;
    // El backend responde 202 y procesa en segundo plano: se consulta el avance
    // hasta que termine.
    pollImport(data.id);
  } catch (err) {
    const code = err.response?.data?.error;
    const known = {
      import_in_progress: 'BULK_ERROR_IN_PROGRESS',
      country_required: 'BULK_SELECT_COUNTRY',
      file_too_large: 'BULK_ERROR_TOO_LARGE',
      file_empty: 'BULK_ERROR_EMPTY',
      too_many_rows: 'BULK_ERROR_TOO_MANY',
    }[code];
    errorMsg.value = t(
      `JABVOX_AFFILIATE_PORTAL.${known ?? 'BULK_ERROR_DEFAULT'}`,
      { max: err.response?.data?.max }
    );
    isLoading.value = false;
  }
};
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="p-6 sm:p-8 max-w-xl">
    <h2 class="text-lg font-semibold text-n-slate-12 mb-1">
      {{ t('JABVOX_AFFILIATE_PORTAL.BULK_TITLE') }}
    </h2>
    <p class="text-sm text-n-slate-11 mb-6">
      {{ t('JABVOX_AFFILIATE_PORTAL.BULK_SUBTITLE') }}
      {{ t('JABVOX_AFFILIATE_PORTAL.BULK_COLUMNS_HINT') }}
      <code class="text-xs font-mono bg-n-alpha-black2 px-1 rounded">
        name, email, phone
      </code>
      {{ t('JABVOX_AFFILIATE_PORTAL.BULK_MAX_HINT') }}
    </p>

    <div class="mb-4">
      <label class="block text-sm font-medium text-n-slate-12 mb-1.5">
        {{ t('JABVOX_AFFILIATE_PORTAL.BULK_COUNTRY_LABEL') }}
        <span class="text-n-ruby-9">*</span>
      </label>
      <select
        v-model="country"
        class="w-full h-9 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
      >
        <option value="" disabled>
          {{ t('JABVOX_AFFILIATE_PORTAL.BULK_COUNTRY_PLACEHOLDER') }}
        </option>
        <option v-for="c in countries" :key="c.id" :value="c.id">
          {{ c.emoji }} {{ c.name }} ({{ c.dial_code }})
        </option>
      </select>
      <p class="mt-1 text-xs text-n-slate-10">
        {{
          t('JABVOX_AFFILIATE_PORTAL.BULK_COUNTRY_HINT', {
            prefix: dialCode || '—',
          })
        }}
      </p>
    </div>

    <div
      class="rounded-xl border-2 border-dashed border-n-weak bg-n-surface-2 p-6 text-center cursor-pointer hover:border-n-brand/50 transition-colors"
      @click="fileInput?.click()"
    >
      <span
        class="i-lucide-upload-cloud size-8 text-n-slate-10 mx-auto block mb-2"
      />
      <p class="text-sm text-n-slate-11">
        {{
          selectedFile
            ? selectedFile.name
            : t('JABVOX_AFFILIATE_PORTAL.BULK_DROP_HINT')
        }}
      </p>
      <input
        ref="fileInput"
        type="file"
        accept=".csv"
        class="hidden"
        @change="onFileChange"
      />
    </div>

    <div v-if="selectedFile" class="mt-3 flex items-center gap-2">
      <span class="i-lucide-file-text size-4 text-n-brand" />
      <span class="text-sm text-n-slate-12 flex-1 truncate">
        {{ selectedFile.name }}
      </span>
      <button
        class="text-n-slate-10 hover:text-n-ruby-9 transition-colors"
        @click="clearFile"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>

    <p
      v-if="successMsg"
      class="mt-4 text-sm text-n-teal-11 rounded-lg bg-n-teal-3 px-3 py-2"
    >
      {{ successMsg }}
    </p>
    <p
      v-if="errorMsg"
      class="mt-4 text-sm text-n-ruby-9 rounded-lg bg-n-ruby-3 px-3 py-2"
    >
      {{ errorMsg }}
    </p>

    <div
      v-if="result"
      class="mt-4 rounded-xl border border-n-weak bg-n-surface-2 p-4 space-y-2"
    >
      <div v-if="result.status === 'processing'" class="space-y-1">
        <div class="flex justify-between text-xs text-n-slate-11">
          <span>{{ t('JABVOX_AFFILIATE_PORTAL.BULK_PROCESSING') }}</span>
          <span>{{ result.rows_processed }} / {{ result.rows_total }}</span>
        </div>
        <div class="h-1.5 rounded-full bg-n-alpha-black2 overflow-hidden">
          <div
            class="h-full bg-n-brand transition-all"
            :style="{ width: `${result.progress}%` }"
          />
        </div>
      </div>

      <div class="flex justify-between text-sm">
        <span class="text-n-slate-11">
          {{ t('JABVOX_AFFILIATE_PORTAL.BULK_RESULT_TOTAL') }}
        </span>
        <span class="font-medium text-n-slate-12">{{ result.rows_total }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-n-slate-11">
          {{ t('JABVOX_AFFILIATE_PORTAL.BULK_RESULT_OK') }}
        </span>
        <span class="font-medium text-n-teal-11">{{ result.rows_ok }}</span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-n-slate-11">
          {{ t('JABVOX_AFFILIATE_PORTAL.BULK_RESULT_DUPLICATED') }}
        </span>
        <span class="font-medium text-n-amber-11">
          {{ result.rows_duplicated }}
        </span>
      </div>
      <div class="flex justify-between text-sm">
        <span class="text-n-slate-11">
          {{ t('JABVOX_AFFILIATE_PORTAL.BULK_RESULT_FAILED') }}
        </span>
        <span class="font-medium text-n-ruby-9">{{ result.rows_failed }}</span>
      </div>
    </div>

    <button
      type="button"
      :disabled="isLoading || !selectedFile"
      class="mt-6 h-10 px-6 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
      @click="onSubmit"
    >
      {{
        isLoading
          ? t('JABVOX_AFFILIATE_PORTAL.BULK_IMPORTING')
          : t('JABVOX_AFFILIATE_PORTAL.BULK_IMPORT')
      }}
    </button>
  </div>
</template>
