<script setup>
// Panel flotante del Chat IA (la "burbuja"). Habla con el MISMO agente Hermes de la cuenta
// que la página completa de Chat IA: comparte store (jabvoxAiChat), sesiones y streaming.
import { ref, computed, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useHermesChat } from 'dashboard/composables/jabvox/useHermesChat';
import { hermesConnectionsAPI } from 'dashboard/api/jabvox/aiChat';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import wootConstants from 'dashboard/constants/globals';
import HermesChatPanel from './HermesChatPanel.vue';

const store = useStore();
const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();

const currentAccountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

// La sesión de la burbuja vive en Vuex (jabvoxAiChat), NO en un ref() local: este
// componente se desmonta por completo cada vez que la burbuja se cierra (v-if más abajo),
// y con él cualquier ref() local se perdería. Vuex sí sobrevive, así que reabrir la
// burbuja (o recargar la página) recupera la MISMA conversación en vez de una vacía —
// igual que ya hace la página completa de Chat IA con sus sesiones guardadas en backend.
const currentSessionId = computed({
  get: () => store.getters['jabvoxAiChat/getCopilotSessionId'],
  set: value => store.commit('jabvoxAiChat/SET_COPILOT_SESSION_ID', value),
});

const hermesAgents = ref([]); // conexiones Hermes ligadas a este usuario
const selectedAgentId = ref(null);
const hasRestoredSession = ref(false);

const messages = computed(() =>
  currentSessionId.value
    ? store.getters['jabvoxAiChat/getMessages'](currentSessionId.value)
    : []
);

const { isStreaming, activeTools, streamAssistant, stopStreaming } =
  useHermesChat({ errorLabel: t('JABVOX_AI_CHAT.ERROR') });

const hasAgents = computed(() => hermesAgents.value.length > 0);
const hasFetchedAgents = ref(false);

const isAiChatEnabled = computed(() =>
  isFeatureEnabledonAccount.value(
    currentAccountId.value,
    FEATURE_FLAGS.JABVOX_AI_CHAT
  )
);

const shouldShowCopilotPanel = computed(() => {
  const { is_copilot_panel_open: isCopilotPanelOpen } = uiSettings.value;
  return isAiChatEnabled.value && isCopilotPanelOpen;
});

const closeCopilotPanel = () => {
  if (isSmallScreen.value && uiSettings.value?.is_copilot_panel_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};

// Cerrar la burbuja SOLO oculta el panel: no aborta el streaming en curso (isStreaming/
// activeTools viven en Vuex, ajenos al ciclo de vida de este componente) ni borra la
// sesión — al reabrir, se ve la misma conversación, completa o siguiendo en vivo.
const handleClose = () => {
  updateUISettings({ is_copilot_panel_open: false });
};

// Conversación nueva explícita: el usuario pidió empezar de cero.
const handleReset = () => {
  if (isStreaming.value) stopStreaming();
  currentSessionId.value = null;
};

const sendMessage = async message => {
  const content = (message || '').trim();
  if (!content || !hasAgents.value) return;

  // Si el bot aún responde, detén esa respuesta antes de enviar el nuevo mensaje.
  if (isStreaming.value) stopStreaming();

  const isNewChat = !currentSessionId.value;
  const apiSessionId = currentSessionId.value || null;
  const displaySessionId = apiSessionId || `pending_${Date.now()}`;
  if (isNewChat) currentSessionId.value = displaySessionId;

  store.commit('jabvoxAiChat/ADD_MESSAGE', {
    sessionId: displaySessionId,
    message: {
      id: Date.now(),
      role: 'user',
      content,
      created_at: new Date(),
    },
  });

  await streamAssistant({
    content,
    apiSessionId,
    displaySessionId,
    isNewChat,
    connectionId: selectedAgentId.value,
  });
};

// Al habilitarse el módulo (llegue antes o después del montaje, ver el watch de abajo):
// 1) carga los agentes Hermes del usuario, y 2) si la burbuja no tiene ya una sesión
// (primera vez que se abre en esta pestaña), recupera la ÚLTIMA sesión existente del
// backend — igual que hace la página completa — en vez de arrancar siempre en blanco.
async function restoreLastSession() {
  if (hasRestoredSession.value || currentSessionId.value) return;
  hasRestoredSession.value = true;
  try {
    await store.dispatch('jabvoxAiChat/fetchSessions');
    const sessions = store.getters['jabvoxAiChat/getSessions'];
    if (!sessions.length) return;

    const [lastSession] = sessions;
    currentSessionId.value = lastSession.session_id;
    if (lastSession.connection_id)
      selectedAgentId.value = lastSession.connection_id;
    await store.dispatch('jabvoxAiChat/fetchMessages', lastSession.session_id);
  } catch {
    hasRestoredSession.value = false;
  }
}

// CopilotContainer vive siempre montado en el Dashboard (no es una ruta a la que se
// navega), así que su onMounted corre ANTES de que App.vue termine de cargar
// accounts/get: en ese instante el flag jabvox_ai_chat aún lee false y la carga de
// agentes se saltaba en silencio (la burbuja quedaba con "sin agente" para siempre).
// Con un watch inmediato+reactivo, la carga se dispara en cuanto el flag esté
// disponible, llegue antes o después del montaje, y solo una vez.
watch(
  isAiChatEnabled,
  async enabled => {
    if (!enabled || hasFetchedAgents.value) return;
    hasFetchedAgents.value = true;
    try {
      const { data } = await hermesConnectionsAPI.mine();
      hermesAgents.value = data || [];
      // No pisar el agente ya restaurado de una sesión anterior (ver restoreLastSession).
      if (!selectedAgentId.value) {
        selectedAgentId.value = hermesAgents.value[0]?.id || null;
      }
      await restoreLastSession();
    } catch {
      hermesAgents.value = [];
      hasFetchedAgents.value = false;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    v-if="shouldShowCopilotPanel"
    v-on-click-outside="() => closeCopilotPanel()"
    class="bg-n-surface-2 h-full overflow-hidden flex-col fixed top-0 ltr:right-0 rtl:left-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[360px] 2xl:w-[360px] shadow-lg md:shadow-none"
    :class="[
      {
        'md:flex': shouldShowCopilotPanel,
        'md:hidden': !shouldShowCopilotPanel,
      },
    ]"
  >
    <HermesChatPanel
      :messages="messages"
      :is-streaming="isStreaming"
      :active-tools="activeTools"
      :has-agents="hasAgents"
      @send-message="sendMessage"
      @stop="stopStreaming"
      @reset="handleReset"
      @close="handleClose"
    />
  </div>
  <template v-else />
</template>
