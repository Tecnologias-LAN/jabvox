<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MessageList from './MessageList.vue';
import CaptainAssistant from 'dashboard/api/captain/assistant';

const { assistantId } = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const { t } = useI18n();

// Dos conversaciones de prueba independientes (p. ej. probar dos flujos a la
// vez). El backend del playground es stateless: cada sesión manda su propio
// historial, así que no necesitan estado en servidor.
const createSession = index => ({
  id: index,
  messages: [],
});

const sessions = ref([createSession(1), createSession(2)]);
const activeSessionId = ref(1);
const newMessage = ref('');
const isLoading = ref(false);

const activeSession = computed(
  () =>
    sessions.value.find(s => s.id === activeSessionId.value) ??
    sessions.value[0]
);

const formatMessagesForApi = session => {
  return session.messages.map(message => {
    const payload = { role: message.sender, content: message.content };
    if (message.sender === 'assistant' && message.agentName) {
      payload.agent_name = message.agentName;
    }
    return payload;
  });
};

const resetConversation = () => {
  const session = activeSession.value;
  session.messages = [];
  newMessage.value = '';
};

const resetAllConversations = () => {
  sessions.value = [createSession(1), createSession(2)];
  activeSessionId.value = 1;
  newMessage.value = '';
};

// Al cambiar de asistente, se limpian ambas conversaciones de prueba.
watch(
  () => assistantId,
  (newId, oldId) => {
    if (oldId && newId !== oldId) resetAllConversations();
  }
);

const sendMessage = async () => {
  if (!newMessage.value.trim() || isLoading.value) return;

  const session = activeSession.value;
  session.messages.push({
    content: newMessage.value,
    sender: 'user',
    timestamp: new Date().toISOString(),
  });
  const currentMessage = newMessage.value;
  newMessage.value = '';

  try {
    isLoading.value = true;
    const { data } = await CaptainAssistant.playground({
      assistantId,
      messageContent: currentMessage,
      messageHistory: formatMessagesForApi(session),
    });

    session.messages.push({
      content: data.response,
      sender: 'assistant',
      agentName: data.agent_name,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error getting assistant response:', error);
  } finally {
    isLoading.value = false;
  }
};

const handleEnterKey = event => {
  if (event.isComposing) return;
  event.preventDefault();
  sendMessage();
};
</script>

<template>
  <div
    class="flex flex-col h-full rounded-xl border py-6 border-n-weak text-n-slate-11"
  >
    <div class="mb-4 px-6">
      <div class="flex justify-between items-center mb-1">
        <h3 class="text-lg font-medium">
          {{ t('CAPTAIN.PLAYGROUND.HEADER') }}
        </h3>
        <NextButton
          ghost
          sm
          slate
          icon="i-lucide-rotate-ccw"
          @click="resetConversation"
        />
      </div>
      <p class="text-sm text-n-slate-11">
        {{ t('CAPTAIN.PLAYGROUND.DESCRIPTION') }}
      </p>
    </div>

    <!-- Pestañas de conversación de prueba -->
    <div class="flex items-center gap-1 px-6 mb-3">
      <button
        v-for="(session, index) in sessions"
        :key="session.id"
        class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors"
        :class="
          activeSessionId === session.id
            ? 'bg-n-alpha-2 text-n-slate-12'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="activeSessionId = session.id"
      >
        {{ t('CAPTAIN.PLAYGROUND.SESSION', { number: index + 1 }) }}
      </button>
    </div>

    <MessageList :messages="activeSession.messages" :is-loading="isLoading" />

    <div
      class="flex items-center mx-6 bg-n-background outline outline-1 outline-n-weak rounded-xl p-3"
    >
      <input
        v-model="newMessage"
        class="flex-1 bg-transparent border-none focus:outline-none text-sm mb-0 text-n-slate-12 placeholder:text-n-slate-10"
        :placeholder="t('CAPTAIN.PLAYGROUND.MESSAGE_PLACEHOLDER')"
        @keydown.enter.exact="handleEnterKey"
      />
      <NextButton
        ghost
        sm
        :disabled="!newMessage.trim()"
        icon="i-lucide-send"
        @click="sendMessage"
      />
    </div>

    <p class="text-xs text-n-slate-11 pt-2 text-center">
      {{ t('CAPTAIN.PLAYGROUND.CREDIT_NOTE') }}
    </p>
  </div>
</template>
