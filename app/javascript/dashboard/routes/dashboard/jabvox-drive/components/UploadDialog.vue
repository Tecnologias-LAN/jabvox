<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { humanSize } from '../helper';

defineProps({
  isLoading: { type: Boolean, default: false },
  progress: { type: Number, default: 0 },
});

const emit = defineEmits(['submit', 'close']);

const { t } = useI18n();
const dialogRef = ref(null);
const selectedFiles = ref([]);
const fileInput = ref(null);
const isDragging = ref(false);

const open = () => {
  selectedFiles.value = [];
  isDragging.value = false;
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
};

const onFilesPicked = event => {
  selectedFiles.value = Array.from(event.target.files || []);
};

const onDrop = event => {
  isDragging.value = false;
  selectedFiles.value = Array.from(event.dataTransfer.files || []);
};

const removeFile = index => {
  selectedFiles.value = selectedFiles.value.filter((_, i) => i !== index);
};

const triggerPicker = () => {
  fileInput.value?.click();
};

const onConfirm = () => {
  if (!selectedFiles.value.length) return;
  emit('submit', selectedFiles.value);
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('JABVOX_DRIVE.UPLOAD.TITLE')"
    :confirm-button-label="t('JABVOX_DRIVE.TOOLBAR.UPLOAD')"
    :is-loading="isLoading"
    :disable-confirm-button="!selectedFiles.length"
    @confirm="onConfirm"
    @close="emit('close')"
  >
    <!-- Contenedor con alto máximo acotado al viewport: en pantallas pequeñas el
         diálogo nunca desborda; la LISTA de archivos es la que hace scroll. -->
    <div class="flex max-h-[60vh] flex-col gap-4 overflow-y-auto">
      <div
        role="button"
        tabindex="0"
        :aria-label="t('JABVOX_DRIVE.UPLOAD.DROP_HERE')"
        class="flex shrink-0 cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed px-4 py-6 text-center transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand sm:py-8"
        :class="
          isDragging
            ? 'border-n-brand bg-n-brand/5'
            : 'border-n-weak bg-n-alpha-1 hover:border-n-brand/50'
        "
        @click="triggerPicker"
        @keydown.enter.prevent="triggerPicker"
        @keydown.space.prevent="triggerPicker"
        @dragover.prevent="isDragging = true"
        @dragleave.prevent="isDragging = false"
        @drop.prevent="onDrop"
      >
        <span
          class="i-lucide-upload-cloud size-8 text-n-slate-10"
          aria-hidden="true"
        />
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_DRIVE.UPLOAD.DROP_HERE') }}
        </p>
        <input
          ref="fileInput"
          type="file"
          multiple
          class="hidden"
          @change="onFilesPicked"
        />
      </div>

      <!-- Lista scrollable: muchos archivos no rompen el diálogo. -->
      <ul
        v-if="selectedFiles.length"
        class="flex max-h-60 flex-col gap-1.5 overflow-y-auto"
      >
        <li
          v-for="(file, index) in selectedFiles"
          :key="index"
          class="flex items-center justify-between gap-2 rounded-lg bg-n-alpha-1 px-3 py-1.5 text-sm"
        >
          <span class="min-w-0 truncate text-n-slate-12">{{ file.name }}</span>
          <div class="flex shrink-0 items-center gap-2">
            <span class="whitespace-nowrap text-xs text-n-slate-10">
              {{ humanSize(file.size) }}
            </span>
            <button
              v-if="!isLoading"
              type="button"
              class="flex items-center justify-center size-5 rounded text-n-slate-10 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
              :aria-label="
                t('JABVOX_DRIVE.UPLOAD.REMOVE_FILE', { name: file.name })
              "
              @click="removeFile(index)"
            >
              <span class="i-lucide-x size-3.5" aria-hidden="true" />
            </button>
          </div>
        </li>
      </ul>
    </div>

    <div v-if="isLoading" class="flex flex-col gap-1">
      <div class="h-2 w-full overflow-hidden rounded-full bg-n-alpha-1">
        <div
          class="h-full rounded-full bg-n-brand transition-all"
          :style="{ width: `${progress}%` }"
        />
      </div>
      <p class="text-xs text-n-slate-10">
        {{ t('JABVOX_DRIVE.UPLOAD.UPLOADING') }} {{ progress }}%
      </p>
    </div>
  </Dialog>
</template>
