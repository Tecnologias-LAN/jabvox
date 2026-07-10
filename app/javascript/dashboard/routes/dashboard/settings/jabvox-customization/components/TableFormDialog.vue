<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['submit']);
const { t } = useI18n();

const dialogRef = ref(null);
const mode = ref('create'); // 'create' | 'edit'
const editingId = ref(null);
// multi = the table holds MANY rows per lead (Asesorías, Casos…) instead of
// one. Only choosable at creation; changing kind after data exists is unsafe.
const form = ref({ name_jabvox: '', description_jabvox: '', multi: false });

const title = computed(() =>
  mode.value === 'edit'
    ? t('JABVOX_CUSTOMIZATION.TABLES.EDIT_TITLE')
    : t('JABVOX_CUSTOMIZATION.TABLES.NEW')
);

const isValid = computed(() => form.value.name_jabvox.trim().length > 0);

const openCreate = () => {
  mode.value = 'create';
  editingId.value = null;
  form.value = { name_jabvox: '', description_jabvox: '', multi: false };
  nextTick(() => dialogRef.value?.open());
};

const openEdit = table => {
  mode.value = 'edit';
  editingId.value = table.id;
  form.value = {
    name_jabvox: table.name_jabvox,
    description_jabvox: table.description_jabvox || '',
    multi: table.kind_jabvox === 'multi',
  };
  nextTick(() => dialogRef.value?.open());
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (!isValid.value) return;
  emit('submit', {
    mode: mode.value,
    id: editingId.value,
    values: {
      name_jabvox: form.value.name_jabvox.trim(),
      description_jabvox: form.value.description_jabvox.trim(),
      // Kind is only set on create; never change an existing table's kind.
      ...(mode.value === 'create'
        ? { kind_jabvox: form.value.multi ? 'multi' : 'single' }
        : {}),
    },
  });
};

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('JABVOX_CUSTOMIZATION.TABLES.FORM_DESCRIPTION')"
    :confirm-button-label="t('JABVOX_CUSTOMIZATION.TABLES.SAVE')"
    :cancel-button-label="t('JABVOX_CUSTOMIZATION.TABLES.CANCEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="lg"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name_jabvox"
        :label="t('JABVOX_CUSTOMIZATION.TABLES.NAME_LABEL')"
        :placeholder="t('JABVOX_CUSTOMIZATION.TABLES.NAME_PLACEHOLDER')"
        autofocus
      />
      <Input
        v-model="form.description_jabvox"
        :label="t('JABVOX_CUSTOMIZATION.TABLES.DESCRIPTION_LABEL')"
        :placeholder="t('JABVOX_CUSTOMIZATION.TABLES.DESCRIPTION_PLACEHOLDER')"
      />
      <div
        v-if="mode === 'create'"
        class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <div class="flex flex-col">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_CUSTOMIZATION.TABLES.MULTI_LABEL') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('JABVOX_CUSTOMIZATION.TABLES.MULTI_HINT') }}
          </span>
        </div>
        <Switch v-model="form.multi" />
      </div>
      <p v-else-if="form.multi" class="text-xs text-n-slate-10">
        {{ t('JABVOX_CUSTOMIZATION.TABLES.MULTI_LOCKED') }}
      </p>
    </div>
  </Dialog>
</template>
