<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';

const props = defineProps({
  dataSourceId: {
    type: [Number, String],
    default: null,
  },
  payload: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['result']);

const { t } = useI18n();
const store = useAnalyticsDataSourcesStore();
const { showError } = useAnalyticsError();

const testing = ref(false);

const handleTest = async () => {
  testing.value = true;
  try {
    const result = props.dataSourceId
      ? await store.testConnection(props.dataSourceId)
      : await store.testUnsaved(props.payload);
    emit('result', result);
  } catch (error) {
    showError(error);
  } finally {
    testing.value = false;
  }
};
</script>

<template>
  <button
    type="button"
    class="inline-flex items-center gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12 disabled:cursor-not-allowed disabled:opacity-50"
    :disabled="testing"
    @click="handleTest"
  >
    <span
      class="size-4"
      :class="testing ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-plug'"
    />
    {{
      testing
        ? t('JABVOX_ANALYTICS.DATA_SOURCES.TEST.TESTING')
        : t('JABVOX_ANALYTICS.DATA_SOURCES.FORM.TEST')
    }}
  </button>
</template>
