<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

defineProps({
  // Carpetas destino disponibles.
  folders: { type: Array, default: () => [] },
  // Cantidad de elementos a mover (para masivo). 1 por defecto.
  count: { type: Number, default: 1 },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();
const dialogRef = ref(null);
const targetFolderId = ref('');

const open = () => {
  targetFolderId.value = '';
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const onConfirm = () => {
  // Cadena vacía => mover a raíz (folderId null).
  const folderId =
    targetFolderId.value === '' ? null : Number(targetFolderId.value);
  emit('submit', { folderId });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('JABVOX_DRIVE.FILE.MOVE_TITLE')"
    :is-loading="isLoading"
    @confirm="onConfirm"
    @close="emit('close')"
  >
    <label class="flex flex-col gap-1.5 text-sm text-n-slate-11">
      <span>
        {{ t('JABVOX_DRIVE.FILE.MOVE_LABEL') }}
        <span v-if="count > 1" class="text-n-slate-10">
          {{ t('JABVOX_DRIVE.BULK.SELECTED', { count }) }}
        </span>
      </span>
      <select
        v-model="targetFolderId"
        class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 outline-none transition-colors focus:border-n-brand focus-visible:ring-2 focus-visible:ring-n-brand/40"
      >
        <option value="">{{ t('JABVOX_DRIVE.FILE.MOVE_ROOT') }}</option>
        <option v-for="folder in folders" :key="folder.id" :value="folder.id">
          {{ folder.name }}
        </option>
      </select>
    </label>
  </Dialog>
</template>
