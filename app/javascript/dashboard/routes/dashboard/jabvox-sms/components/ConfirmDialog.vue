<script setup>
import { ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  // 'alert' (red, destructive) or 'edit' (brand, neutral confirm).
  type: { type: String, default: 'alert' },
  confirmLabel: { type: String, default: '' },
});

const emit = defineEmits(['confirm']);
const { t } = useI18n();

const dialogRef = ref(null);
const title = ref('');
const description = ref('');
const payload = ref(null);
const overrideLabel = ref('');

const open = ({
  title: titleText,
  description: descText,
  data,
  confirmLabel,
}) => {
  title.value = titleText;
  description.value = descText;
  payload.value = data;
  overrideLabel.value = confirmLabel || '';
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
    :type="type"
    :title="title"
    :description="description"
    :confirm-button-label="
      overrideLabel || props.confirmLabel || t('JABVOX_SMS.COMMON.DELETE')
    "
    :cancel-button-label="t('JABVOX_SMS.COMMON.CANCEL')"
    @confirm="handleConfirm"
  />
</template>
