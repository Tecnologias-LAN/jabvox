<script setup>
import { ref } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import affiliatePortalAPI from '../../api/jabvox/affiliatePortal';

const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const portalAccountId = route.params.portalAccountId;
const affiliateSlug = route.params.affiliateSlug;

const accountCode = ref('');
const authToken = ref('');
const isLoading = ref(false);
const errorMsg = ref('');

const ERROR_KEYS = {
  invalid_credentials: 'JABVOX_AFFILIATE_PORTAL.ERROR_INVALID_CREDENTIALS',
  module_disabled: 'JABVOX_AFFILIATE_PORTAL.ERROR_MODULE_DISABLED',
  ip_blocked: 'JABVOX_AFFILIATE_PORTAL.ERROR_IP_BLOCKED',
};

const onLogin = async () => {
  errorMsg.value = '';
  if (!accountCode.value.trim() || !authToken.value.trim()) {
    errorMsg.value = t('JABVOX_AFFILIATE_PORTAL.FILL_ALL_FIELDS');
    return;
  }
  isLoading.value = true;
  try {
    const { data } = await affiliatePortalAPI.login(
      affiliateSlug,
      accountCode.value.trim(),
      authToken.value.trim()
    );
    localStorage.setItem('jabvox_affiliate_token', data.token);
    localStorage.setItem('jabvox_affiliate_name', data.affiliate.name);
    localStorage.setItem('jabvox_affiliate_slug', affiliateSlug);
    localStorage.setItem(
      'jabvox_affiliate_expires',
      String(Date.now() + data.expires_in * 1000)
    );
    await router.push({
      name: 'affiliate_portal_leads',
      params: { portalAccountId, affiliateSlug },
    });
  } catch (err) {
    const key = err.response?.data?.error;
    errorMsg.value = t(
      ERROR_KEYS[key] ?? 'JABVOX_AFFILIATE_PORTAL.ERROR_DEFAULT'
    );
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <div
    class="min-h-screen flex items-center justify-center bg-n-surface-1 px-4"
  >
    <div class="w-full max-w-sm">
      <div
        class="rounded-2xl border border-n-weak bg-n-surface-2 p-8 shadow-sm"
      >
        <div class="text-center mb-6">
          <div
            class="inline-flex items-center justify-center w-12 h-12 rounded-2xl bg-n-brand/10 mb-3"
          >
            <span class="i-lucide-users text-n-brand size-6" />
          </div>
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ t('JABVOX_AFFILIATE_PORTAL.TITLE') }}
          </h1>
          <p class="text-sm text-n-slate-11 mt-1">
            {{ t('JABVOX_AFFILIATE_PORTAL.LOGIN_SUBTITLE') }}
          </p>
        </div>

        <form class="space-y-4" @submit.prevent="onLogin">
          <div>
            <label class="block text-sm font-medium text-n-slate-12 mb-1.5">
              {{ t('JABVOX_AFFILIATE_PORTAL.ACCOUNT_CODE_LABEL') }}
            </label>
            <input
              v-model="accountCode"
              type="text"
              :placeholder="
                t('JABVOX_AFFILIATE_PORTAL.ACCOUNT_CODE_PLACEHOLDER')
              "
              autocomplete="username"
              class="w-full h-10 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-n-slate-12 mb-1.5">
              {{ t('JABVOX_AFFILIATE_PORTAL.TOKEN_LABEL') }}
            </label>
            <input
              v-model="authToken"
              type="password"
              :placeholder="t('JABVOX_AFFILIATE_PORTAL.TOKEN_PLACEHOLDER')"
              autocomplete="current-password"
              class="w-full h-10 rounded-lg border border-n-weak bg-n-surface-1 px-3 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
            />
          </div>

          <p
            v-if="errorMsg"
            class="text-sm text-n-ruby-9 rounded-lg bg-n-ruby-3 px-3 py-2"
          >
            {{ errorMsg }}
          </p>

          <button
            type="submit"
            :disabled="isLoading"
            class="w-full h-10 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
          >
            {{
              isLoading
                ? t('JABVOX_AFFILIATE_PORTAL.LOGGING_IN')
                : t('JABVOX_AFFILIATE_PORTAL.LOGIN_BUTTON')
            }}
          </button>
        </form>
      </div>
    </div>
  </div>
</template>
