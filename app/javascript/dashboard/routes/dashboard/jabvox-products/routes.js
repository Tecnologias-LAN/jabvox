import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const ProductsPage = () => import('./ProductsPage.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/jabvox/products'),
    name: 'jabvox_products_index',
    meta: {
      featureFlag: FEATURE_FLAGS.JABVOX_PRODUCTS,
      permissions: ['administrator'],
    },
    component: ProductsPage,
  },
];
