<script setup>
import { ref, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import DashboardForm from './DashboardForm.vue';

const props = defineProps({
  open: {
    type: Boolean,
    default: false,
  },
  folderId: {
    type: [Number, String, null],
    default: null,
  },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();
const store = useAnalyticsDashboardsStore();
const { showError } = useAnalyticsError();

const formRef = ref(null);
const saving = ref(false);

const emptyForm = () => ({
  nameJabvox: '',
  descriptionJabvox: '',
  folderId: props.folderId || null,
});

const form = reactive(emptyForm());

// Aplica el cambio de un campo al objeto reactive (mutación in-place, así vuelidate
// —que valida sobre este mismo objeto— ve el valor y no marca "campo requerido").
const onFieldChange = ({ key, value }) => {
  form[key] = value;
};

watch(
  () => props.open,
  isOpen => {
    if (!isOpen) return;
    Object.assign(form, emptyForm());
  },
  { immediate: true }
);

const handleSave = async () => {
  const valid = await formRef.value?.v$.$validate();
  if (!valid) return;

  saving.value = true;
  try {
    const created = await store.create({
      name_jabvox: form.nameJabvox,
      description_jabvox: form.descriptionJabvox,
      folder_id: form.folderId,
    });
    useAlert(t('JABVOX_ANALYTICS.DASHBOARDS.SAVED'));
    emit('saved', created);
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.DASHBOARDS.SAVE_ERROR');
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
        class="w-full max-w-lg rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <div class="mb-4 flex items-center justify-between">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('JABVOX_ANALYTICS.DASHBOARDS.FORM.TITLE') }}
          </h3>
          <button
            type="button"
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <DashboardForm
          ref="formRef"
          :model-value="form"
          @field-change="onFieldChange"
        />

        <div class="mt-6 flex items-center justify-end gap-3">
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12"
            @click="emit('close')"
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
            {{ t('JABVOX_ANALYTICS.COMMON.CREATE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
