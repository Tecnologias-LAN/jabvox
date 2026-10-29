<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

defineProps({
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  confirmLabel: { type: String, default: '' },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['confirm', 'close']);

const dialogRef = ref(null);

const open = () => dialogRef.value?.open();
const close = () => dialogRef.value?.close();

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="title"
    :description="description"
    :confirm-button-label="confirmLabel"
    :is-loading="isLoading"
    @confirm="emit('confirm')"
    @close="emit('close')"
  />
</template>
