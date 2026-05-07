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
const showPassword = ref(false);

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

<!-- eslint-disable vue/no-bare-strings-in-template -->
<template>
  <div class="af-layout">
    <!-- LEFT PANEL -->
    <div class="af-left">
      <div class="af-left-bg" />
      <div class="af-left-content">
        <p class="af-left-title">
          Portal de<br />
          <span>Afiliados.</span>
        </p>
        <p class="af-left-subtitle">Accede a tu espacio personal de afiliado</p>
      </div>
    </div>

    <!-- RIGHT PANEL -->
    <div class="af-right">
      <div class="af-form-box">
        <img src="/jabvox/public/logo.png" alt="Jabvox" class="af-logo" />
        <h1 class="af-form-title">Portal de Afiliados</h1>
        <p class="af-form-subtitle">Ingresa tus credenciales para continuar</p>

        <form class="af-form" @submit.prevent="onLogin">
          <div class="af-field">
            <label class="af-label">
              {{ t('JABVOX_AFFILIATE_PORTAL.ACCOUNT_CODE_LABEL') }}
            </label>
            <input
              v-model="accountCode"
              type="text"
              :placeholder="
                t('JABVOX_AFFILIATE_PORTAL.ACCOUNT_CODE_PLACEHOLDER')
              "
              autocomplete="username"
              class="af-input"
            />
          </div>

          <div class="af-field">
            <label class="af-label">
              {{ t('JABVOX_AFFILIATE_PORTAL.TOKEN_LABEL') }}
            </label>
            <div class="af-pass-wrap">
              <input
                v-model="authToken"
                :type="showPassword ? 'text' : 'password'"
                :placeholder="t('JABVOX_AFFILIATE_PORTAL.TOKEN_PLACEHOLDER')"
                autocomplete="current-password"
                class="af-input af-input-pass"
              />
              <button
                type="button"
                class="af-eye"
                @click="showPassword = !showPassword"
              >
                <svg
                  v-if="!showPassword"
                  xmlns="http://www.w3.org/2000/svg"
                  width="18"
                  height="18"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                  />
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                  />
                </svg>
                <svg
                  v-else
                  xmlns="http://www.w3.org/2000/svg"
                  width="18"
                  height="18"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="1.5"
                    d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 4.411m0 0L21 21"
                  />
                </svg>
              </button>
            </div>
          </div>

          <p v-if="errorMsg" class="af-error">
            {{ errorMsg }}
          </p>

          <button type="submit" :disabled="isLoading" class="af-btn">
            <span v-if="!isLoading">
              {{ t('JABVOX_AFFILIATE_PORTAL.LOGIN_BUTTON') }}
            </span>
            <span v-else>
              {{ t('JABVOX_AFFILIATE_PORTAL.LOGGING_IN') }}
            </span>
          </button>
        </form>
      </div>
    </div>
  </div>
</template>

<style>
@font-face {
  font-family: 'Comfortaa';
  src: url('/jabvox/public/fonts/Comfortaa-Light.ttf') format('truetype');
  font-weight: 300;
}
.af-layout {
  display: flex;
  width: 100vw;
  height: 100vh;
  overflow: hidden;
  background-image: url('/jabvox/public/login-bg.jpg');
  background-size: cover;
  background-position: center;
  font-family: 'Comfortaa', sans-serif;
}
.af-left {
  display: none;
  width: 50%;
  height: 100%;
  position: relative;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  padding: 4rem;
}
@media (min-width: 1024px) {
  .af-left {
    display: flex;
  }
}
.af-left-bg {
  display: none;
}
.af-left-content {
  position: relative;
  z-index: 1;
  text-align: center;
}
.af-left-title {
  font-size: 2.75rem;
  font-weight: 300;
  line-height: 1.25;
  color: #24292d;
  font-family: 'Comfortaa', sans-serif;
}
.af-left-title span {
  color: #15605a;
}
.af-left-subtitle {
  font-size: 1rem;
  font-weight: 300;
  color: #24292d;
  margin-top: 1rem;
  font-family: 'Comfortaa', sans-serif;
}
.af-right {
  flex: 1;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
}
.af-form-box {
  background: #ffffff;
  border-radius: 1rem;
  padding: 2rem 2.5rem;
  width: 100%;
  max-width: 420px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
  font-family: 'Comfortaa', sans-serif;
}
.af-logo {
  height: 4rem;
  width: auto;
  display: block;
  margin: 0 auto 1.5rem;
}
.af-form-title {
  font-size: 1.4rem;
  font-weight: 300;
  color: #15605a;
  margin-bottom: 0.25rem;
  text-align: center;
}
.af-form-subtitle {
  font-size: 0.8rem;
  color: #40b5b4;
  margin-bottom: 1.25rem;
  text-align: center;
}
.af-form {
  display: flex;
  flex-direction: column;
  gap: 0;
}
.af-field {
  margin-bottom: 0.6rem;
}
.af-label {
  display: block;
  font-size: 0.75rem;
  color: #24292d;
  margin-bottom: 0.4rem;
  font-family: 'Comfortaa', sans-serif;
}
.af-input {
  width: 100%;
  padding: 0.7rem 1rem;
  border: 1px solid #daebdb;
  border-radius: 0.5rem;
  font-size: 0.875rem;
  color: #24292d;
  background: #ffffff;
  outline: none;
  font-family: 'Comfortaa', sans-serif;
  transition:
    border-color 0.2s,
    box-shadow 0.2s;
  box-sizing: border-box;
}
.af-input:focus {
  border-color: #40b5b4;
  box-shadow: 0 0 0 3px rgba(64, 181, 180, 0.15);
}
.af-pass-wrap {
  position: relative;
}
.af-input-pass {
  padding-right: 3rem;
}
.af-eye {
  position: absolute;
  right: 0.75rem;
  top: 50%;
  transform: translateY(-50%);
  background: none;
  border: none;
  cursor: pointer;
  color: #59b995;
  display: flex;
  align-items: center;
  padding: 0.2rem;
}
.af-error {
  font-size: 0.8rem;
  color: #e03e3e;
  background: #fff0f0;
  border-radius: 0.5rem;
  padding: 0.6rem 0.875rem;
  margin-bottom: 0.75rem;
}
.af-btn {
  width: 100%;
  padding: 0.8rem;
  border: none;
  border-radius: 0.5rem;
  background: #15605a;
  color: #ffffff;
  font-size: 0.875rem;
  font-weight: 300;
  cursor: pointer;
  margin-top: 0.25rem;
  font-family: 'Comfortaa', sans-serif;
  transition: background 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
}
.af-btn:hover {
  background: #40b5b4;
}
.af-btn:disabled {
  opacity: 0.7;
  cursor: not-allowed;
}
</style>
