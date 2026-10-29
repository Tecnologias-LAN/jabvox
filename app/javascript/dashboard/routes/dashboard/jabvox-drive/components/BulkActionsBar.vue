<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  count: { type: Number, default: 0 },
});

const emit = defineEmits(['move', 'delete', 'clear']);

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-n-brand/40 bg-n-brand/5 px-4 py-2.5"
  >
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('JABVOX_DRIVE.BULK.SELECTED', { count }) }}
    </span>
    <div class="flex items-center gap-2">
      <Button
        variant="outline"
        color="slate"
        size="sm"
        icon="i-lucide-folder-input"
        :label="t('JABVOX_DRIVE.BULK.MOVE')"
        @click="emit('move')"
      />
      <Button
        variant="outline"
        color="ruby"
        size="sm"
        icon="i-lucide-trash-2"
        :label="t('JABVOX_DRIVE.BULK.DELETE')"
        @click="emit('delete')"
      />
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-x"
        :label="t('JABVOX_DRIVE.BULK.CLEAR')"
        @click="emit('clear')"
      />
    </div>
  </div>
</template>
