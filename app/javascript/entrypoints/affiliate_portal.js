import '../dashboard/assets/scss/app.scss';
import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import { createRouter, createWebHistory } from 'vue-router';
import axios from 'axios';
import jabvoxAffiliatePortal from '../dashboard/i18n/locale/en/jabvoxAffiliatePortal.json';
import { routes } from '../dashboard/routes/affiliate-portal/index';

window.axios = axios;

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: { ...jabvoxAffiliatePortal } },
});

const router = createRouter({
  history: createWebHistory(),
  routes,
});

const app = createApp({ template: '<RouterView />' });
app.use(i18n);
app.use(router);
app.mount('#affiliate-portal-app');
