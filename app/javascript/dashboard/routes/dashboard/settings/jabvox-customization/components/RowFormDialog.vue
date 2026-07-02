<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  saving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const dialogRef = ref(null);
const columns = ref([]);
const editingId = ref(null);
// A flat map of column name -> current field value.
const form = ref({});

const title = computed(() =>
  editingId.value
    ? t('JABVOX_CUSTOMIZATION.DATA.EDIT_TITLE')
    : t('JABVOX_CUSTOMIZATION.DATA.NEW_TITLE')
);

// Required text/number/date/select fields must be filled; booleans always valid.
const isValid = computed(() =>
  columns.value.every(column => {
    if (!column.required_jabvox || column.column_type_jabvox === 'boolean') {
      return true;
    }
    const value = form.value[column.name_jabvox];
    return value !== null && value !== undefined && String(value).trim() !== '';
  })
);

const selectOptions = column =>
  (column.options_jabvox || []).map(opt => ({ value: opt, label: opt }));

const open = ({ columns: cols, row }) => {
  columns.value = cols || [];
  editingId.value = row?.id || null;
  const initial = {};
  columns.value.forEach(column => {
    const stored = row?.data?.[column.name_jabvox];
    initial[column.name_jabvox] =
      column.column_type_jabvox === 'boolean'
        ? Boolean(stored)
        : (stored ?? '');
  });
  form.value = initial;
  nextTick(() => dialogRef.value?.open());
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (!isValid.value) return;
  // Send exactly the defined columns; the server sanitizes and coerces again.
  const values = {};
  columns.value.forEach(column => {
    values[column.name_jabvox] = form.value[column.name_jabvox];
  });
  emit('submit', { rowId: editingId.value, values });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('JABVOX_CUSTOMIZATION.DATA.FORM_DESCRIPTION')"
    :confirm-button-label="t('JABVOX_CUSTOMIZATION.DATA.SAVE')"
    :cancel-button-label="t('JABVOX_CUSTOMIZATION.DATA.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="saving"
    width="lg"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <p v-if="!columns.length" class="text-sm text-n-slate-11">
        {{ t('JABVOX_CUSTOMIZATION.DATA.NO_COLUMNS_FORM') }}
      </p>

      <template v-for="column in columns" :key="column.id">
        <!-- Boolean -> switch -->
        <div
          v-if="column.column_type_jabvox === 'boolean'"
          class="flex items-center justify-between rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ column.label_jabvox }}
          </span>
          <Switch v-model="form[column.name_jabvox]" />
        </div>

        <!-- Select -> dropdown of configured options -->
        <div
          v-else-if="column.column_type_jabvox === 'select'"
          class="flex flex-col gap-1.5"
        >
          <span class="text-sm font-medium text-n-slate-12">
            {{ column.label_jabvox }}
          </span>
          <Select
            v-model="form[column.name_jabvox]"
            :options="selectOptions(column)"
            :placeholder="t('JABVOX_CUSTOMIZATION.DATA.SELECT_OPTION')"
          />
        </div>

        <!-- Date -->
        <Input
          v-else-if="column.column_type_jabvox === 'date'"
          v-model="form[column.name_jabvox]"
          type="date"
          :label="column.label_jabvox"
        />

        <!-- Integer / Float -->
        <Input
          v-else-if="
            column.column_type_jabvox === 'integer' ||
            column.column_type_jabvox === 'float'
          "
          v-model="form[column.name_jabvox]"
          type="number"
          :label="column.label_jabvox"
        />

        <!-- Text (default) -->
        <Input
          v-else
          v-model="form[column.name_jabvox]"
          :label="column.label_jabvox"
        />
      </template>
    </div>
  </Dialog>
</template>
