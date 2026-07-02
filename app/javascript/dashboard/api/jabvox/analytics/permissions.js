/* global axios */
import ApiClient from '../../ApiClient';

// Covers the RBAC sibling endpoints (roles, role_permissions, user_permissions,
// my_capabilities, audit_logs) under the jabvox/analytics namespace.
class JabvoxAnalyticsPermissionsAPI extends ApiClient {
  constructor() {
    super('jabvox/analytics/roles', { accountScoped: true });
  }

  // url => .../jabvox/analytics/roles ; derive the sibling endpoints from it.
  get base() {
    return this.url.replace(/\/roles$/, '');
  }

  getRoles() {
    return axios.get(`${this.base}/roles`);
  }

  createRole(data) {
    return axios.post(`${this.base}/roles`, { role: data });
  }

  updateRole(id, data) {
    return axios.patch(`${this.base}/roles/${id}`, { role: data });
  }

  deleteRole(id) {
    return axios.delete(`${this.base}/roles/${id}`);
  }

  getRolePermissions() {
    return axios.get(`${this.base}/role_permissions`);
  }

  updateRolePermissions(roleId, grants) {
    return axios.patch(`${this.base}/role_permissions/${roleId}`, { grants });
  }

  getUserPermissions() {
    return axios.get(`${this.base}/user_permissions`);
  }

  bulkUpdateUserPermissions(payload) {
    return axios.patch(`${this.base}/user_permissions/bulk`, payload);
  }

  // Which dashboards a single user can see (per-user access panel).
  getUserDashboardAccess(userId) {
    return axios.get(`${this.base}/user_dashboard_access`, {
      params: { user_id: userId },
    });
  }

  updateUserDashboardAccess(userId, dashboardIds) {
    return axios.patch(`${this.base}/user_dashboard_access`, {
      user_id: userId,
      dashboard_ids: dashboardIds,
    });
  }

  myCapabilities() {
    return axios.get(`${this.base}/my_capabilities`);
  }

  getAuditLogs(params = {}) {
    return axios.get(`${this.base}/audit_logs`, { params });
  }
}

export default new JabvoxAnalyticsPermissionsAPI();
