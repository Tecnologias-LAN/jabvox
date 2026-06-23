<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const COLUMN_TYPES = ['text', 'integer', 'float', 'boolean', 'date', 'select'];

const { t } = useI18n();

const dialogRef = ref(null);
const mode = ref('create');
const editingId = ref(null);

const emptyForm = () => ({
  name_jabvox: '',
  label_jabvox: '',
  column_type_jabvox: 'text',
  required_jabvox: false,
  options_text: '',
});
const form = ref(emptyForm());

const typeOptions = computed(() =>
  COLUMN_TYPES.map(type => ({
    value: type,
    label: t(`JABVOX_CUSTOMIZATION.COLUMNS.TYPES.${type}`),
  }))
);

const title = computed(() =>
  mode.value === 'edit'
    ? t('JABVOX_CUSTOMIZATION.COLUMNS.EDIT_TITLE')
    : t('JABVOX_CUSTOMIZATION.COLUMNS.NEW')
);

const isSelect = computed(() => form.value.column_type_jabvox === 'select');

const isValid = computed(
  () =>
    form.value.name_jabvox.trim().length > 0 &&
    form.value.label_jabvox.trim().length > 0 &&
    (!isSelect.value || form.value.options_text.trim().length > 0)
);

const openCreate = () => {
  mode.value = 'create';
  editingId.value = null;
  form.value = emptyForm();
  nextTick(() => dialogRef.value?.open());
};

const openEdit = col => {
  mode.value = 'edit';
  editingId.value = col.id;
  form.value = {
    name_jabvox: col.name_jabvox,
    label_jabvox: col.label_jabvox,
    column_type_jabvox: col.column_type_jabvox,
    required_jabvox: col.required_jabvox,
    options_text: (col.options_jabvox || []).join(', '),
  };
  nextTick(() => dialogRef.value?.open());
};

const close = () => dialogRef.value?.close();

const parseOptions = text =>
  text
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

const handleConfirm = () => {
  if (!isValid.value) return;
  const values = {
    name_jabvox: form.value.name_jabvox.trim(),
    label_jabvox: form.value.label_jabvox.trim(),
    column_type_jabvox: form.value.column_type_jabvox,
    required_jabvox: form.value.required_jabvox,
  };
  if (isSelect.value) {
    values.options_jabvox = parseOptions(form.value.options_text);
  }
  emit('submit', { mode: mode.value, id: editingId.value, values });
};

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('JABVOX_CUSTOMIZATION.COLUMNS.FORM_DESCRIPTION')"
    :confirm-button-label="t('JABVOX_CUSTOMIZATION.COLUMNS.SAVE')"
    :cancel-button-label="t('JABVOX_CUSTOMIZATION.COLUMNS.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="lg"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Input
          v-model="form.label_jabvox"
          :label="t('JABVOX_CUSTOMIZATION.COLUMNS.DISPLAY_LABEL')"
          :placeholder="t('JABVOX_CUSTOMIZATION.COLUMNS.DISPLAY_PLACEHOLDER')"
          autofocus
        />
        <Input
          v-model="form.name_jabvox"
          :label="t('JABVOX_CUSTOMIZATION.COLUMNS.INTERNAL_NAME_LABEL')"
          :placeholder="
            t('JABVOX_CUSTOMIZATION.COLUMNS.INTERNAL_NAME_PLACEHOLDER')
          "
          :message="t('JABVOX_CUSTOMIZATION.COLUMNS.INTERNAL_NAME_HINT')"
        />
      </div>

      <div class="flex flex-col gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_CUSTOMIZATION.COLUMNS.TYPE_LABEL') }}
        </span>
        <Select v-model="form.column_type_jabvox" :options="typeOptions" />
      </div>

      <Input
        v-if="isSelect"
        v-model="form.options_text"
        :label="t('JABVOX_CUSTOMIZATION.COLUMNS.OPTIONS_LABEL')"
        :placeholder="t('JABVOX_CUSTOMIZATION.COLUMNS.OPTIONS_PLACEHOLDER')"
      />

      <div
        class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <div class="flex flex-col">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_CUSTOMIZATION.COLUMNS.REQUIRED_LABEL') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('JABVOX_CUSTOMIZATION.COLUMNS.REQUIRED_HINT') }}
          </span>
        </div>
        <Switch v-model="form.required_jabvox" />
      </div>
    </div>
  </Dialog>
</template>
