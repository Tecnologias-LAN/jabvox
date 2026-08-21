<script setup>
import SignupForm from './components/Signup/Form.vue';

// Logo servido desde el branding de Jabvox (mismo que el login).
const jabvoxLogoUrl = '/jabvox/public/logo.png';
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="jabvox-login-layout">
    <!-- PANEL IZQUIERDO: branding -->
    <div class="jabvox-left">
      <div class="jabvox-left-content">
        <p class="jabvox-left-title">
          Empieza hoy<br />
          <span>a potenciar</span><br />
          tu negocio con jabvox
        </p>
      </div>
    </div>

    <!-- PANEL DERECHO: formulario de registro -->
    <div class="jabvox-right">
      <div class="jabvox-form-box">
        <img :src="jabvoxLogoUrl" alt="Jabvox" class="jabvox-logo" />
        <h1 class="jabvox-form-title">Crea tu cuenta</h1>
        <p class="jabvox-form-subtitle">
          Regístrate y comienza tu experiencia con Jabvox
        </p>

        <SignupForm />

        <p class="jabvox-forgot jabvox-signup-alt">
          ¿Ya tienes cuenta?
          <router-link to="/app/login" tabindex="6">
            Inicia sesión
          </router-link>
        </p>
      </div>
    </div>
  </div>
</template>

<style scoped>
@font-face {
  font-family: 'Comfortaa';
  src: url('/jabvox/public/fonts/Comfortaa-Light.ttf') format('truetype');
  font-weight: 300;
}
.jabvox-login-layout {
  display: flex;
  width: 100vw;
  min-height: 100vh;
  overflow-y: auto;
  background-image: url('/jabvox/public/login-bg.jpg');
  background-size: cover;
  background-position: center;
  font-family: 'Comfortaa', sans-serif;
}
.jabvox-left {
  display: none;
  width: 50%;
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
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 2rem 1rem;
}
.jabvox-form-box {
  background: #ffffff;
  border-radius: 1rem;
  padding: 2rem 2.5rem;
  width: 100%;
  max-width: 440px;
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
.jabvox-forgot {
  text-align: center;
  margin-top: 1rem;
  font-size: 0.75rem;
  color: #24292d;
}
.jabvox-signup-alt {
  border-top: 1px solid #eef4ef;
  padding-top: 1rem;
}
.jabvox-forgot a {
  color: #59b995;
  text-decoration: none;
  font-weight: 500;
}
.jabvox-forgot a:hover {
  color: #40b5b4;
}
</style>
