<script setup>
import { useI18n } from 'vue-i18n';

// v1 placeholder: geographic maps need a registered GeoJSON which is heavy to
// bundle. Rendered as an informational placeholder until configured.
const { t } = useI18n();
</script>

<template>
  <div
    class="flex size-full flex-col items-center justify-center gap-2 p-4 text-center"
  >
    <span class="i-lucide-map size-8 text-n-slate-9" />
    <p class="text-sm text-n-slate-11">
      {{ t('JABVOX_ANALYTICS.WIDGETS.MAP_PLACEHOLDER') }}
    </p>
  </div>
</template>
