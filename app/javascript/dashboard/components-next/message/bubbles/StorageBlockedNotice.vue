<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';

// Aviso cuando un adjunto está retenido por falta de espacio en el Drive de la
// cuenta (jabvox-drive). El archivo NO se perdió: se verá al ampliar el plan o
// liberar espacio. Reutilizable por los bubbles de imagen/video/audio/archivo.
const props = defineProps({
  fileType: { type: String, default: 'file' },
});

// Claves explícitas (no dinámicas) para que el extractor de i18n las detecte.
const MESSAGE_KEYS = {
  image: 'COMPONENTS.MEDIA.STORAGE_FULL_IMAGE',
  video: 'COMPONENTS.MEDIA.STORAGE_FULL_VIDEO',
  audio: 'COMPONENTS.MEDIA.STORAGE_FULL_AUDIO',
  file: 'COMPONENTS.MEDIA.STORAGE_FULL_FILE',
};

const messageKey = computed(() => {
  const t = (props.fileType || 'file').toLowerCase();
  if (t.includes('image')) return MESSAGE_KEYS.image;
  if (t.includes('video')) return MESSAGE_KEYS.video;
  if (t.includes('audio')) return MESSAGE_KEYS.audio;
  return MESSAGE_KEYS.file;
});
</script>

<template>
  <div
    class="flex flex-col items-center gap-1 text-center rounded-lg px-3 py-4 max-w-xs"
  >
    <Icon icon="i-lucide-cloud-off" class="text-n-amber-11" />
    <p class="mb-0 text-sm font-medium text-n-slate-12">
      {{ $t(messageKey) }}
    </p>
    <p class="mb-0 text-xs text-n-slate-10">
      {{ $t('COMPONENTS.MEDIA.STORAGE_FULL_HINT') }}
    </p>
  </div>
</template>
