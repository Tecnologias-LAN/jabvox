<script setup>
import { ref, reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import DataSourceForm from './DataSourceForm.vue';
import TestConnectionButton from './TestConnectionButton.vue';
import TestConnectionResult from './TestConnectionResult.vue';

const props = defineProps({
  open: {
    type: Boolean,
    default: false,
  },
  dataSource: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();
const store = useAnalyticsDataSourcesStore();
const { showError } = useAnalyticsError();

const formRef = ref(null);
const testResult = ref(null);
const saving = ref(false);

const emptyForm = () => ({
  nameJabvox: '',
  engineJabvox: 'postgresql',
  hostJabvox: '',
  portJabvox: '',
  databaseJabvox: '',
  usernameJabvox: '',
  passwordJabvox: '',
  sqlitePathJabvox: '',
  allowPrivateNetworkJabvox: false,
  maxRowsJabvox: '',
  queryTimeoutMsJabvox: '',
});

const form = reactive(emptyForm());

const isEdit = computed(() => Boolean(props.dataSource?.id));

const resetForm = () => {
  Object.assign(form, emptyForm());
  testResult.value = null;
  if (props.dataSource?.id) {
    Object.keys(form).forEach(key => {
      if (props.dataSource[key] !== undefined && key !== 'passwordJabvox') {
        form[key] = props.dataSource[key];
      }
    });
  }
};

watch(
  () => props.open,
  isOpen => {
    if (isOpen) resetForm();
  },
  { immediate: true }
);

// snake_case payload expected by the API.
const buildPayload = () => {
  const payload = {
    name_jabvox: form.nameJabvox,
    engine_jabvox: form.engineJabvox,
    allow_private_network_jabvox: form.allowPrivateNetworkJabvox,
  };
  if (form.maxRowsJabvox !== '') payload.max_rows_jabvox = form.maxRowsJabvox;
  if (form.queryTimeoutMsJabvox !== '')
    payload.query_timeout_ms_jabvox = form.queryTimeoutMsJabvox;

  if (form.engineJabvox === 'sqlite') {
    payload.sqlite_path_jabvox = form.sqlitePathJabvox;
  } else {
    payload.host_jabvox = form.hostJabvox;
    payload.port_jabvox = form.portJabvox;
    payload.database_jabvox = form.databaseJabvox;
    payload.username_jabvox = form.usernameJabvox;
    if (form.passwordJabvox) payload.password_jabvox = form.passwordJabvox;
  }
  return payload;
};

const handleClose = () => emit('close');

const handleSave = async () => {
  // Only the name is required; connection can be saved untested.
  const valid = formRef.value?.validate();
  if (!valid) return;

  saving.value = true;
  try {
    if (isEdit.value) {
      await store.update(props.dataSource.id, buildPayload());
    } else {
      await store.create(buildPayload());
    }
    useAlert(t('JABVOX_ANALYTICS.DATA_SOURCES.SAVED'));
    emit('saved');
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.DATA_SOURCES.SAVE_ERROR');
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div>
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-n-alpha-3 p-4 pt-16"
    >
      <div
        class="w-full max-w-xl rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <div class="mb-4 flex items-center justify-between">
          <h3 class="text-base font-medium text-n-slate-12">
            {{
              isEdit
                ? t('JABVOX_ANALYTICS.COMMON.EDIT')
                : t('JABVOX_ANALYTICS.DATA_SOURCES.NEW')
            }}
          </h3>
          <button
            type="button"
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
            @click="handleClose"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <DataSourceForm ref="formRef" v-model="form" :is-edit="isEdit" />

        <!-- Optional connection test — does not block saving -->
        <div class="mt-5 flex flex-col gap-3 border-t border-n-weak pt-4">
          <div class="flex items-center justify-between gap-3">
            <span class="text-xs text-n-slate-10">
              {{ t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.TEST_OPTIONAL') }}
            </span>
            <TestConnectionButton
              :data-source-id="isEdit ? dataSource.id : null"
              :payload="form"
              @result="testResult = $event"
            />
          </div>
          <TestConnectionResult :result="testResult" />
        </div>

        <div class="mt-6 flex items-center justify-end gap-3">
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
            @click="handleClose"
          >
            {{ t('JABVOX_ANALYTICS.COMMON.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="saving"
            @click="handleSave"
          >
            <span
              v-if="saving"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            {{
              isEdit
                ? t('JABVOX_ANALYTICS.COMMON.SAVE')
                : t('JABVOX_ANALYTICS.COMMON.CREATE')
            }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
