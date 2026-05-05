import { frontendURL } from 'dashboard/helper/URLHelper.js';

const FieldSecuritySettings = () => import('./FieldSecuritySettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/settings/jabvox/field-security'),
    name: 'jabvox_field_security_index',
    meta: { permissions: ['administrator'] },
    component: FieldSecuritySettings,
  },
];
