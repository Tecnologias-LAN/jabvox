<script setup>
import { ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const emit = defineEmits(['submit']);
const { t } = useI18n();

const dialogRef = ref(null);
const title = ref('');
const value = ref('');
const payload = ref(null);

const open = ({ title: titleText, initialValue = '', data }) => {
  title.value = titleText;
  value.value = initialValue;
  payload.value = data;
  nextTick(() => dialogRef.value?.open());
};

const handleConfirm = () => {
  emit('submit', { value: value.value.trim(), data: payload.value });
  dialogRef.value?.close();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :confirm-button-label="t('JABVOX_WA_FLOWS.CONFIRM.OK')"
    :cancel-button-label="t('JABVOX_WA_FLOWS.CONFIRM.CANCEL')"
    :disable-confirm-button="!value.trim()"
    @confirm="handleConfirm"
  >
    <Input v-model="value" autofocus />
  </Dialog>
</template>
