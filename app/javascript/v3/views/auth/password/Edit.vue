<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { DEFAULT_REDIRECT_URL } from 'dashboard/constants/globals';
import { setNewPassword } from '../../../api/auth';

export default {
  props: {
    resetPasswordToken: { type: String, default: '' },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      jabvoxLogoUrl: '/jabvox/public/logo.png',
      jabvoxLogoAlt: 'Jabvox',
      credentials: {
        confirmPassword: '',
        password: '',
      },
      newPasswordAPI: {
        message: '',
        showLoading: false,
      },
      error: '',
    };
  },
  mounted() {
    // Si se abre sin token, volver al login.
    if (!this.resetPasswordToken) {
      window.location = DEFAULT_REDIRECT_URL;
    }
  },
  validations: {
    credentials: {
      password: {
        required,
        minLength: minLength(6),
      },
      confirmPassword: {
        required,
        minLength: minLength(6),
        isEqPassword(value) {
          if (value !== this.credentials.password) {
            return false;
          }
          return true;
        },
      },
    },
  },
  methods: {
    showAlertMessage(message) {
      this.newPasswordAPI.showLoading = false;
      useAlert(message);
    },
    submitForm() {
      this.newPasswordAPI.showLoading = true;
      const credentials = {
        confirmPassword: this.credentials.confirmPassword,
        password: this.credentials.password,
        resetPasswordToken: this.resetPasswordToken,
      };
      setNewPassword(credentials)
        .then(() => {
          window.location = DEFAULT_REDIRECT_URL;
        })
        .catch(error => {
          this.showAlertMessage(
            error?.message || this.$t('SET_NEW_PASSWORD.API.ERROR_MESSAGE')
          );
        });
    },
  },
};
</script>

<template>
  <div class="jabvox-pwedit-layout">
    <div class="jabvox-pwedit-bg" />
    <div class="jabvox-pwedit-center">
      <div class="jabvox-pwedit-box">
        <img
          :src="jabvoxLogoUrl"
          :alt="jabvoxLogoAlt"
          class="jabvox-pwedit-logo"
        />
        <h1 class="jabvox-pwedit-title">
          {{ $t('SET_NEW_PASSWORD.TITLE') }}
        </h1>
        <form @submit.prevent="submitForm">
          <div class="jabvox-pwedit-field">
            <label class="jabvox-pwedit-label">
              {{ $t('SET_NEW_PASSWORD.PASSWORD.LABEL') }}
            </label>
            <input
              v-model="credentials.password"
              type="password"
              name="password"
              class="jabvox-pwedit-input"
              :placeholder="$t('SET_NEW_PASSWORD.PASSWORD.PLACEHOLDER')"
              @blur="v$.credentials.password.$touch"
            />
            <span
              v-if="v$.credentials.password.$error"
              class="jabvox-pwedit-error"
            >
              {{ $t('SET_NEW_PASSWORD.PASSWORD.ERROR') }}
            </span>
          </div>
          <div class="jabvox-pwedit-field">
            <label class="jabvox-pwedit-label">
              {{ $t('SET_NEW_PASSWORD.CONFIRM_PASSWORD.LABEL') }}
            </label>
            <input
              v-model="credentials.confirmPassword"
              type="password"
              name="confirm_password"
              class="jabvox-pwedit-input"
              :placeholder="$t('SET_NEW_PASSWORD.CONFIRM_PASSWORD.PLACEHOLDER')"
              @blur="v$.credentials.confirmPassword.$touch"
            />
            <span
              v-if="v$.credentials.confirmPassword.$error"
              class="jabvox-pwedit-error"
            >
              {{ $t('SET_NEW_PASSWORD.CONFIRM_PASSWORD.ERROR') }}
            </span>
          </div>
          <button
            type="submit"
            data-testid="submit_button"
            class="jabvox-pwedit-btn"
            :disabled="
              v$.credentials.password.$invalid ||
              v$.credentials.confirmPassword.$invalid ||
              newPasswordAPI.showLoading
            "
          >
            <span v-if="!newPasswordAPI.showLoading">
              {{ $t('SET_NEW_PASSWORD.SUBMIT') }}
            </span>
            <span v-else>{{ $t('SET_NEW_PASSWORD.SUBMITTING') }}</span>
          </button>
        </form>
      </div>
    </div>
  </div>
</template>

<style>
.jabvox-pwedit-layout {
  position: relative;
  width: 100vw;
  height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Comfortaa', sans-serif;
}
.jabvox-pwedit-bg {
  position: absolute;
  inset: 0;
  background-image: url('/jabvox/public/login-bg.jpg');
  background-size: cover;
  background-position: center;
  z-index: 0;
}
.jabvox-pwedit-center {
  position: relative;
  z-index: 1;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
}
.jabvox-pwedit-box {
  background: #ffffff;
  border-radius: 1rem;
  padding: 2.5rem;
  width: 100%;
  max-width: 420px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
}
.jabvox-pwedit-logo {
  height: 4rem;
  width: auto;
  display: block;
  margin: 0 auto 1.75rem;
}
.jabvox-pwedit-title {
  font-size: 1.4rem;
  font-weight: 300;
  color: #15605a;
  text-align: center;
  margin-bottom: 1.75rem;
}
.jabvox-pwedit-field {
  margin-bottom: 1.25rem;
}
.jabvox-pwedit-label {
  display: block;
  font-size: 0.75rem;
  color: #24292d;
  margin-bottom: 0.4rem;
}
.jabvox-pwedit-input {
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
.jabvox-pwedit-input:focus {
  border-color: #40b5b4;
  box-shadow: 0 0 0 3px rgba(64, 181, 180, 0.15);
}
.jabvox-pwedit-error {
  display: block;
  margin-top: 0.4rem;
  font-size: 0.72rem;
  color: #e5484d;
}
.jabvox-pwedit-btn {
  width: 100%;
  padding: 0.8rem;
  border: none;
  border-radius: 0.5rem;
  background: #15605a;
  color: #ffffff;
  font-size: 0.875rem;
  font-weight: 300;
  cursor: pointer;
  font-family: 'Comfortaa', sans-serif;
  transition: background 0.2s;
  margin-top: 0.25rem;
}
.jabvox-pwedit-btn:hover:not(:disabled) {
  background: #40b5b4;
}
.jabvox-pwedit-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
</style>
