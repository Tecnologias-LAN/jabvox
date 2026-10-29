<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';

const props = defineProps({
  file: { type: Object, required: true },
  canManage: { type: Boolean, default: true },
});

const emit = defineEmits([
  'preview',
  'download',
  'rename',
  'move',
  'delete',
  'goToConversation',
]);

const { t } = useI18n();
const open = ref(false);

const close = () => {
  open.value = false;
};

// Cierra el menú y emite el evento correspondiente con el archivo.
const onPreview = () => {
  close();
  emit('preview', props.file);
};
const onDownload = () => {
  close();
  emit('download', props.file);
};
const onGoToConversation = () => {
  close();
  emit('goToConversation', props.file);
};
const onRename = () => {
  close();
  emit('rename', props.file);
};
const onMove = () => {
  close();
  emit('move', props.file);
};
const onDelete = () => {
  close();
  emit('delete', props.file);
};
</script>

<template>
  <OnClickOutside @trigger="close">
    <div class="relative">
      <button
        type="button"
        class="flex items-center justify-center size-7 rounded-md text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :aria-label="t('JABVOX_DRIVE.FILE.ACTIONS')"
        aria-haspopup="menu"
        :aria-expanded="open"
        @click.stop="open = !open"
      >
        <span class="i-lucide-more-vertical size-4" aria-hidden="true" />
      </button>
      <div
        v-if="open"
        role="menu"
        class="absolute right-0 top-8 z-20 w-48 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 py-1 shadow-xl"
        @click.stop
      >
        <button
          type="button"
          role="menuitem"
          class="flex w-full items-center gap-2 px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="onPreview"
        >
          <span class="i-lucide-eye size-4" aria-hidden="true" />
          {{ t('JABVOX_DRIVE.FILE.PREVIEW') }}
        </button>
        <button
          type="button"
          role="menuitem"
          class="flex w-full items-center gap-2 px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="onDownload"
        >
          <span class="i-lucide-download size-4" aria-hidden="true" />
          {{ t('JABVOX_DRIVE.FILE.DOWNLOAD') }}
        </button>
        <button
          v-if="file.conversation_id"
          type="button"
          role="menuitem"
          class="flex w-full items-center gap-2 px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="onGoToConversation"
        >
          <span class="i-lucide-message-square size-4" aria-hidden="true" />
          {{ t('JABVOX_DRIVE.FILE.GO_TO_CONVERSATION') }}
        </button>
        <template v-if="canManage">
          <div class="my-1 h-px bg-n-weak" />
          <button
            type="button"
            role="menuitem"
            class="flex w-full items-center gap-2 px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
            @click="onRename"
          >
            <span class="i-lucide-pencil size-4" aria-hidden="true" />
            {{ t('JABVOX_DRIVE.FILE.RENAME') }}
          </button>
          <button
            type="button"
            role="menuitem"
            class="flex w-full items-center gap-2 px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
            @click="onMove"
          >
            <span class="i-lucide-folder-input size-4" aria-hidden="true" />
            {{ t('JABVOX_DRIVE.FILE.MOVE') }}
          </button>
          <button
            type="button"
            role="menuitem"
            class="flex w-full items-center gap-2 px-3 py-2 text-sm text-n-ruby-11 hover:bg-n-alpha-1"
            @click="onDelete"
          >
            <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
            {{ t('JABVOX_DRIVE.FILE.DELETE') }}
          </button>
        </template>
      </div>
    </div>
  </OnClickOutside>
</template>
