<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import affiliatePortalAPI from '../../api/jabvox/affiliatePortal';

const { t } = useI18n();

const isLoading = ref(false);
const successMsg = ref('');
const errorMsg = ref('');
const fileInput = ref(null);
const selectedFile = ref(null);
const result = ref(null);

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

const onSubmit = async () => {
  if (!selectedFile.value) {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.BULK_SELECT_FILE');
    return;
  }
  errorMsg.value = '';
  successMsg.value = '';
  result.value = null;
  isLoading.value = true;
  try {
    const formData = new FormData();
    formData.append('file', selectedFile.value);
    const { data } = await affiliatePortalAPI.importCsv(formData);
    result.value = data;
    successMsg.value = t('JABVOX_AFFILIATE_PORTAL.BULK_SUCCESS', {
      ok: data.rows_ok,
      failed: data.rows_failed,
    });
    clearFile();
  } catch (err) {
    errorMsg.value =
      err.response?.data?.error ??
      t('JABVOX_AFFILIATE_PORTAL.BULK_ERROR_DEFAULT');
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <div class="p-6 sm:p-8 max-w-xl">
    <h2 class="text-lg font-semibold text-n-slate-12 mb-1">
      {{ t('JABVOX_AFFILIATE_PORTAL.BULK_TITLE') }}
    </h2>
    <p class="text-sm text-n-slate-11 mb-6">
      {{ t('JABVOX_AFFILIATE_PORTAL.BULK_SUBTITLE') }}
      {{ t('JABVOX_AFFILIATE_PORTAL.BULK_COLUMNS_HINT') }}
      <code class="text-xs font-mono bg-n-alpha-black2 px-1 rounded">
        name, email, phone, country
      </code>
      {{ t('JABVOX_AFFILIATE_PORTAL.BULK_MAX_HINT') }}
    </p>

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
