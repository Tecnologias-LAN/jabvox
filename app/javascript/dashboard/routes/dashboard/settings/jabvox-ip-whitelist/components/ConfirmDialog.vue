<script setup>
import { ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const emit = defineEmits(['confirm']);
const { t } = useI18n();

const dialogRef = ref(null);
const title = ref('');
const description = ref('');
const payload = ref(null);

const open = ({ title: titleText, description: descText, data }) => {
  title.value = titleText;
  description.value = descText;
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
    :confirm-button-label="t('JABVOX_IP_WHITELIST.COMMON.DELETE')"
    :cancel-button-label="t('JABVOX_IP_WHITELIST.COMMON.CANCEL')"
    @confirm="handleConfirm"
  />
</template>
