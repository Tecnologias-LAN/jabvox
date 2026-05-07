<!-- eslint-disable vue/no-bare-strings-in-template -->
<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';

/* eslint-disable vue/no-unused-components */
export default {
  components: {
    FormInput,
    GoogleOAuthButton,
    Spinner,
    NextButton,
    SimpleDivider,
    MfaVerification,
    Icon,
  } /* eslint-enable vue/no-unused-components */,
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      jabvoxLogoUrl: '/jabvox/public/logo.png',
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
      showPassword: false,
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showGoogleOAuth() {
      return (
        this.allowedLoginMethods.includes('google_oauth') &&
        Boolean(window.chatwootConfig.googleOAuthClientId)
      );
    },
    showSignupLink() {
      return window.chatwootConfig.signupEnabled === 'true';
    },
    showSamlLogin() {
      return this.allowedLoginMethods.includes('saml');
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
    if (this.authError) {
      const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
      // Use a method to get the translated text to avoid dynamic key warning
      const translatedMessage = this.getTranslatedMessage(messageKey);
      useAlert(translatedMessage);
      // wait for idle state
      this.requestIdleCallbackPolyfill(() => {
        // Remove the error query param from the url
        const { query } = this.$route;
        this.$router.replace({ query: { ...query, error: undefined } });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      // Avoid dynamic key warning by handling each case explicitly
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    // TODO: Remove this when Safari gets wider support
    // Ref: https://caniuse.com/requestidlecallback
    //
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        // Fallback for safari
        // Using a delay of 0 allows the callback to be executed asynchronously
        // in the next available event loop iteration, similar to requestIdleCallback
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      // Detects impersonation mode via URL and sets a session flag to prevent user settings changes during impersonation.
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      };

      login(credentials)
        .then(result => {
          // Check if MFA is required
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          // Reset URL Params if the authentication is invalid
          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified() {
      // MFA verification successful, continue with login
      this.handleImpersonation();
      window.location = '/app';
    },
    handleMfaCancel() {
      // User cancelled MFA, reset state
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
    },
  },
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="jabvox-login-layout">
    <!-- LEFT PANEL -->
    <div class="jabvox-left">
      <div class="jabvox-left-bg" />
      <div class="jabvox-left-content">
        <p class="jabvox-left-title">
          Conecta<br />
          <span>tu comunidad</span><br />
          en un solo lugar con jabvox
        </p>
      </div>
    </div>

    <!-- RIGHT PANEL -->
    <div class="jabvox-right">
      <!-- MFA -->
      <div v-if="mfaRequired" class="jabvox-form-box">
        <MfaVerification
          :mfa-token="mfaToken"
          @verified="handleMfaVerified"
          @cancel="handleMfaCancel"
        />
      </div>

      <!-- Login form -->
      <div
        v-else
        class="jabvox-form-box"
        :class="{ 'animate-wiggle': loginApi.hasErrored }"
      >
        <img :src="jabvoxLogoUrl" alt="Jabvox" class="jabvox-logo" />
        <h1 class="jabvox-form-title">Bienvenido a Jabvox</h1>
        <p class="jabvox-form-subtitle">Inicia sesión para continuar</p>

        <div v-if="!email">
          <GoogleOAuthButton v-if="showGoogleOAuth" class="mb-4" />

          <form @submit.prevent="submitFormLogin">
            <div class="jabvox-field">
              <label class="jabvox-label">Usuario</label>
              <input
                v-model="credentials.email"
                type="text"
                name="email_address"
                data-testid="email_input"
                placeholder="Usuario"
                class="jabvox-input"
                :tabindex="1"
                required
                @input="v$.credentials.email.$touch"
              />
            </div>

            <div class="jabvox-field">
              <label class="jabvox-label">Contraseña</label>
              <div class="jabvox-pass-wrap">
                <input
                  v-model="credentials.password"
                  :type="showPassword ? 'text' : 'password'"
                  name="password"
                  data-testid="password_input"
                  placeholder="••••••••"
                  class="jabvox-input jabvox-input-pass"
                  :tabindex="2"
                  required
                  @input="v$.credentials.password.$touch"
                />
                <button
                  type="button"
                  class="jabvox-eye"
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

            <button
              type="submit"
              data-testid="submit_button"
              class="jabvox-btn"
              :tabindex="3"
              :disabled="loginApi.showLoading"
            >
              <Spinner v-if="loginApi.showLoading" size="small" />
              <span v-else>Iniciar sesión</span>
            </button>
          </form>

          <p
            v-if="!globalConfig.disableUserProfileUpdate"
            class="jabvox-forgot"
          >
            <router-link to="auth/reset/password" tabindex="4">
              ¿Olvidaste tu contraseña?
            </router-link>
          </p>
        </div>

        <div v-else class="flex items-center justify-center py-8">
          <Spinner color-scheme="primary" size="" />
        </div>
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
.jabvox-login-layout {
  display: flex;
  width: 100vw;
  height: 100vh;
  overflow: hidden;
  background-image: url('/jabvox/public/login-bg.jpg');
  background-size: cover;
  background-position: center;
  font-family: 'Comfortaa', sans-serif;
}
.jabvox-left {
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
  .jabvox-left {
    display: flex;
  }
}
.jabvox-left-bg {
  display: none;
}
.jabvox-left-content {
  position: relative;
  z-index: 1;
  text-align: center;
}
.jabvox-left-title {
  font-size: 2.75rem;
  font-weight: 300;
  line-height: 1.25;
  color: #24292d;
  font-family: 'Comfortaa', sans-serif;
}
.jabvox-left-title span {
  color: #15605a;
}
.jabvox-right {
  flex: 1;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
}
.jabvox-form-box {
  background: #ffffff;
  border-radius: 1rem;
  padding: 2rem 2.5rem;
  width: 100%;
  max-width: 420px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
  font-family: 'Comfortaa', sans-serif;
}
.jabvox-logo {
  height: 4rem;
  width: auto;
  display: block;
  margin: 0 auto 1.5rem;
}
.jabvox-form-title {
  font-size: 1.4rem;
  font-weight: 300;
  color: #15605a;
  margin-bottom: 0.25rem;
  text-align: center;
}
.jabvox-form-subtitle {
  font-size: 0.8rem;
  color: #40b5b4;
  margin-bottom: 1.75rem;
  text-align: center;
}
.jabvox-field {
  margin-bottom: 1.1rem;
}
.jabvox-label {
  display: block;
  font-size: 0.75rem;
  color: #24292d;
  margin-bottom: 0.4rem;
  font-family: 'Comfortaa', sans-serif;
}
.jabvox-input {
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
.jabvox-input:focus {
  border-color: #40b5b4;
  box-shadow: 0 0 0 3px rgba(64, 181, 180, 0.15);
}
.jabvox-pass-wrap {
  position: relative;
}
.jabvox-input-pass {
  padding-right: 3rem;
}
.jabvox-eye {
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
.jabvox-btn {
  width: 100%;
  padding: 0.8rem;
  border: none;
  border-radius: 0.5rem;
  background: #15605a;
  color: #ffffff;
  font-size: 0.875rem;
  font-weight: 300;
  cursor: pointer;
  margin-top: 0.5rem;
  font-family: 'Comfortaa', sans-serif;
  transition: background 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
}
.jabvox-btn:hover {
  background: #40b5b4;
}
.jabvox-btn:disabled {
  opacity: 0.7;
  cursor: not-allowed;
}
.jabvox-forgot {
  text-align: right;
  margin-top: 1rem;
  font-size: 0.75rem;
}
.jabvox-forgot a {
  color: #59b995;
  text-decoration: none;
}
.jabvox-forgot a:hover {
  color: #40b5b4;
}
</style>
