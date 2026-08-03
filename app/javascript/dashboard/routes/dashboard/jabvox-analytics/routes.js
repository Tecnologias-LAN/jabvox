import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const AnalyticsLayout = () => import('./AnalyticsLayout.vue');
const OverviewPage = () => import('./overview/OverviewPage.vue');
const DataSourcesIndex = () => import('./data-sources/DataSourcesIndex.vue');
const SchemaExplorer = () => import('./data-sources/SchemaExplorer.vue');
const DataViewerPage = () => import('./data-sources/DataViewerPage.vue');
const QueryBuilderPage = () => import('./query-builder/QueryBuilderPage.vue');
const SqlEditorPage = () => import('./sql/SqlEditorPage.vue');
const DashboardsIndex = () => import('./dashboards/DashboardsIndex.vue');
const DashboardBuilder = () => import('./dashboards/DashboardBuilder.vue');
const PermissionsIndex = () => import('./permissions/PermissionsIndex.vue');
const CrossReportsIndex = () => import('./cross-reports/CrossReportsIndex.vue');
const CrossReportEditor = () => import('./cross-reports/CrossReportEditor.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.JABVOX_ANALYTICS,
  permissions: ['administrator', 'agent'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/analytics'),
    component: AnalyticsLayout,
    children: [
      {
        path: '',
        name: 'jabvox_analytics_index',
        meta,
        redirect: to => ({
          name: 'jabvox_analytics_overview',
          params: { accountId: to.params.accountId },
        }),
      },
      {
        path: 'overview',
        name: 'jabvox_analytics_overview',
        meta,
        component: OverviewPage,
      },
      {
        path: 'data-sources',
        name: 'jabvox_analytics_data_sources',
        meta,
        component: DataSourcesIndex,
      },
      {
        path: 'data-sources/:dataSourceId/tables',
        name: 'jabvox_analytics_ds_tables',
        meta,
        component: SchemaExplorer,
      },
      {
        path: 'data-sources/:dataSourceId/data',
        name: 'jabvox_analytics_ds_viewer',
        meta,
        component: DataViewerPage,
      },
      {
        path: 'query-builder',
        name: 'jabvox_analytics_query_builder',
        meta,
        component: QueryBuilderPage,
      },
      {
        path: 'sql',
        name: 'jabvox_analytics_sql',
        meta,
        component: SqlEditorPage,
      },
      {
        path: 'dashboards',
        name: 'jabvox_analytics_dashboards',
        meta,
        component: DashboardsIndex,
      },
      {
        path: 'dashboards/:dashboardId',
        name: 'jabvox_analytics_dashboard_show',
        meta,
        component: DashboardBuilder,
      },
      {
        path: 'cross-reports',
        name: 'jabvox_analytics_cross_reports',
        meta,
        component: CrossReportsIndex,
      },
      {
        path: 'cross-reports/new',
        name: 'jabvox_analytics_cross_report_new',
        meta,
        component: CrossReportEditor,
      },
      {
        path: 'cross-reports/:crossReportId',
        name: 'jabvox_analytics_cross_report_edit',
        meta,
        component: CrossReportEditor,
      },
      {
        path: 'permissions',
        name: 'jabvox_analytics_permissions',
        meta,
        component: PermissionsIndex,
      },
    ],
  },
];
