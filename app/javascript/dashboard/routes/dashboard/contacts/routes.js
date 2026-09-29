import { frontendURL } from '../../../helper/URLHelper';
import ContactsIndex from './pages/ContactsIndex.vue';
import ContactManageView from './pages/ContactManageView.vue';
import { FEATURE_FLAGS } from '../../../featureFlags';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent', 'contact_manage'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/contacts'),
    component: ContactsIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'contacts_dashboard_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'segments/:segmentId',
        name: 'contacts_dashboard_segments_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'labels/:label',
        name: 'contacts_dashboard_labels_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'active',
        name: 'contacts_dashboard_active',
        component: ContactsIndex,
        meta: commonMeta,
      },
    ],
  },
  // Leads desapareció: todo vive en Contactos. Se conservan las rutas como REDIRECCIÓN para
  // que los enlaces guardados (favoritos, correos, automatizaciones) no den 404. El id del
  // lead es hoy el id del contacto, así que el detalle redirige directo a su ficha.
  {
    path: frontendURL('accounts/:accountId/contacts/jabvox/leads'),
    name: 'jabvox_leads_index',
    redirect: to => ({
      name: 'contacts_dashboard_index',
      params: { accountId: to.params.accountId },
    }),
  },
  {
    path: frontendURL('accounts/:accountId/contacts/jabvox/leads/:leadId'),
    name: 'jabvox_lead_detail',
    redirect: to => ({
      name: 'contacts_edit',
      params: { accountId: to.params.accountId, contactId: to.params.leadId },
    }),
  },
  {
    path: frontendURL('accounts/:accountId/contacts/:contactId'),
    component: ContactManageView,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'contacts_edit',
        component: ContactManageView,
        meta: commonMeta,
      },
      {
        path: 'segments/:segmentId',
        name: 'contacts_edit_segment',
        component: ContactManageView,
        meta: commonMeta,
      },
      {
        path: 'labels/:label',
        name: 'contacts_edit_label',
        component: ContactManageView,
        meta: commonMeta,
      },
    ],
  },
];
