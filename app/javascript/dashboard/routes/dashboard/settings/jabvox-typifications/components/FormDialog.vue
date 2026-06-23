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
const editingId = ref(null);
const form = ref({ name: '', description: '', is_active: true });

const title = computed(() =>
  editingId.value
    ? t('JABVOX_CLICK_TO_CALL.SETTINGS.EDIT_TITLE')
    : t('JABVOX_CLICK_TO_CALL.SETTINGS.NEW')
);
const isValid = computed(() => form.value.name.trim().length > 0);

const openCreate = () => {
  editingId.value = null;
  form.value = { name: '', description: '', is_active: true };
  nextTick(() => dialogRef.value?.open());
};

const openEdit = tp => {
  editingId.value = tp.id;
  form.value = {
    name: tp.name || '',
    description: tp.description || '',
    is_active: tp.is_active ?? true,
  };
  nextTick(() => dialogRef.value?.open());
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (!isValid.value) return;
  emit('submit', {
    id: editingId.value,
    values: {
      name: form.value.name.trim(),
      description: form.value.description.trim(),
      is_active: form.value.is_active,
    },
  });
};

defineExpose({ openCreate, openEdit, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :description="t('JABVOX_CLICK_TO_CALL.SETTINGS.FORM_SUBTITLE')"
    :confirm-button-label="t('JABVOX_CLICK_TO_CALL.SETTINGS.SAVE')"
    :cancel-button-label="t('JABVOX_CLICK_TO_CALL.SETTINGS.CANCEL_LABEL')"
    :disable-confirm-button="!isValid"
    :is-loading="isSaving"
    width="lg"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('JABVOX_CLICK_TO_CALL.SETTINGS.NAME')"
        :placeholder="t('JABVOX_CLICK_TO_CALL.SETTINGS.NAME_PLACEHOLDER')"
        autofocus
      />
      <Input
        v-model="form.description"
        :label="t('JABVOX_CLICK_TO_CALL.SETTINGS.DESCRIPTION')"
        :placeholder="
          t('JABVOX_CLICK_TO_CALL.SETTINGS.DESCRIPTION_PLACEHOLDER')
        "
      />
      <div
        class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-alpha-1 px-4 py-3"
      >
        <div class="flex flex-col">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.ACTIVE') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('JABVOX_CLICK_TO_CALL.SETTINGS.ACTIVE_HINT') }}
          </span>
        </div>
        <Switch v-model="form.is_active" />
      </div>
    </div>
  </Dialog>
</template>
