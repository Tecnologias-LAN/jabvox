<script>
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required, minLength, email } from '@vuelidate/validators';
import { useBranding } from 'shared/composables/useBranding';
import FormInput from '../../../../components/Form/Input.vue';
import { resetPassword } from '../../../../api/auth';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: { FormInput, NextButton },
  setup() {
    const { replaceInstallationName } = useBranding();
    return { v$: useVuelidate(), replaceInstallationName };
  },
  data() {
    return {
      credentials: { email: '' },
      resetPassword: {
        message: '',
        showLoading: false,
      },
      error: '',
    };
  },
  validations() {
    return {
      credentials: {
        email: {
          required,
          email,
          minLength: minLength(4),
        },
      },
    };
  },
  methods: {
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.resetPassword.showLoading = false;
      useAlert(message);
    },
    submit() {
      this.resetPassword.showLoading = true;
      resetPassword(this.credentials)
        .then(res => {
          let successMessage = this.$t('RESET_PASSWORD.API.SUCCESS_MESSAGE');
          if (res.data && res.data.message) {
            successMessage = res.data.message;
          }
          this.showAlertMessage(successMessage);
        })
        .catch(error => {
          let errorMessage = this.$t('RESET_PASSWORD.API.ERROR_MESSAGE');
          if (error?.response?.data?.message) {
            errorMessage = error.response.data.message;
          }
          this.showAlertMessage(errorMessage);
        });
    },
  },
};
</script>

<template>
  <div class="jabvox-reset-layout">
    <div class="jabvox-reset-bg" />
    <div class="jabvox-reset-center">
      <div class="jabvox-reset-box">
        <img :src="'/jabvox/public/logo.png'" alt="Jabvox" class="jabvox-reset-logo" />
        <h1 class="jabvox-reset-title">¿Olvidaste tu contraseña?</h1>
        <p class="jabvox-reset-subtitle">Ingresa tu correo y te enviaremos instrucciones para restablecerla</p>
        <form @submit.prevent="submit">
          <div class="jabvox-reset-field">
            <label class="jabvox-reset-label">Correo electrónico</label>
            <input
              v-model="credentials.email"
              type="email"
              name="email_address"
              class="jabvox-reset-input"
              :placeholder="$t('RESET_PASSWORD.EMAIL.PLACEHOLDER')"
              @input="v$.credentials.email.$touch"
            />
          </div>
          <button
            type="submit"
            class="jabvox-reset-btn"
            :disabled="v$.credentials.email.$invalid || resetPassword.showLoading"
          >
            <span v-if="!resetPassword.showLoading">Enviar instrucciones</span>
            <span v-else>Enviando...</span>
          </button>
        </form>
        <p class="jabvox-reset-back">
          <router-link to="/auth/login">← Volver al inicio de sesión</router-link>
        </p>
      </div>
    </div>
  </div>
</template>

<style>
.jabvox-reset-layout {
  position: relative;
  width: 100vw;
  height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Comfortaa', sans-serif;
}
.jabvox-reset-bg {
  position: absolute;
  inset: 0;
  background-image: url('/jabvox/public/login-bg.jpg');
  background-size: cover;
  background-position: center;
  z-index: 0;
}
.jabvox-reset-center {
  position: relative;
  z-index: 1;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
}
.jabvox-reset-box {
  background: #FFFFFF;
  border-radius: 1rem;
  padding: 2.5rem;
  width: 100%;
  max-width: 420px;
  box-shadow: 0 8px 32px rgba(0,0,0,0.12);
}
.jabvox-reset-logo {
  height: 4rem;
  width: auto;
  display: block;
  margin: 0 auto 1.75rem;
}
.jabvox-reset-title {
  font-size: 1.4rem;
  font-weight: 300;
  color: #15605A;
  text-align: center;
  margin-bottom: 0.5rem;
}
.jabvox-reset-subtitle {
  font-size: 0.8rem;
  color: #40B5B4;
  text-align: center;
  margin-bottom: 1.75rem;
  line-height: 1.5;
}
.jabvox-reset-field { margin-bottom: 1.25rem; }
.jabvox-reset-label {
  display: block;
  font-size: 0.75rem;
  color: #24292D;
  margin-bottom: 0.4rem;
}
.jabvox-reset-input {
  width: 100%;
  padding: 0.7rem 1rem;
  border: 1px solid #DAEBDB;
  border-radius: 0.5rem;
  font-size: 0.875rem;
  color: #24292D;
  background: #FFFFFF;
  outline: none;
  font-family: 'Comfortaa', sans-serif;
  transition: border-color 0.2s, box-shadow 0.2s;
  box-sizing: border-box;
}
.jabvox-reset-input:focus {
  border-color: #40B5B4;
  box-shadow: 0 0 0 3px rgba(64,181,180,0.15);
}
.jabvox-reset-btn {
  width: 100%;
  padding: 0.8rem;
  border: none;
  border-radius: 0.5rem;
  background: #15605A;
  color: #FFFFFF;
  font-size: 0.875rem;
  font-weight: 300;
  cursor: pointer;
  font-family: 'Comfortaa', sans-serif;
  transition: background 0.2s;
  margin-top: 0.25rem;
}
.jabvox-reset-btn:hover:not(:disabled) { background: #40B5B4; }
.jabvox-reset-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.jabvox-reset-back {
  text-align: center;
  margin-top: 1.25rem;
  font-size: 0.75rem;
}
.jabvox-reset-back a { color: #59B995; text-decoration: none; }
.jabvox-reset-back a:hover { color: #40B5B4; }
</style>
