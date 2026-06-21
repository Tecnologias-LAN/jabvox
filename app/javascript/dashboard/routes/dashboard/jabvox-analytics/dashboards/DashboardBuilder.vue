<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';
import { useAlert } from 'dashboard/composables';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';
import { useAnalyticsWidgetsStore } from 'dashboard/stores/jabvox/analytics/widgets';
import { useAnalyticsDataSourcesStore } from 'dashboard/stores/jabvox/analytics/dataSources';
import { useAnalyticsCapabilitiesStore } from 'dashboard/stores/jabvox/analytics/capabilities';
import { useAnalyticsError } from 'dashboard/composables/useAnalyticsError';
import AnalyticsLoadingState from '../components/AnalyticsLoadingState.vue';
import AnalyticsEmptyState from '../components/AnalyticsEmptyState.vue';
import DashboardGrid from './builder/DashboardGrid.vue';
import WidgetPicker from './builder/WidgetPicker.vue';
import WidgetConfigPanel from './builder/WidgetConfigPanel.vue';
import GlobalFilterBar from './filters/GlobalFilterBar.vue';
import ExportMenu from './actions/ExportMenu.vue';
import ShareDialog from './actions/ShareDialog.vue';
import RefreshControl from './actions/RefreshControl.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const dashboardsStore = useAnalyticsDashboardsStore();
const widgetsStore = useAnalyticsWidgetsStore();
const dsStore = useAnalyticsDataSourcesStore();
const capabilities = useAnalyticsCapabilitiesStore();
const { showError } = useAnalyticsError();

const { currentDashboard, editMode, globalFilters } =
  storeToRefs(dashboardsStore);

const dashboardId = computed(() => route.params.dashboardId);
const loading = computed(() => dashboardsStore.uiFlags.fetchingItem);

// Widget-type labels resolved with static literal keys so an initial widget
// title can be derived from the type without passing a dynamic i18n key.
const widgetTypeLabels = computed(() => ({
  number: t('JABVOX_ANALYTICS.WIDGETS.TYPES.number'),
  indicator: t('JABVOX_ANALYTICS.WIDGETS.TYPES.indicator'),
  comparative: t('JABVOX_ANALYTICS.WIDGETS.TYPES.comparative'),
  ranking: t('JABVOX_ANALYTICS.WIDGETS.TYPES.ranking'),
  line: t('JABVOX_ANALYTICS.WIDGETS.TYPES.line'),
  area: t('JABVOX_ANALYTICS.WIDGETS.TYPES.area'),
  time_series: t('JABVOX_ANALYTICS.WIDGETS.TYPES.time_series'),
  bar: t('JABVOX_ANALYTICS.WIDGETS.TYPES.bar'),
  stacked_bar: t('JABVOX_ANALYTICS.WIDGETS.TYPES.stacked_bar'),
  pie: t('JABVOX_ANALYTICS.WIDGETS.TYPES.pie'),
  donut: t('JABVOX_ANALYTICS.WIDGETS.TYPES.donut'),
  scatter: t('JABVOX_ANALYTICS.WIDGETS.TYPES.scatter'),
  gauge: t('JABVOX_ANALYTICS.WIDGETS.TYPES.gauge'),
  heatmap: t('JABVOX_ANALYTICS.WIDGETS.TYPES.heatmap'),
  treemap: t('JABVOX_ANALYTICS.WIDGETS.TYPES.treemap'),
  funnel: t('JABVOX_ANALYTICS.WIDGETS.TYPES.funnel'),
  map: t('JABVOX_ANALYTICS.WIDGETS.TYPES.map'),
  table: t('JABVOX_ANALYTICS.WIDGETS.TYPES.table'),
  pivot_table: t('JABVOX_ANALYTICS.WIDGETS.TYPES.pivot_table'),
  text_markdown: t('JABVOX_ANALYTICS.WIDGETS.TYPES.text_markdown'),
}));

const showPicker = ref(false);
const configWidget = ref(null);
const showShare = ref(false);

const widgets = computed(() => widgetsStore.forDashboard(dashboardId.value));
const layout = computed(() => currentDashboard.value?.layoutJabvox || []);
const notFound = computed(() => !loading.value && !currentDashboard.value);

// snake_case only the known top-level keys; the dynamic map carries
// user-defined field names that must be preserved verbatim.
const filterPayload = () => ({
  date_from: globalFilters.value.dateFrom,
  date_to: globalFilters.value.dateTo,
  dynamic: globalFilters.value.dynamic,
});

const refreshAll = () => {
  widgets.value.forEach(widget => {
    widgetsStore
      .refreshWidget(dashboardId.value, widget.id, filterPayload())
      .catch(error => showError(error, 'JABVOX_ANALYTICS.WIDGETS.ERROR'));
  });
};

const refreshOne = widget => {
  widgetsStore
    .refreshWidget(dashboardId.value, widget.id, filterPayload())
    .catch(error => showError(error, 'JABVOX_ANALYTICS.WIDGETS.ERROR'));
};

onMounted(async () => {
  try {
    await dashboardsStore.getDashboard(dashboardId.value);
    await widgetsStore.fetchWidgets(dashboardId.value);
    if (!dsStore.list.length) dsStore.fetch().catch(() => {});
    refreshAll();
  } catch (error) {
    showError(error);
  }
});

const toggleEdit = () => dashboardsStore.setEditMode(!editMode.value);

const goBack = () =>
  router.push({
    name: 'jabvox_analytics_dashboards',
    params: { accountId: route.params.accountId },
  });

const onSelectWidgetType = async type => {
  showPicker.value = false;
  try {
    const created = await widgetsStore.addWidget(dashboardId.value, {
      widget_type_jabvox: type,
      title_jabvox: widgetTypeLabels.value[type],
    });
    // Open the config panel so the user can wire up the data immediately.
    configWidget.value = created;
  } catch (error) {
    showError(error);
  }
};

const onConfigSaved = () => {
  const widget = configWidget.value;
  configWidget.value = null;
  if (widget) refreshOne(widget);
};

const onDuplicate = async widget => {
  try {
    await widgetsStore.addWidget(dashboardId.value, {
      widget_type_jabvox: widget.widgetTypeJabvox,
      title_jabvox: widget.titleJabvox,
      data_source_id: widget.dataSourceId,
      query_spec_jabvox: widget.querySpecJabvox || {},
      custom_sql_jabvox: widget.customSqlJabvox || null,
      config_jabvox: widget.configJabvox || {},
    });
    refreshAll();
  } catch (error) {
    showError(error);
  }
};

const onRemove = async widget => {
  try {
    await widgetsStore.deleteWidget(dashboardId.value, widget.id);
    useAlert(t('JABVOX_ANALYTICS.COMMON.DELETE'));
  } catch (error) {
    showError(error);
  }
};

const secondaryBtn =
  'inline-flex items-center gap-2 rounded-lg bg-n-alpha-2 px-3 py-2 text-sm font-medium text-n-slate-12';
</script>

<template>
  <div>
    <AnalyticsLoadingState v-if="loading" />

    <AnalyticsEmptyState
      v-else-if="notFound"
      icon="i-lucide-search-x"
      :title="t('JABVOX_ANALYTICS.DASHBOARDS.NOT_FOUND')"
    >
      <template #action>
        <button type="button" :class="secondaryBtn" @click="goBack">
          <span class="i-lucide-arrow-left size-4" />
          {{ t('JABVOX_ANALYTICS.DASHBOARDS.BACK') }}
        </button>
      </template>
    </AnalyticsEmptyState>

    <template v-else>
      <!-- Header -->
      <div
        class="mb-4 flex flex-wrap items-center justify-between gap-3 border-b border-n-weak pb-4"
      >
        <div class="flex min-w-0 items-center gap-2">
          <button
            type="button"
            class="rounded-lg p-1.5 text-n-slate-11 hover:bg-n-alpha-2"
            :title="t('JABVOX_ANALYTICS.DASHBOARDS.BACK')"
            @click="goBack"
          >
            <span class="i-lucide-arrow-left size-5" />
          </button>
          <h1 class="truncate text-lg font-semibold text-n-slate-12">
            {{ currentDashboard.nameJabvox }}
          </h1>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button type="button" :class="secondaryBtn" @click="toggleEdit">
            <span
              :class="editMode ? 'i-lucide-eye' : 'i-lucide-pencil'"
              class="size-4"
            />
            {{
              editMode
                ? t('JABVOX_ANALYTICS.DASHBOARDS.VIEW_MODE')
                : t('JABVOX_ANALYTICS.DASHBOARDS.EDIT_MODE')
            }}
          </button>
          <button
            v-if="editMode && capabilities.canCreate"
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white"
            @click="showPicker = true"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('JABVOX_ANALYTICS.DASHBOARDS.ADD_WIDGET') }}
          </button>
          <RefreshControl @refresh="refreshAll" />
          <ExportMenu :dashboard-id="dashboardId" />
          <button
            v-if="capabilities.can('share')"
            type="button"
            :class="secondaryBtn"
            @click="showShare = true"
          >
            <span class="i-lucide-share-2 size-4" />
            {{ t('JABVOX_ANALYTICS.DASHBOARDS.SHARE') }}
          </button>
        </div>
      </div>

      <GlobalFilterBar @apply="refreshAll" />

      <AnalyticsEmptyState
        v-if="!widgets.length"
        icon="i-lucide-layout-dashboard"
        :title="t('JABVOX_ANALYTICS.DASHBOARDS.NO_WIDGETS_TITLE')"
        :body="t('JABVOX_ANALYTICS.DASHBOARDS.NO_WIDGETS_BODY')"
      >
        <template #action>
          <button
            v-if="capabilities.canCreate"
            type="button"
            class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white"
            @click="showPicker = true"
          >
            <span class="i-lucide-plus size-4" />
            {{ t('JABVOX_ANALYTICS.DASHBOARDS.ADD_WIDGET') }}
          </button>
        </template>
      </AnalyticsEmptyState>

      <DashboardGrid
        v-else
        :dashboard-id="dashboardId"
        :widgets="widgets"
        :layout="layout"
        :edit-mode="editMode"
        @duplicate="onDuplicate"
        @remove="onRemove"
        @refresh="refreshOne"
        @configure="configWidget = $event"
      />
    </template>

    <WidgetPicker
      :open="showPicker"
      @close="showPicker = false"
      @select="onSelectWidgetType"
    />

    <WidgetConfigPanel
      :open="Boolean(configWidget)"
      :widget="configWidget"
      :dashboard-id="dashboardId"
      @close="configWidget = null"
      @saved="onConfigSaved"
    />

    <ShareDialog
      :open="showShare"
      :dashboard-id="dashboardId"
      @close="showShare = false"
    />
  </div>
</template>
