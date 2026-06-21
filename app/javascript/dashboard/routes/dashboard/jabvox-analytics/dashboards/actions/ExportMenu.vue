<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { analyticsExportsAPI } from 'dashboard/api/jabvox/analytics';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';

const props = defineProps({
  dashboardId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const { showError } = useAnalyticsError();
const capabilities = useAnalyticsCapabilitiesStore();

const open = ref(false);
const busy = ref(false);

const FORMATS = ['pdf', 'excel', 'csv'];

// Labels resolved with static literal keys so the template binds plain strings.
const formatLabels = computed(() => ({
  pdf: t('JABVOX_ANALYTICS.EXPORT.PDF'),
  excel: t('JABVOX_ANALYTICS.EXPORT.EXCEL'),
  csv: t('JABVOX_ANALYTICS.EXPORT.CSV'),
}));

const runExport = async format => {
  open.value = false;
  busy.value = true;
  useAlert(t('JABVOX_ANALYTICS.EXPORT.PREPARING'));
  try {
    await analyticsExportsAPI.create({
      dashboard_id: props.dashboardId,
      format_jabvox: format,
    });
    useAlert(t('JABVOX_ANALYTICS.EXPORT.READY'));
  } catch (error) {
    showError(error, 'JABVOX_ANALYTICS.EXPORT.FAILED');
  } finally {
    busy.value = false;
  }
};

const menuItemClass =
  'flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-n-slate-12 hover:bg-n-alpha-2';
</script>

<template>
  <div class="relative">
    <template v-if="capabilities.can('export')">
      <button
        type="button"
        class="inline-flex items-center gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="busy"
        @click="open = !open"
      >
        <span
          :class="
            busy ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-download'
          "
          class="size-4"
        />
        {{ t('JABVOX_ANALYTICS.DASHBOARDS.EXPORT') }}
      </button>
      <div
        v-if="open"
        class="absolute right-0 z-20 mt-1 w-48 overflow-hidden rounded-lg border border-n-weak bg-n-solid-1 py-1 shadow-lg"
      >
        <button
          v-for="format in FORMATS"
          :key="format"
          type="button"
          :class="menuItemClass"
          @click="runExport(format)"
        >
          {{ formatLabels[format] }}
        </button>
      </div>
    </template>
  </div>
</template>
