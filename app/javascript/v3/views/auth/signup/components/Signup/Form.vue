<script setup>
import { ref, computed, reactive } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength, email } from '@vuelidate/validators';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import VueHcaptcha from '@hcaptcha/vue3-hcaptcha';
import Spinner from 'shared/components/Spinner.vue';
import PasswordRequirements from './PasswordRequirements.vue';
import { isValidPassword } from 'shared/helpers/Validators';
import GoogleOAuthButton from '../../../../../components/GoogleOauth/Button.vue';
import { register } from '../../../../../api/auth';

const MIN_PASSWORD_LENGTH = 6;

const store = useStore();
const { t } = useI18n();
const router = useRouter();

const hCaptcha = ref(null);
const isPasswordFocused = ref(false);
const isSignupInProgress = ref(false);

const MIN_NAME_LENGTH = 2;

const credentials = reactive({
  fullName: '',
  accountName: '',
  email: '',
  password: '',
  hCaptchaClientResponse: '',
});

const rules = {
  credentials: {
    fullName: {
      required,
      minLength: minLength(MIN_NAME_LENGTH),
    },
    accountName: {
      required,
      minLength: minLength(MIN_NAME_LENGTH),
    },
    email: {
      required,
      email,
    },
    password: {
      required,
      isValidPassword,
      minLength: minLength(MIN_PASSWORD_LENGTH),
    },
  },
};

const v$ = useVuelidate(rules, { credentials });

const globalConfig = computed(() => store.getters['globalConfig/get']);

const termsLink = computed(() =>
  t('REGISTER.TERMS_ACCEPT')
    .replace('https://www.jabvox.com/terms', globalConfig.value.termsURL)
    .replace(
      'https://www.jabvox.com/privacy-policy',
      globalConfig.value.privacyURL
    )
);

const allowedLoginMethods = computed(
  () => window.jabvoxConfig.allowedLoginMethods || ['email']
);

const showGoogleOAuth = computed(
  () =>
    allowedLoginMethods.value.includes('google_oauth') &&
    Boolean(window.jabvoxConfig.googleOAuthClientId)
);

const isFormValid = computed(() => !v$.value.$invalid);

const performRegistration = async () => {
  isSignupInProgress.value = true;
  try {
    await register(credentials);
    router.push({
      name: 'auth_verify_email',
      state: { email: credentials.email },
    });
  } catch (error) {
    const errorMessage = error?.message || t('REGISTER.API.ERROR_MESSAGE');
    if (globalConfig.value.hCaptchaSiteKey) {
      hCaptcha.value.reset();
      credentials.hCaptchaClientResponse = '';
    }
    useAlert(errorMessage);
  } finally {
    isSignupInProgress.value = false;
  }
};

const submit = () => {
  if (isSignupInProgress.value) return;
  v$.value.$touch();
  if (v$.value.$invalid) return;
  isSignupInProgress.value = true;
  if (globalConfig.value.hCaptchaSiteKey) {
    hCaptcha.value.execute();
  } else {
    performRegistration();
  }
};

const onRecaptchaVerified = token => {
  credentials.hCaptchaClientResponse = token;
  performRegistration();
};

const onCaptchaError = () => {
  isSignupInProgress.value = false;
  credentials.hCaptchaClientResponse = '';
  hCaptcha.value.reset();
};
</script>

<template>
  <div class="jabvox-signup">
    <form @submit.prevent="submit">
      <div class="jabvox-field">
        <label class="jabvox-label">{{ $t('REGISTER.FULL_NAME.LABEL') }}</label>
        <input
          v-model="credentials.fullName"
          type="text"
          name="full_name"
          :placeholder="$t('REGISTER.FULL_NAME.PLACEHOLDER')"
          class="jabvox-input"
          :class="{ 'jabvox-input-error': v$.credentials.fullName.$error }"
          :tabindex="1"
          @blur="v$.credentials.fullName.$touch"
        />
        <span v-if="v$.credentials.fullName.$error" class="jabvox-error">
          {{ $t('REGISTER.FULL_NAME.ERROR') }}
        </span>
      </div>

      <div class="jabvox-field">
        <label class="jabvox-label">{{
          $t('REGISTER.COMPANY_NAME.LABEL')
        }}</label>
        <input
          v-model="credentials.accountName"
          type="text"
          name="account_name"
          :placeholder="$t('REGISTER.COMPANY_NAME.PLACEHOLDER')"
          class="jabvox-input"
          :class="{ 'jabvox-input-error': v$.credentials.accountName.$error }"
          :tabindex="2"
          @blur="v$.credentials.accountName.$touch"
        />
        <span v-if="v$.credentials.accountName.$error" class="jabvox-error">
          {{ $t('REGISTER.COMPANY_NAME.ERROR') }}
        </span>
      </div>

      <div class="jabvox-field">
        <label class="jabvox-label">{{ $t('REGISTER.EMAIL.LABEL') }}</label>
        <input
          v-model="credentials.email"
          type="email"
          name="email_address"
          :placeholder="$t('REGISTER.EMAIL.PLACEHOLDER')"
          class="jabvox-input"
          :class="{ 'jabvox-input-error': v$.credentials.email.$error }"
          :tabindex="3"
          @blur="v$.credentials.email.$touch"
        />
        <span v-if="v$.credentials.email.$error" class="jabvox-error">
          {{ $t('REGISTER.EMAIL.ERROR') }}
        </span>
      </div>

      <div class="jabvox-field">
        <label class="jabvox-label">{{ $t('LOGIN.PASSWORD.LABEL') }}</label>
        <div class="relative">
          <input
            v-model="credentials.password"
            type="password"
            name="password"
            :placeholder="$t('SET_NEW_PASSWORD.PASSWORD.PLACEHOLDER')"
            class="jabvox-input"
            :class="{ 'jabvox-input-error': v$.credentials.password.$error }"
            :tabindex="4"
            @focus="isPasswordFocused = true"
            @blur="
              isPasswordFocused = false;
              v$.credentials.password.$touch();
            "
          />
          <Transition
            enter-active-class="transition duration-200 ease-out origin-left"
            enter-from-class="opacity-0 scale-90 translate-x-1"
            enter-to-class="opacity-100 scale-100 translate-x-0"
            leave-active-class="transition duration-150 ease-in origin-left"
            leave-from-class="opacity-100 scale-100 translate-x-0"
            leave-to-class="opacity-0 scale-90 translate-x-1"
          >
            <PasswordRequirements
              v-if="isPasswordFocused"
              :password="credentials.password"
            />
          </Transition>
        </div>
      </div>

      <VueHcaptcha
        v-if="globalConfig.hCaptchaSiteKey"
        ref="hCaptcha"
        size="invisible"
        :sitekey="globalConfig.hCaptchaSiteKey"
        @verify="onRecaptchaVerified"
        @error="onCaptchaError"
        @expired="onCaptchaError"
        @challenge-expired="onCaptchaError"
        @closed="onCaptchaError"
      />

      <button
        type="submit"
        data-testid="submit_button"
        class="jabvox-btn"
        :tabindex="5"
        :disabled="isSignupInProgress || !isFormValid"
      >
        <Spinner v-if="isSignupInProgress" color-scheme="" size="small" />
        <span v-else>{{ $t('REGISTER.SUBMIT') }}</span>
      </button>
    </form>

    <GoogleOAuthButton v-if="showGoogleOAuth" class="mt-3">
      {{ $t('REGISTER.OAUTH.GOOGLE_SIGNUP') }}
    </GoogleOAuthButton>

    <p class="jabvox-terms" v-html="termsLink" />
  </div>
</template>

<style scoped>
.jabvox-signup {
  font-family: 'Comfortaa', sans-serif;
}
.jabvox-field {
  margin-bottom: 1.1rem;
}
.jabvox-label {
  display: block;
  font-size: 0.75rem;
  color: #24292d;
  margin-bottom: 0.4rem;
}
.jabvox-input {
  width: 100%;
  padding: 0.7rem 1rem;
  border: 1px solid #daebdb;
  border-radius: 0.5rem;
  font-size: 0.875rem;
  /* Fuerza el color del texto: sin esto, un estilo global de la app puede
     dejar el texto blanco/transparente y el correo escrito no se ve. */
  color: #24292d !important;
  -webkit-text-fill-color: #24292d;
  background: #ffffff !important;
  outline: none;
  font-family: 'Comfortaa', sans-serif;
  transition:
    border-color 0.2s,
    box-shadow 0.2s;
  box-sizing: border-box;
}
.jabvox-input::placeholder {
  color: #9aa3a0;
  opacity: 1;
}
.jabvox-input:focus {
  border-color: #40b5b4;
  box-shadow: 0 0 0 3px rgba(64, 181, 180, 0.15);
}
/* Evita que el autofill del navegador pinte el texto de blanco/amarillo. */
.jabvox-input:-webkit-autofill,
.jabvox-input:-webkit-autofill:focus {
  -webkit-text-fill-color: #24292d;
  box-shadow: 0 0 0 1000px #ffffff inset;
}
.jabvox-input-error {
  border-color: #e5484d;
}
.jabvox-error {
  display: block;
  margin-top: 0.3rem;
  font-size: 0.7rem;
  color: #e5484d;
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
.jabvox-btn:hover:not(:disabled) {
  background: #40b5b4;
}
.jabvox-btn:disabled {
  opacity: 0.7;
  cursor: not-allowed;
}
.jabvox-terms {
  font-size: 0.72rem;
  margin-top: 1.25rem;
  margin-bottom: 0;
  color: #5c635d;
  text-align: center;
}
.jabvox-terms :deep(a) {
  color: #59b995;
  font-weight: 500;
  text-decoration: none;
}
.jabvox-terms :deep(a:hover) {
  color: #40b5b4;
}
</style>
