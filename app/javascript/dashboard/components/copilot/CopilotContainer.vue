<script setup>
// Panel flotante del Chat IA (la "burbuja"). Habla con los MISMOS agentes Hermes de la
// cuenta que la página completa de Chat IA: comparte store (jabvoxAiChat), sesiones,
// agentes, comandos y streaming, vía los composables useHermes*.
import { ref, computed, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useHermesChat } from 'dashboard/composables/jabvox/useHermesChat';
import { useHermesSessions } from 'dashboard/composables/jabvox/useHermesSessions';
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
// burbuja (o recargar la página) recupera la MISMA conversación en vez de una vacía.
const currentSessionId = computed({
  get: () => store.getters['jabvoxAiChat/getCopilotSessionId'],
  set: value => store.commit('jabvoxAiChat/SET_COPILOT_SESSION_ID', value),
});

const {
  selectedAgentId,
  selectedAgentName,
  sessions,
  hasAgents,
  agentOptions,
  modelOptions,
  selectedModelKey,
  selectedModelOverride,
  loadAgents,
  loadModelOptions,
  selectSession,
  restoreLastSession,
  sessionBelongsToOtherAgent,
} = useHermesSessions({ sessionId: currentSessionId });

const hasRestoredSession = ref(false);
const hasFetchedAgents = ref(false);

const messages = computed(() =>
  currentSessionId.value
    ? store.getters['jabvoxAiChat/getMessages'](currentSessionId.value)
    : []
);

const { isStreaming, activeTools, streamAssistant, stopStreaming } =
  useHermesChat({ errorLabel: t('JABVOX_AI_CHAT.ERROR') });

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

const handleSelectSession = async sessionId => {
  if (sessionId === currentSessionId.value) return;
  if (isStreaming.value) stopStreaming();
  await selectSession(sessionId);
};

const sendMessage = async ({
  content,
  isNewChatCommand,
  isStopCommand,
  isModelCommand,
}) => {
  const text = (content || '').trim();
  if (!text || !hasAgents.value) return;

  // Si el bot aún responde, detén esa respuesta antes de enviar el nuevo mensaje.
  if (isStreaming.value) stopStreaming();

  // "/new", "/reset" y "/clear" abren sesión nueva en Jabvox; "/stop" solo corta el
  // streaming. Ninguno se envía a Hermes.
  if (isNewChatCommand) {
    currentSessionId.value = null;
    return;
  }
  if (isStopCommand) return;

  const isNewChat = !currentSessionId.value;
  const apiSessionId = currentSessionId.value || null;
  const displaySessionId = apiSessionId || `pending_${Date.now()}`;
  if (isNewChat) currentSessionId.value = displaySessionId;

  store.commit('jabvoxAiChat/ADD_MESSAGE', {
    sessionId: displaySessionId,
    message: {
      id: Date.now(),
      role: 'user',
      content: text,
      created_at: new Date(),
    },
  });

  await streamAssistant({
    content: text,
    apiSessionId,
    displaySessionId,
    isNewChat,
    connectionId: selectedAgentId.value,
    // Con "/model ..." el usuario está eligiendo modelo por comando: mandar además el del
    // picker sobrescribiría en el body justo lo que el comando acaba de pedir.
    modelOverride: isModelCommand ? {} : selectedModelOverride.value,
  });

  // Hermes no avisa del cambio de modelo por el stream, así que tras un "/model" releemos
  // model/options para que el picker refleje el modelo realmente activo.
  if (isModelCommand) await loadModelOptions(selectedAgentId.value);
};

// Cambiar de agente recarga sus modelos y, si la sesión abierta pertenece a otro agente,
// abre una nueva: una conversación siempre continúa con su propio interlocutor.
watch(selectedAgentId, (newId, oldId) => {
  loadModelOptions(newId);
  if (!oldId || newId === oldId || !currentSessionId.value) return;
  if (sessionBelongsToOtherAgent(currentSessionId.value, newId)) {
    if (isStreaming.value) stopStreaming();
    currentSessionId.value = null;
  }
});

// Al habilitarse el módulo: carga agentes y sesiones, y recupera la última conversación
// si la burbuja aún no tiene una abierta.
async function initialise() {
  if (hasFetchedAgents.value) return;
  hasFetchedAgents.value = true;
  try {
    await loadAgents({ keepSelection: true });
    if (!hasRestoredSession.value && !currentSessionId.value) {
      hasRestoredSession.value = true;
      await restoreLastSession();
    }
  } catch {
    hasFetchedAgents.value = false;
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
    if (enabled) await initialise();
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
      v-model:selected-agent-id="selectedAgentId"
      v-model:selected-model-key="selectedModelKey"
      :messages="messages"
      :is-streaming="isStreaming"
      :active-tools="activeTools"
      :has-agents="hasAgents"
      :agent-options="agentOptions"
      :model-options="modelOptions"
      :sessions="sessions"
      :current-session-id="currentSessionId"
      :selected-agent-name="selectedAgentName"
      @send-message="sendMessage"
      @select-session="handleSelectSession"
      @stop="stopStreaming"
      @reset="handleReset"
      @close="handleClose"
    />
  </div>
  <template v-else />
</template>
