<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const store = useStore();
const { t } = useI18n();
const alert = useAlert;

const currentSessionId = ref(null);
const messageInput = ref('');
const messagesContainer = ref(null);
const selectedMode = ref('model');
const selectedModelId = ref(null);

const sessions = computed(() => store.getters['jabvoxAiChat/getSessions']);
const messages = computed(() =>
  currentSessionId.value
    ? store.getters['jabvoxAiChat/getMessages'](currentSessionId.value)
    : []
);
const models = computed(() => store.getters['jabvoxAiChat/getModels']);
const documents = computed(() => store.getters['jabvoxAiChat/getDocuments']);
const myAccess = computed(() => store.getters['jabvoxAiChat/getMyAccess']);
const uiFlags = computed(() => store.getters['jabvoxAiChat/getUIFlags']);

const isSending = computed(() => uiFlags.value.isSending);
const canUse = computed(() => !myAccess.value || myAccess.value.can_use);
const canUseModels = computed(
  () => !myAccess.value || myAccess.value.can_use_models
);
const canUseDocuments = computed(
  () => !myAccess.value || myAccess.value.can_use_documents
);
const hasModels = computed(() => (models.value || []).length > 0);
const hasDocuments = computed(() => (documents.value || []).length > 0);
const canSend = computed(
  () =>
    messageInput.value.trim().length > 0 &&
    !isSending.value &&
    canUse.value &&
    hasModels.value
);
const defaultModel = computed(
  () => models.value.find(m => m.is_default_jabvox) || models.value[0]
);

function selectSession(sessionId) {
  currentSessionId.value = sessionId;
  store.dispatch('jabvoxAiChat/fetchMessages', sessionId);
}

onMounted(async () => {
  await Promise.all([
    store.dispatch('jabvoxAiChat/fetchMyAccess'),
    store.dispatch('jabvoxAiChat/fetchSessions'),
    store.dispatch('jabvoxAiChat/fetchModels'),
    store.dispatch('jabvoxAiChat/fetchDocuments'),
  ]);
  if (defaultModel.value) selectedModelId.value = defaultModel.value.id;
  if (sessions.value.length > 0) selectSession(sessions.value[0].session_id);
});

watch(
  [hasModels, hasDocuments],
  ([modelsAvailable, documentsAvailable]) => {
    if (!modelsAvailable && documentsAvailable) {
      selectedMode.value = 'documents';
      return;
    }
    if (modelsAvailable && !documentsAvailable) {
      selectedMode.value = 'model';
    }
  },
  { immediate: true }
);

watch(messages, async () => {
  await nextTick();
  if (messagesContainer.value)
    messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight;
});

function newChat() {
  currentSessionId.value = null;
  messageInput.value = '';
}

async function deleteSession(sessionId) {
  if (!window.confirm(t('JABVOX_AI_CHAT.DELETE_SESSION_CONFIRM'))) return;
  await store.dispatch('jabvoxAiChat/deleteSession', sessionId);
  if (currentSessionId.value === sessionId) currentSessionId.value = null;
}

async function sendMessage() {
  const content = messageInput.value.trim();
  if (!content) return;
  if (!hasModels.value) {
    alert(t('JABVOX_AI_CHAT.NO_MODEL'));
    return;
  }

  const isNewChat = !currentSessionId.value;
  const apiSessionId = currentSessionId.value || null;
  const displaySessionId = apiSessionId || `pending_${Date.now()}`;

  if (isNewChat) currentSessionId.value = displaySessionId;

  store.commit('jabvoxAiChat/ADD_MESSAGE', {
    sessionId: displaySessionId,
    message: { id: Date.now(), role: 'user', content, created_at: new Date() },
  });

  messageInput.value = '';

  try {
    const result = await store.dispatch('jabvoxAiChat/sendMessage', {
      content,
      session_id: apiSessionId,
      mode: selectedMode.value,
      model_id: selectedModelId.value,
    });
    if (isNewChat && result?.session_id) {
      await store.dispatch('jabvoxAiChat/fetchMessages', result.session_id);
      currentSessionId.value = result.session_id;
      await store.dispatch('jabvoxAiChat/fetchSessions');
    }
  } catch (e) {
    const errorMessage =
      e?.response?.data?.error || e?.message || t('JABVOX_AI_CHAT.ERROR');
    alert(errorMessage);
    if (isNewChat) {
      currentSessionId.value = null;
    } else {
      store.commit('jabvoxAiChat/ADD_MESSAGE', {
        sessionId: currentSessionId.value,
        message: {
          id: Date.now(),
          role: 'assistant',
          content: `Error: ${errorMessage}`,
          created_at: new Date(),
        },
      });
    }
  }
}

function handleKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    if (canSend.value) sendMessage();
  }
}

function formatTime(dateStr) {
  return new Date(dateStr).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function formatSessionLabel(session) {
  return new Date(session.last_message_at || session.created_at).toLocaleString(
    [],
    {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    }
  );
}
</script>

<template>
  <div class="flex h-full w-full overflow-hidden bg-slate-50">
    <!-- Sessions sidebar -->
    <div
      class="hidden lg:flex w-72 flex-shrink-0 border-r border-slate-200 bg-white flex-col"
    >
      <div
        class="p-4 border-b border-slate-200 flex items-center justify-between"
      >
        <h2 class="text-sm font-semibold text-slate-700">
          {{ t('JABVOX_AI_CHAT.SESSIONS_LABEL') }}
        </h2>
        <button
          class="p-1.5 rounded-lg text-slate-500 hover:bg-slate-100 hover:text-violet-600 transition-colors"
          @click="newChat"
        >
          <span class="i-ri-add-line text-lg" />
        </button>
      </div>
      <div class="flex-1 overflow-y-auto p-3 space-y-1">
        <button
          v-for="session in sessions"
          :key="session.session_id"
          class="w-full text-left px-3 py-2 rounded-lg text-xs transition-colors group flex items-center justify-between"
          :class="
            currentSessionId === session.session_id
              ? 'bg-violet-50 text-violet-700'
              : 'text-slate-600 hover:bg-slate-100'
          "
          @click="selectSession(session.session_id)"
        >
          <span class="truncate">{{ formatSessionLabel(session) }}</span>
          <span
            class="hidden group-hover:flex i-ri-delete-bin-line text-slate-400 hover:text-red-500 ml-1 flex-shrink-0"
            @click.stop="deleteSession(session.session_id)"
          />
        </button>
        <p
          v-if="sessions.length === 0"
          class="text-xs text-slate-400 px-3 py-4 text-center"
        >
          {{ t('JABVOX_AI_CHAT.EMPTY_STATE') }}
        </p>
      </div>
    </div>

    <!-- Main chat area -->
    <div class="flex-1 flex flex-col min-w-0">
      <!-- Header -->
      <div
        class="border-b border-slate-200 bg-white px-4 sm:px-6 py-3 flex flex-wrap items-center justify-between gap-3 flex-shrink-0"
      >
        <div class="flex items-center gap-3">
          <div
            class="hidden sm:flex items-center justify-center size-10 rounded-xl bg-violet-50 text-violet-600"
          >
            <span class="i-ri-robot-2-line text-lg" />
          </div>
          <div>
            <h1 class="text-base sm:text-lg font-semibold text-slate-800">
              {{ t('JABVOX_AI_CHAT.TITLE') }}
            </h1>
            <p class="text-xs text-slate-500">
              {{ t('JABVOX_AI_CHAT.SESSIONS_LABEL') }}
            </p>
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2 sm:gap-3">
          <!-- Mode selector -->
          <div class="flex items-center gap-1 bg-slate-100 rounded-lg p-1">
            <button
              v-if="canUseModels && hasModels"
              class="px-3 py-1 rounded-md text-xs font-medium transition-colors"
              :class="
                selectedMode === 'model'
                  ? 'bg-white text-violet-700 shadow-sm'
                  : 'text-slate-500 hover:text-slate-700'
              "
              @click="selectedMode = 'model'"
            >
              {{ t('JABVOX_AI_CHAT.MODE_MODEL') }}
            </button>
            <button
              v-if="canUseDocuments && hasDocuments"
              class="px-3 py-1 rounded-md text-xs font-medium transition-colors"
              :class="
                selectedMode === 'documents'
                  ? 'bg-white text-violet-700 shadow-sm'
                  : 'text-slate-500 hover:text-slate-700'
              "
              @click="selectedMode = 'documents'"
            >
              {{ t('JABVOX_AI_CHAT.MODE_DOCUMENTS') }}
            </button>
          </div>
          <!-- Model selector -->
          <select
            v-if="hasModels && canUseModels"
            v-model="selectedModelId"
            class="text-xs border border-slate-200 rounded-lg px-2 py-1.5 text-slate-600 focus:outline-none focus:ring-2 focus:ring-violet-500"
          >
            <option v-for="m in models" :key="m.id" :value="m.id">
              {{ m.name_jabvox }}
            </option>
          </select>
        </div>
      </div>

      <!-- Access denied -->
      <div v-if="!canUse" class="flex-1 flex items-center justify-center">
        <p class="text-slate-500 text-sm">
          {{ t('JABVOX_AI_CHAT.ACCESS_DENIED') }}
        </p>
      </div>

      <!-- No model warning -->
      <div
        v-else-if="!hasModels && !hasDocuments"
        class="flex-1 flex items-center justify-center"
      >
        <p class="text-slate-500 text-sm">{{ t('JABVOX_AI_CHAT.NO_MODEL') }}</p>
      </div>

      <template v-else>
        <!-- Messages -->
        <div
          ref="messagesContainer"
          class="flex-1 overflow-y-auto px-4 sm:px-8 py-6 space-y-4"
        >
          <p
            v-if="messages.length === 0 && !currentSessionId"
            class="text-center text-slate-400 text-sm mt-16"
          >
            {{ t('JABVOX_AI_CHAT.EMPTY_STATE') }}
          </p>
          <div
            v-for="msg in messages"
            :key="msg.id"
            class="flex gap-3"
            :class="msg.role === 'user' ? 'flex-row-reverse' : ''"
          >
            <div
              class="max-w-[min(720px,100%)] rounded-2xl px-4 py-2.5 text-sm leading-relaxed"
              :class="
                msg.role === 'user'
                  ? 'bg-violet-600 text-white rounded-tr-sm'
                  : 'bg-white border border-slate-200 text-slate-700 rounded-tl-sm shadow-sm'
              "
            >
              <p class="whitespace-pre-wrap">
                {{ msg.content || msg.content_jabvox }}
              </p>
              <span
                class="text-xs opacity-60 mt-1 block"
                :class="msg.role === 'user' ? 'text-right' : ''"
              >
                {{ formatTime(msg.created_at) }}
              </span>
            </div>
          </div>
          <!-- Thinking indicator -->
          <div v-if="isSending" class="flex gap-3">
            <div
              class="bg-white border border-slate-200 rounded-2xl rounded-tl-sm px-4 py-3 shadow-sm"
            >
              <div class="flex gap-1 items-center">
                <div
                  class="w-1.5 h-1.5 rounded-full bg-slate-400 animate-bounce [animation-delay:0ms]"
                />
                <div
                  class="w-1.5 h-1.5 rounded-full bg-slate-400 animate-bounce [animation-delay:150ms]"
                />
                <div
                  class="w-1.5 h-1.5 rounded-full bg-slate-400 animate-bounce [animation-delay:300ms]"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- Input area -->
        <div class="border-t border-slate-200 bg-white p-4 flex-shrink-0">
          <div
            class="flex flex-col sm:flex-row gap-3 items-stretch sm:items-end max-w-5xl mx-auto w-full"
          >
            <textarea
              v-model="messageInput"
              rows="1"
              class="flex-1 resize-none border border-slate-200 rounded-xl px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500 focus:border-transparent text-slate-700 placeholder-slate-400"
              :placeholder="t('JABVOX_AI_CHAT.PLACEHOLDER')"
              @keydown="handleKeydown"
            />
            <button
              class="flex-shrink-0 bg-violet-600 hover:bg-violet-700 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-xl px-4 py-3 transition-colors flex items-center justify-center gap-2"
              :disabled="!canSend"
              @click="sendMessage"
            >
              <span class="i-ri-send-plane-fill text-base" />
            </button>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
