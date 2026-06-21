// Barrel for the Analytics & Dashboards API clients. Each resource lives in its own file
// under api/jabvox/analytics/ (one class per file); this re-exports them under the names
// the stores and components already import.
import analyticsDataSourcesAPI from './analytics/dataSources';
import analyticsFoldersAPI from './analytics/folders';
import analyticsDashboardsAPI from './analytics/dashboards';
import analyticsExportsAPI from './analytics/exports';
import analyticsPermissionsAPI from './analytics/permissions';

export {
  analyticsDataSourcesAPI,
  analyticsFoldersAPI,
  analyticsDashboardsAPI,
  analyticsExportsAPI,
  analyticsPermissionsAPI,
};
