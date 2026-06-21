<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsPageHeader from '../components/AnalyticsPageHeader.vue';
import AnalyticsLoadingState from '../components/AnalyticsLoadingState.vue';
import AnalyticsEmptyState from '../components/AnalyticsEmptyState.vue';
import SchemaTreeView from './SchemaTreeView.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useAnalyticsDataSourcesStore();
const { showError } = useAnalyticsError();

const dataSourceId = computed(() => route.params.dataSourceId);

const dataSource = computed(() => store.find(dataSourceId.value));

const loading = computed(() => store.uiFlags.fetchingSchema);

// The schema may arrive as a plain array or as an object grouping tables/views.
const schema = computed(() => {
  const raw = store.schemaFor(dataSourceId.value);
  if (!raw) return [];
  if (Array.isArray(raw)) return raw;
  const tables = (raw.tables || []).map(item => ({ ...item, type: 'table' }));
  const views = (raw.views || []).map(item => ({ ...item, type: 'view' }));
  return [...tables, ...views];
});

const loadSchema = async () => {
  try {
    await store.fetchSchema(dataSourceId.value);
  } catch (error) {
    showError(error);
  }
};

const viewData = table => {
  router.push({
    name: 'jabvox_analytics_ds_viewer',
    params: {
      accountId: route.params.accountId,
      dataSourceId: dataSourceId.value,
    },
    query: { table },
  });
};

onMounted(() => {
  if (!store.list.length) store.fetch().catch(() => {});
  loadSchema();
});
</script>

<template>
  <div>
    <AnalyticsPageHeader
      :title="dataSource.nameJabvox || t('JABVOX_ANALYTICS.SCHEMA.TABLES')"
    />

    <AnalyticsLoadingState v-if="loading" />

    <AnalyticsEmptyState
      v-else-if="!schema.length"
      icon="i-lucide-table-2"
      :title="t('JABVOX_ANALYTICS.SCHEMA.EMPTY')"
    />

    <SchemaTreeView v-else :schema="schema" @view-data="viewData" />
  </div>
</template>
