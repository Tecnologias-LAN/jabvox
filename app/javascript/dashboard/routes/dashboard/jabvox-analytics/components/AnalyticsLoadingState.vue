<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  label: { type: String, default: '' },
});

const { t } = useI18n();
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-3 py-16 text-n-slate-11"
  >
    <span class="i-lucide-loader-circle size-6 animate-spin" />
    <p class="text-sm">
      {{ label || t('JABVOX_ANALYTICS.COMMON.LOADING') }}
    </p>
  </div>
</template>
