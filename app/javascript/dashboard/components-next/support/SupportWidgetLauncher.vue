<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// Burbuja de "Soporte" global. Carga el widget de chat (SDK) apuntando a la
// bandeja de soporte global (JABVOX_INBOX_TOKEN) e identifica al agente logueado
// con su HMAC, de modo que su historial de soporte lo sigue en cualquier cuenta
// y dispositivo. La burbuja nativa del SDK se oculta y usamos esta, situada
// ARRIBA de la de Captain. El logo/avatar dentro del chat es el avatar del
// inbox de soporte (se sube en Ajustes de esa bandeja; si no, el de defecto).
const { t } = useI18n();

const accountId = useMapGetter('getCurrentAccountId');
const currentUser = useMapGetter('getCurrentUser');
const globalConfig = useMapGetter('globalConfig/get');
const getAccountById = useMapGetter('accounts/getAccount');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

// Nombre de la cuenta actual (para mostrarlo entre paréntesis en soporte).
const currentAccountName = computed(
  () => getAccountById.value(accountId.value)?.name || ''
);

// Se muestra solo si la cuenta tiene el módulo de soporte activo Y hay token global.
const isEnabled = computed(
  () =>
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CONTACT_JABVOX_SUPPORT_TEAM
    ) && !!globalConfig.value.jabvoxInboxToken
);

const sdkReady = ref(false);

// Inyecta el SDK una sola vez y lo arranca apuntando a la bandeja de soporte.
const loadSdk = () => {
  const token = globalConfig.value.jabvoxInboxToken;
  if (!token || window.$jabvox) {
    sdkReady.value = !!window.$jabvox;
    return;
  }
  // Nuestra burbuja reemplaza la del SDK: la ocultamos.
  window.jabvoxSettings = {
    hideMessageBubble: true,
    position: 'right',
    launcherTitle: t('SUPPORT_WIDGET.LAUNCHER_TITLE'),
  };
  const baseUrl = window.location.origin;
  const script = document.createElement('script');
  script.src = `${baseUrl}/packs/js/sdk.js`;
  script.async = true;
  script.onload = () => {
    if (!window.jabvoxSDK) return;
    window.jabvoxSDK.run({ websiteToken: token, baseUrl });
    sdkReady.value = true;
  };
  script.onerror = () => {
    // Si el SDK no carga (red/404), permitimos reintentar en el próximo click.
    sdkReady.value = false;
    // eslint-disable-next-line no-console
    console.error('[Jabvox soporte] No se pudo cargar el widget de soporte.');
  };
  document.body.appendChild(script);
};

// Identifica al agente para historial persistente (setUser + HMAC). IMPORTANTE:
// el `identifier` es "email:accountId" (NO solo el email), para que el MISMO
// usuario en cuentas distintas sea un CONTACTO distinto en la bandeja de
// soporte (nombre e historial por cuenta). El backend firma ese mismo
// identifier por cuenta (support_hmac_identifiers[accountId]) con la clave
// HMAC global; si identifier y hash no corresponden, el widget rechaza el HMAC.
// El nombre que verá soporte es "Nombre del agente (Nombre de la cuenta)".
const lastIdentifier = ref(null);
const identifyUser = () => {
  const user = currentUser.value;
  const accId = accountId.value;
  if (!window.$jabvox || !user?.email || !accId) return;

  const hash =
    user.supportHmacIdentifiers?.[accId] ||
    user.support_hmac_identifiers?.[accId];
  if (!hash) return; // sin hash de esta cuenta no identificamos (evita HMAC inválido)

  const identifier = `${user.email}:${accId}`;
  const displayName = currentAccountName.value
    ? `${user.name} (${currentAccountName.value})`
    : user.name;

  // Al cambiar de cuenta cambia el identifier: reseteamos la sesión del widget
  // para no arrastrar el contacto/historial de la cuenta anterior.
  if (lastIdentifier.value && lastIdentifier.value !== identifier) {
    try {
      window.$jabvox.reset();
    } catch (e) {
      // El SDK puede no exponer reset en versiones antiguas; setUser igual cambia el user.
    }
  }
  lastIdentifier.value = identifier;

  window.$jabvox.setUser(identifier, {
    name: displayName,
    email: user.email,
    identifier_hash: hash,
  });
};

watch(sdkReady, ready => {
  if (ready) identifyUser();
});
watch(currentUser, () => {
  if (sdkReady.value) identifyUser();
});
// Al cambiar de cuenta activa, reidentificar para actualizar el "(cuenta)".
watch(currentAccountName, () => {
  if (sdkReady.value) identifyUser();
});

const openSupport = () => {
  // Si el SDK ya está listo, abre el chat. Si no cargó aún (o falló), lo intenta
  // de nuevo para no dejar la burbuja "muerta".
  if (window.$jabvox) {
    window.$jabvox.toggle('open');
  } else if (isEnabled.value) {
    loadSdk();
  }
};

onMounted(() => {
  if (isEnabled.value) loadSdk();
});
watch(isEnabled, enabled => {
  if (enabled && !window.$jabvox) loadSdk();
});
</script>

<template>
  <button
    v-if="isEnabled"
    type="button"
    :title="t('SUPPORT_WIDGET.LAUNCHER_TITLE')"
    class="fixed bottom-20 ltr:right-4 rtl:left-4 z-50 w-12 h-12 rounded-full bg-n-solid-3 shadow hover:shadow-md hover:brightness-110 transition-all flex items-center justify-center border border-n-weak"
    @click="openSupport"
  >
    <span class="i-lucide-life-buoy size-6 text-n-brand" />
  </button>
</template>
