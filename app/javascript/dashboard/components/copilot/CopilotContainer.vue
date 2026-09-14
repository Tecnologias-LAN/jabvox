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

// Sesión de la burbuja. Es una sesión más de Hermes, así que también aparece en la página
// completa de Chat IA: el usuario puede empezar aquí y seguir allá.
const currentSessionId = ref(null);
const hermesAgents = ref([]); // conexiones Hermes ligadas a este usuario
const selectedAgentId = ref(null);

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

const handleClose = () => {
  updateUISettings({ is_copilot_panel_open: false });
};

// Conversación nueva: la siguiente pregunta abre una sesión limpia en Hermes.
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
      selectedAgentId.value = hermesAgents.value[0]?.id || null;
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
