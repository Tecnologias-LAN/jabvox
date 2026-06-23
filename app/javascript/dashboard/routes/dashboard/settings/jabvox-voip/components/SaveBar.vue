<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  visible: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'discard']);
const { t } = useI18n();
</script>

<template>
  <Transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="translate-y-full opacity-0"
    enter-to-class="translate-y-0 opacity-100"
    leave-active-class="transition duration-150 ease-in"
    leave-from-class="translate-y-0 opacity-100"
    leave-to-class="translate-y-full opacity-0"
  >
    <div
      v-if="visible"
      class="sticky bottom-0 inset-x-0 z-10 mt-2 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-3 shadow-lg"
    >
      <span class="flex items-center gap-2 text-sm text-n-slate-12">
        <span class="i-lucide-circle-alert size-4 text-n-amber-11" />
        {{ t('JABVOX_VOIP.SAVE_BAR.UNSAVED') }}
      </span>
      <div class="flex items-center gap-2">
        <Button
          :label="t('JABVOX_VOIP.SAVE_BAR.DISCARD')"
          variant="outline"
          color="slate"
          size="sm"
          @click="emit('discard')"
        />
        <Button
          :label="t('JABVOX_VOIP.SAVE_BAR.SAVE')"
          size="sm"
          :is-loading="isSaving"
          :disabled="disabled"
          @click="emit('save')"
        />
      </div>
    </div>
  </Transition>
</template>
