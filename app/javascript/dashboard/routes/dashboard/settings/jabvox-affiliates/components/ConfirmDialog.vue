<script setup>
import { ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const emit = defineEmits(['confirm']);
const { t } = useI18n();

const dialogRef = ref(null);
const title = ref('');
const description = ref('');
const confirmLabel = ref('');
const payload = ref(null);

// open({ title, description, confirmLabel, data }) — generic accept/cancel.
const open = ({
  title: titleText,
  description: descText,
  confirmLabel: label,
  data,
}) => {
  title.value = titleText;
  description.value = descText;
  confirmLabel.value = label || t('JABVOX_AFFILIATES.COMMON.DELETE');
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
    :cancel-button-label="t('JABVOX_AFFILIATES.COMMON.CANCEL')"
    @confirm="handleConfirm"
  />
</template>
