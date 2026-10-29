<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  file: { type: Object, default: null },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();
const dialogRef = ref(null);
const filename = ref('');

const open = () => {
  filename.value = props.file?.filename || '';
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

watch(
  () => props.file,
  () => {
    filename.value = props.file?.filename || '';
  }
);

const onConfirm = () => {
  const trimmed = filename.value.trim();
  if (!trimmed) return;
  emit('submit', { filename: trimmed });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('JABVOX_DRIVE.FILE.RENAME_TITLE')"
    :is-loading="isLoading"
    :disable-confirm-button="!filename.trim()"
    @confirm="onConfirm"
    @close="emit('close')"
  >
    <Input
      v-model="filename"
      :label="t('JABVOX_DRIVE.FILE.RENAME_LABEL')"
      autofocus
    />
  </Dialog>
</template>
