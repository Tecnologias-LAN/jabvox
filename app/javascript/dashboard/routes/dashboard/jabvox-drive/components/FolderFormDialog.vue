<script setup>
import { ref, watch, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  // Carpeta a editar; si es null => crear.
  folder: { type: Object, default: null },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();
const dialogRef = ref(null);
const name = ref('');

const isEdit = computed(() => !!props.folder);
const title = computed(() =>
  isEdit.value
    ? t('JABVOX_DRIVE.FOLDER.RENAME_TITLE')
    : t('JABVOX_DRIVE.FOLDER.CREATE_TITLE')
);
const confirmLabel = computed(() =>
  isEdit.value ? t('JABVOX_DRIVE.FOLDER.SAVE') : t('JABVOX_DRIVE.FOLDER.CREATE')
);

const open = async () => {
  name.value = props.folder?.name || '';
  dialogRef.value?.open();
  await nextTick();
};

const close = () => {
  dialogRef.value?.close();
};

watch(
  () => props.folder,
  () => {
    name.value = props.folder?.name || '';
  }
);

const onConfirm = () => {
  const trimmed = name.value.trim();
  if (!trimmed) return;
  emit('submit', { name: trimmed });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    :confirm-button-label="confirmLabel"
    :is-loading="isLoading"
    :disable-confirm-button="!name.trim()"
    @confirm="onConfirm"
    @close="emit('close')"
  >
    <Input
      v-model="name"
      :label="t('JABVOX_DRIVE.FOLDER.NAME_LABEL')"
      :placeholder="t('JABVOX_DRIVE.FOLDER.NAME_PLACEHOLDER')"
      autofocus
    />
  </Dialog>
</template>
