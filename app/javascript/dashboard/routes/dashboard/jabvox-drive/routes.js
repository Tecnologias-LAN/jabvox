import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const DriveLayout = () => import('./DriveLayout.vue');
const DrivePage = () => import('./DrivePage.vue');
const DriveHistoryPage = () => import('./DriveHistoryPage.vue');
const DriveTrashPage = () => import('./DriveTrashPage.vue');

const meta = {
  featureFlag: FEATURE_FLAGS.JABVOX_DRIVE,
  permissions: ['administrator', 'agent'],
};
// El historial de auditoría es solo para administradores.
const adminMeta = {
  featureFlag: FEATURE_FLAGS.JABVOX_DRIVE,
  permissions: ['administrator'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/drive'),
    component: DriveLayout,
    children: [
      {
        path: '',
        name: 'jabvox_drive_index',
        meta,
        component: DrivePage,
      },
      {
        // Vista de una carpeta concreta (navegación por carpetas).
        path: 'folders/:folderId',
        name: 'jabvox_drive_folder',
        meta,
        component: DrivePage,
        props: true,
      },
      {
        // Adjuntos de un contacto específico (carpeta especial "Contactos/").
        path: 'contacts/:contactId',
        name: 'jabvox_drive_contact',
        meta,
        component: DrivePage,
        props: true,
      },
      {
        // Historial de actividad (quién subió/descargó/renombró/movió/eliminó).
        path: 'history',
        name: 'jabvox_drive_history',
        meta: adminMeta,
        component: DriveHistoryPage,
      },
      {
        // Papelera: archivos eliminados (recuperables hasta la auto-purga).
        path: 'trash',
        name: 'jabvox_drive_trash',
        meta: adminMeta,
        component: DriveTrashPage,
      },
    ],
  },
];
