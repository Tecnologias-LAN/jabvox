<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';

const props = defineProps({
  folder: { type: Object, required: true },
});

const emit = defineEmits(['rename', 'delete']);

const { t } = useI18n();
const open = ref(false);

// Las carpetas de sistema (contactos y bandejas) son estructura canónica:
// no se pueden renombrar, mover ni eliminar desde la UI.
const isSystemFolder = computed(() => !!props.folder.system_folder);

const close = () => {
  open.value = false;
};

const onRename = () => {
  close();
  emit('rename', props.folder);
};
const onDelete = () => {
  close();
  emit('delete', props.folder);
};
</script>

<template>
  <!-- En carpetas de sistema no hay acciones disponibles: se oculta el menú. -->
  <OnClickOutside v-if="!isSystemFolder" @trigger="close">
    <div class="relative">
      <button
        type="button"
        class="flex items-center justify-center size-7 rounded-md text-n-slate-10 hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :aria-label="t('JABVOX_DRIVE.FOLDER.ACTIONS')"
        aria-haspopup="menu"
        :aria-expanded="open"
        @click.stop="open = !open"
      >
        <span class="i-lucide-more-vertical size-4" aria-hidden="true" />
      </button>
      <div
        v-if="open"
        role="menu"
        class="absolute right-0 top-8 z-20 w-44 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 py-1 shadow-xl"
        @click.stop
      >
        <button
          type="button"
          role="menuitem"
          class="flex w-full items-center gap-2 px-3 py-2 text-sm text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="onRename"
        >
          <span class="i-lucide-pencil size-4" aria-hidden="true" />
          {{ t('JABVOX_DRIVE.FOLDER.RENAME') }}
        </button>
        <button
          type="button"
          role="menuitem"
          class="flex w-full items-center gap-2 px-3 py-2 text-sm text-n-ruby-11 hover:bg-n-alpha-1"
          @click="onDelete"
        >
          <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
          {{ t('JABVOX_DRIVE.FOLDER.DELETE') }}
        </button>
      </div>
    </div>
  </OnClickOutside>
</template>
