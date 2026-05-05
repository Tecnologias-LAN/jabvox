const AffiliatePortalLogin = () => import('./AffiliatePortalLogin.vue');
const AffiliatePortalLayout = () => import('./AffiliatePortalLayout.vue');
const AffiliateManualUpload = () => import('./AffiliateManualUpload.vue');
const AffiliateBulkUpload = () => import('./AffiliateBulkUpload.vue');
const AffiliateHistory = () => import('./AffiliateHistory.vue');
const AffiliateLeads = () => import('./AffiliateLeads.vue');

export const routes = [
  {
    path: '/:portalAccountId/affiliate-portal/login/:affiliateSlug',
    name: 'affiliate_portal_login',
    component: AffiliatePortalLogin,
    meta: { public: true },
  },
  {
    path: '/:portalAccountId/affiliate-portal/:affiliateSlug',
    component: AffiliatePortalLayout,
    meta: { public: true },
    redirect: to => ({ name: 'affiliate_portal_leads', params: to.params }),
    children: [
      {
        path: 'manual',
        name: 'affiliate_portal_manual',
        component: AffiliateManualUpload,
        meta: { public: true },
      },
      {
        path: 'bulk',
        name: 'affiliate_portal_bulk',
        component: AffiliateBulkUpload,
        meta: { public: true },
      },
      {
        path: 'history',
        name: 'affiliate_portal_history',
        component: AffiliateHistory,
        meta: { public: true },
      },
      {
        path: 'leads',
        name: 'affiliate_portal_leads',
        component: AffiliateLeads,
        meta: { public: true },
      },
    ],
  },
];
