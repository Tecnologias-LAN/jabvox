<script setup>
import { ref, nextTick } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const emit = defineEmits(['confirm']);

const dialogRef = ref(null);
const title = ref('');
const description = ref('');
const confirmLabel = ref('');
const cancelLabel = ref('');
const payload = ref(null);

const open = ({
  title: titleText,
  description: descText,
  confirmLabel: confirmText,
  cancelLabel: cancelText,
  data,
}) => {
  title.value = titleText;
  description.value = descText;
  confirmLabel.value = confirmText;
  cancelLabel.value = cancelText;
  payload.value = data;
  nextTick(() => dialogRef.value?.open());
};

const handleConfirm = () => {
  emit('confirm', payload.value);
  dialogRef.value?.close();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="title"
    :description="description"
    :confirm-button-label="confirmLabel"
    :cancel-button-label="cancelLabel"
    @confirm="handleConfirm"
  />
</template>
