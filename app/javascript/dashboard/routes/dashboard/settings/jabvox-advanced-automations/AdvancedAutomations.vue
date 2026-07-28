<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { advancedAutomationsAPI } from 'dashboard/api/jabvox/advancedAutomations';

const { t } = useI18n();

const STATE = { LOADING: 'loading', READY: 'ready', ERROR: 'error' };

const viewState = ref(STATE.LOADING);
const iframeUrl = ref('');
const iframeRef = ref(null);
// Mensaje de error ya localizado, listo para mostrar.
const errorMessage = ref('');
// Origin del que aceptamos postMessage. Se deriva de la url devuelta por el
// backend; cualquier mensaje de otro origin se ignora.
const allowedOrigin = ref('');

// Tema actual del dashboard: el body lleva la clase `dark` (ver themeHelper.js).
const currentTheme = () =>
  document.body.classList.contains('dark') ? 'dark' : 'light';

const originFromUrl = url => {
  try {
    return new URL(url).origin;
  } catch (e) {
    return '';
  }
};

const resolveErrorMessage = error => {
  const status = error?.response?.status;
  if (status === 403) {
    return t('JABVOX_ADVANCED_AUTOMATIONS.ERRORS.FORBIDDEN');
  }
  if (status === 503) {
    return t('JABVOX_ADVANCED_AUTOMATIONS.ERRORS.NOT_CONFIGURED');
  }
  return t('JABVOX_ADVANCED_AUTOMATIONS.ERRORS.GENERIC');
};

const requestToken = async () => {
  viewState.value = STATE.LOADING;
  try {
    const { data } = await advancedAutomationsAPI.ssoToken(currentTheme());
    if (!data?.url) {
      throw new Error('missing url');
    }
    allowedOrigin.value = originFromUrl(data.url);
    iframeUrl.value = data.url;
    viewState.value = STATE.READY;
  } catch (error) {
    errorMessage.value = resolveErrorMessage(error);
    viewState.value = STATE.ERROR;
  }
};

// Fuerza una recarga real del iframe pidiendo un token nuevo (el JWT es de un
// solo uso y expira en 5 min: solo sirve para la CARGA).
const reloadIframe = async () => {
  iframeUrl.value = '';
  await requestToken();
};

const postToIframe = payload => {
  const target = iframeRef.value?.contentWindow;
  if (target && allowedOrigin.value) {
    target.postMessage(payload, allowedOrigin.value);
  }
};

// Allow-list estricta de tipos de mensaje aceptados desde el iframe.
const handleMessage = async event => {
  // Origin debe coincidir EXACTAMENTE con el de Automations.
  if (!allowedOrigin.value || event.origin !== allowedOrigin.value) {
    return;
  }
  const type = event.data?.type;
  switch (type) {
    case 'ready':
      // El iframe termino de cargar; reafirmamos el tema actual.
      postToIframe({ type: 'theme', theme: currentTheme() });
      break;
    case 'resize':
      // Ajuste de alto opcional (el iframe ya ocupa el 100% del contenedor).
      break;
    case 'session-expired':
      // La sesion de Automation caduco: re-pedimos token y recargamos.
      reloadIframe();
      break;
    case 'permissions-check':
      try {
        const { data } = await advancedAutomationsAPI.permissionsCheck();
        postToIframe({ type: 'permissions-result', ok: !!data?.ok });
      } catch (error) {
        postToIframe({ type: 'permissions-result', ok: false });
      }
      break;
    default:
      // Cualquier otro tipo se ignora.
      break;
  }
};

let themeObserver = null;

const observeTheme = () => {
  themeObserver = new MutationObserver(() => {
    postToIframe({ type: 'theme', theme: currentTheme() });
  });
  themeObserver.observe(document.body, {
    attributes: true,
    attributeFilter: ['class'],
  });
};

const isLoading = computed(() => viewState.value === STATE.LOADING);
const isError = computed(() => viewState.value === STATE.ERROR);
const isReady = computed(() => viewState.value === STATE.READY);

onMounted(() => {
  window.addEventListener('message', handleMessage);
  observeTheme();
  requestToken();
});

onBeforeUnmount(() => {
  window.removeEventListener('message', handleMessage);
  themeObserver?.disconnect();
});
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <div
      v-if="isLoading"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ t('JABVOX_ADVANCED_AUTOMATIONS.LOADING') }}
    </div>

    <div
      v-else-if="isError"
      class="flex flex-col items-center justify-center flex-1 gap-3 p-6 text-center"
    >
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.TITLE') }}
      </h2>
      <p class="max-w-md text-sm text-n-slate-11">{{ errorMessage }}</p>
    </div>

    <iframe
      v-else-if="isReady"
      ref="iframeRef"
      :src="iframeUrl"
      :title="t('JABVOX_ADVANCED_AUTOMATIONS.TITLE')"
      class="flex-1 w-full h-full border-0"
      sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-modals"
      referrerpolicy="strict-origin"
      allow="clipboard-write"
    />
  </div>
</template>
