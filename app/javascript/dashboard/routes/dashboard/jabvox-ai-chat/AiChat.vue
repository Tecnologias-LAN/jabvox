<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import {
  hasPushPermissions,
  requestPushPermissions,
  verifyServiceWorkerExistence,
} from 'dashboard/helper/pushHelper';

const store = useStore();
const { t } = useI18n();
const alert = useAlert;

const currentSessionId = ref(null);
const messageInput = ref('');
const messagesContainer = ref(null);
const selectedMode = ref('model');
const selectedModelId = ref(null);
const showSessions = ref(false); // mobile drawer
const deleteDialog = ref(null);
const pendingDeleteId = ref(null);
const pushEnabled = ref(false);
const pushSupported = computed(
  () => 'Notification' in window && 'serviceWorker' in navigator
);

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
const modelOptions = computed(() =>
  (models.value || []).map(m => ({ value: m.id, label: m.name_jabvox }))
);

function selectSession(sessionId) {
  currentSessionId.value = sessionId;
  showSessions.value = false;
  store.dispatch('jabvoxAiChat/fetchMessages', sessionId);
}

function syncPushStatus() {
  if (!pushSupported.value || !hasPushPermissions()) {
    pushEnabled.value = false;
    return;
  }

  verifyServiceWorkerExistence(registration => {
    registration.pushManager
      .getSubscription()
      .then(subscription => {
        pushEnabled.value = !!subscription;
      })
      .catch(() => {
        pushEnabled.value = false;
      });
  });
}

function enablePushNotifications() {
  requestPushPermissions({
    onSuccess: () => {
      pushEnabled.value = true;
    },
  });
}

onMounted(async () => {
  await Promise.all([
    store.dispatch('jabvoxAiChat/fetchMyAccess'),
    store.dispatch('jabvoxAiChat/fetchSessions'),
    store.dispatch('jabvoxAiChat/fetchModels'),
    store.dispatch('jabvoxAiChat/fetchDocuments'),
  ]);
  syncPushStatus();
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
  showSessions.value = false;
}

function askDeleteSession(sessionId) {
  pendingDeleteId.value = sessionId;
  deleteDialog.value?.open();
}

async function confirmDeleteSession() {
  const sessionId = pendingDeleteId.value;
  if (!sessionId) return;
  await store.dispatch('jabvoxAiChat/deleteSession', sessionId);
  if (currentSessionId.value === sessionId) currentSessionId.value = null;
  pendingDeleteId.value = null;
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

// Sessions newest-first; numbered so each gets a readable primary label
// (the backend only sends session_id + timestamps, no title/preview).
const numberedSessions = computed(() =>
  sessions.value.map((session, idx) => ({
    ...session,
    label: `${t('JABVOX_AI_CHAT.SESSION_ITEM')} ${sessions.value.length - idx}`,
  }))
);
</script>

<template>
  <div class="flex h-full w-full overflow-hidden bg-n-background flex-col">
    <div v-if="pushSupported" class="px-4 pt-3">
      <Banner
        v-if="!pushEnabled"
        color="amber"
        :action-label="
          t('PROFILE_SETTINGS.FORM.PUSH_NOTIFICATIONS_SECTION.REQUEST_PUSH')
        "
        @action="enablePushNotifications"
      >
        {{ t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.BROWSER_PERMISSION') }}
      </Banner>
      <Banner v-else color="teal">
        {{
          t('PROFILE_SETTINGS.FORM.PUSH_NOTIFICATIONS_SECTION.HAS_ENABLED_PUSH')
        }}
      </Banner>
    </div>

    <div class="flex flex-1 min-h-0 overflow-hidden relative">
      <!-- Mobile drawer backdrop -->
      <div
        v-if="showSessions"
        class="fixed inset-0 z-30 bg-n-alpha-black2 lg:hidden"
        @click="showSessions = false"
      />

      <!-- Sessions sidebar -->
      <aside
        class="z-40 w-72 flex-shrink-0 border-r border-n-weak bg-n-solid-1 flex-col lg:flex lg:static lg:translate-x-0"
        :class="
          showSessions
            ? 'flex fixed inset-y-0 left-0 shadow-xl'
            : 'hidden lg:flex'
        "
      >
        <div
          class="p-4 border-b border-n-weak flex items-center justify-between"
        >
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ t('JABVOX_AI_CHAT.SESSIONS_LABEL') }}
          </h2>
          <Button
            icon="i-lucide-plus"
            variant="ghost"
            color="slate"
            size="sm"
            :title="t('JABVOX_AI_CHAT.NEW_CHAT')"
            @click="newChat"
          />
        </div>
        <div class="flex-1 overflow-y-auto p-2.5 space-y-1.5">
          <div
            v-for="session in numberedSessions"
            :key="session.session_id"
            class="group relative flex items-center gap-3 px-3 py-2.5 rounded-xl cursor-pointer overflow-hidden transition-all duration-200"
            :class="
              currentSessionId === session.session_id
                ? 'bg-gradient-to-r from-n-alpha-2 to-transparent ring-1 ring-inset ring-n-brand/30'
                : 'hover:bg-n-alpha-1'
            "
            @click="selectSession(session.session_id)"
          >
            <!-- Active accent bar -->
            <span
              v-if="currentSessionId === session.session_id"
              class="absolute inset-y-2 left-0 w-0.5 rounded-full bg-n-brand"
            />
            <!-- Icon -->
            <span
              class="flex items-center justify-center size-8 rounded-lg shrink-0 transition-colors"
              :class="
                currentSessionId === session.session_id
                  ? 'bg-n-brand/15 text-n-brand'
                  : 'bg-n-alpha-2 text-n-slate-10 group-hover:text-n-slate-11'
              "
            >
              <span class="i-lucide-message-square-text size-4" />
            </span>
            <!-- Label + meta -->
            <div class="flex-1 min-w-0">
              <p
                class="text-sm truncate"
                :class="
                  currentSessionId === session.session_id
                    ? 'font-semibold text-n-slate-12'
                    : 'font-medium text-n-slate-11'
                "
              >
                {{ session.label }}
              </p>
              <span
                class="flex items-center gap-1 text-xs text-n-slate-9 mt-0.5"
              >
                <span class="i-lucide-clock size-3 shrink-0" />
                {{ formatSessionLabel(session) }}
              </span>
            </div>
            <!-- Delete -->
            <button
              class="hidden group-hover:flex items-center justify-center size-6 rounded-md text-n-slate-9 hover:text-n-ruby-11 hover:bg-n-ruby-3 shrink-0 transition-colors"
              :title="t('JABVOX_AI_CHAT.DELETE_SESSION')"
              @click.stop="askDeleteSession(session.session_id)"
            >
              <span class="i-lucide-trash-2 size-3.5" />
            </button>
          </div>
          <div
            v-if="sessions.length === 0"
            class="flex flex-col items-center justify-center gap-2 px-3 py-10 text-center"
          >
            <span
              class="i-lucide-messages-square size-8 text-n-slate-9 opacity-50"
            />
            <p class="text-xs text-n-slate-10">
              {{ t('JABVOX_AI_CHAT.EMPTY_STATE') }}
            </p>
          </div>
        </div>
      </aside>

      <!-- Main chat area -->
      <div class="flex-1 flex flex-col min-w-0">
        <!-- Header -->
        <div
          class="border-b border-n-weak bg-n-solid-1 px-4 sm:px-6 py-3 flex flex-wrap items-center justify-between gap-3 flex-shrink-0"
        >
          <div class="flex items-center gap-2 sm:gap-3 min-w-0">
            <!-- Historial (móvil) -->
            <Button
              icon="i-lucide-panel-left"
              variant="ghost"
              color="slate"
              size="sm"
              class="lg:hidden"
              :title="t('JABVOX_AI_CHAT.HISTORY')"
              @click="showSessions = true"
            />
            <div
              class="hidden sm:flex items-center justify-center size-10 rounded-xl bg-n-alpha-2 text-n-brand shrink-0"
            >
              <span class="i-lucide-bot size-5" />
            </div>
            <div class="min-w-0">
              <h1
                class="text-base sm:text-lg font-semibold text-n-slate-12 truncate"
              >
                {{ t('JABVOX_AI_CHAT.TITLE') }}
              </h1>
              <p class="text-xs text-n-slate-10">
                {{ t('JABVOX_AI_CHAT.SESSIONS_LABEL') }}
              </p>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-2 sm:gap-3">
            <!-- Mode selector -->
            <div
              v-if="
                (canUseModels && hasModels) || (canUseDocuments && hasDocuments)
              "
              class="flex items-center gap-1 bg-n-alpha-1 rounded-lg p-1"
            >
              <button
                v-if="canUseModels && hasModels"
                class="px-3 py-1 rounded-md text-xs font-medium transition-colors"
                :class="
                  selectedMode === 'model'
                    ? 'bg-n-solid-1 text-n-brand shadow-sm'
                    : 'text-n-slate-10 hover:text-n-slate-12'
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
                    ? 'bg-n-solid-1 text-n-brand shadow-sm'
                    : 'text-n-slate-10 hover:text-n-slate-12'
                "
                @click="selectedMode = 'documents'"
              >
                {{ t('JABVOX_AI_CHAT.MODE_DOCUMENTS') }}
              </button>
            </div>
            <!-- Model selector -->
            <div v-if="hasModels && canUseModels" class="w-40">
              <Select v-model="selectedModelId" :options="modelOptions" />
            </div>
          </div>
        </div>

        <!-- Access denied -->
        <div
          v-if="!canUse"
          class="flex-1 flex items-center justify-center text-center px-6"
        >
          <p class="text-n-slate-11 text-sm">
            {{ t('JABVOX_AI_CHAT.ACCESS_DENIED') }}
          </p>
        </div>

        <!-- No model warning -->
        <div
          v-else-if="!hasModels && !hasDocuments"
          class="flex-1 flex items-center justify-center text-center px-6"
        >
          <p class="text-n-slate-11 text-sm">
            {{ t('JABVOX_AI_CHAT.NO_MODEL') }}
          </p>
        </div>

        <template v-else>
          <!-- Messages -->
          <div
            ref="messagesContainer"
            class="flex-1 overflow-y-auto px-4 sm:px-8 py-6 space-y-4"
          >
            <div
              v-if="messages.length === 0 && !currentSessionId"
              class="flex flex-col items-center justify-center gap-3 text-center mt-16 text-n-slate-10"
            >
              <span class="i-lucide-sparkles size-12 text-n-brand opacity-50" />
              <p class="text-sm">{{ t('JABVOX_AI_CHAT.EMPTY_STATE') }}</p>
            </div>
            <div
              v-for="msg in messages"
              :key="msg.id"
              class="flex gap-3"
              :class="msg.role === 'user' ? 'flex-row-reverse' : ''"
            >
              <div
                class="max-w-[min(720px,85%)] sm:max-w-[min(720px,100%)] rounded-2xl px-4 py-2.5 text-sm leading-relaxed"
                :class="
                  msg.role === 'user'
                    ? 'bg-n-brand text-white rounded-tr-sm'
                    : 'bg-n-solid-1 border border-n-weak text-n-slate-12 rounded-tl-sm shadow-sm'
                "
              >
                <p class="whitespace-pre-wrap break-words">
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
                class="bg-n-solid-1 border border-n-weak rounded-2xl rounded-tl-sm px-4 py-3 shadow-sm"
              >
                <div class="flex gap-1 items-center">
                  <div
                    class="size-1.5 rounded-full bg-n-slate-9 animate-bounce [animation-delay:0ms]"
                  />
                  <div
                    class="size-1.5 rounded-full bg-n-slate-9 animate-bounce [animation-delay:150ms]"
                  />
                  <div
                    class="size-1.5 rounded-full bg-n-slate-9 animate-bounce [animation-delay:300ms]"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- Input area -->
          <div class="border-t border-n-weak bg-n-solid-1 p-4 flex-shrink-0">
            <div
              class="flex flex-col sm:flex-row gap-3 items-stretch sm:items-end max-w-5xl mx-auto w-full"
            >
              <textarea
                v-model="messageInput"
                rows="1"
                class="reset-base flex-1 resize-none border border-n-weak rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-n-slate-7 text-n-slate-12 placeholder:text-n-slate-9 bg-n-background transition-colors"
                :placeholder="t('JABVOX_AI_CHAT.PLACEHOLDER')"
                @keydown="handleKeydown"
              />
              <Button
                icon="i-lucide-send"
                :label="t('JABVOX_AI_CHAT.SEND')"
                :disabled="!canSend"
                class="shrink-0 sm:w-auto justify-center"
                @click="sendMessage"
              />
            </div>
          </div>
        </template>
      </div>

      <!-- Delete session dialog -->
      <Dialog
        ref="deleteDialog"
        type="alert"
        :title="t('JABVOX_AI_CHAT.DELETE_TITLE')"
        :description="t('JABVOX_AI_CHAT.DELETE_BODY')"
        :confirm-button-label="t('JABVOX_AI_CHAT.DELETE')"
        :cancel-button-label="t('JABVOX_AI_CHAT.CANCEL')"
        @confirm="confirmDeleteSession"
      />
    </div>
  </div>
</template>
