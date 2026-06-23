<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  loading: { type: Boolean, default: false },
  showReset: { type: Boolean, default: true },
});

const emit = defineEmits(['apply', 'reset']);
const { t } = useI18n();
</script>

<template>
  <div
    class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm flex flex-col gap-4"
  >
    <div class="flex items-center gap-2">
      <span class="i-lucide-sliders-horizontal size-4 text-n-slate-11" />
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('JABVOX_REPORTS.COMMON.FILTERS') }}
      </span>
    </div>
    <div class="flex flex-wrap items-end gap-3">
      <slot />
      <div class="flex items-center gap-2 ml-auto">
        <Button
          :label="t('JABVOX_REPORTS.COMMON.APPLY')"
          icon="i-lucide-search"
          size="sm"
          :is-loading="loading"
          @click="emit('apply')"
        />
        <Button
          v-if="showReset"
          :label="t('JABVOX_REPORTS.COMMON.RESET')"
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="sm"
          @click="emit('reset')"
        />
      </div>
    </div>
  </div>
</template>
