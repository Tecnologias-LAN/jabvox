<script setup>
// Vista compacta del Chat IA para la burbuja flotante. Mismos agentes, sesiones y comandos
// que la página completa (la lógica vive en los composables useHermes*); aquí cambia solo
// la presentación: la lista de conversaciones y los selectores se despliegan bajo demanda
// para no comerse el alto disponible.
import { ref, nextTick, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useHermesCommands } from 'dashboard/composables/jabvox/useHermesCommands';

const props = defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
  isStreaming: {
    type: Boolean,
    default: false,
  },
  activeTools: {
    type: Array,
    default: () => [],
  },
  hasAgents: {
    type: Boolean,
    default: false,
  },
  agentOptions: {
    type: Array,
    default: () => [],
  },
  modelOptions: {
    type: Array,
    default: () => [],
  },
  sessions: {
    type: Array,
    default: () => [],
  },
  currentSessionId: {
    type: [String, Number],
    default: null,
  },
  selectedAgentId: {
    type: [String, Number],
    default: null,
  },
  selectedModelKey: {
    type: String,
    default: '',
  },
  selectedAgentName: {
    type: String,
    default: '',
  },
});

const emit = defineEmits([
  'sendMessage',
  'selectSession',
  'stop',
  'reset',
  'close',
  'update:selectedAgentId',
  'update:selectedModelKey',
]);

const { t } = useI18n();

const messageInput = ref('');
const messagesContainer = ref(null);
const expandedTool = ref(null);
const showSessions = ref(false);

const {
  showCommands,
  commandIndex,
  filteredCommands,
  onInput,
  applyCommand,
  closeCommands,
  handleCommandKeydown,
  isNewChatCommand,
  isStopCommand,
  isModelCommand,
} = useHermesCommands(messageInput);

const agentModel = computed({
  get: () => props.selectedAgentId,
  set: value => emit('update:selectedAgentId', value),
});

const modelKey = computed({
  get: () => props.selectedModelKey,
  set: value => emit('update:selectedModelKey', value),
});

const scrollToBottom = async () => {
  await nextTick();
  const el = messagesContainer.value;
  if (el) el.scrollTop = el.scrollHeight;
};

watch(() => props.messages, scrollToBottom, { deep: true });

const toggleToolDetail = (msgId, toolId) => {
  const key = `${msgId}:${toolId}`;
  expandedTool.value = expandedTool.value === key ? null : key;
};

const onSelectSession = sessionId => {
  showSessions.value = false;
  emit('selectSession', sessionId);
};

const send = () => {
  const content = messageInput.value.trim();
  if (!content || !props.hasAgents) return;
  emit('sendMessage', {
    content,
    isNewChatCommand: isNewChatCommand(content),
    isStopCommand: isStopCommand(content) && props.isStreaming,
    isModelCommand: isModelCommand(content),
  });
  messageInput.value = '';
  closeCommands();
};

// El menú de comandos consume primero las flechas/Tab/Enter; si no, Enter envía y
// Shift+Enter hace salto de línea.
const onKeydown = e => {
  if (handleCommandKeydown(e)) return;
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    send();
  }
};

const formatTime = value => {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};

const sessionLabel = session =>
  session.title || session.name || t('JABVOX_AI_CHAT.UNTITLED_SESSION');
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-surface-2">
    <!-- Header -->
    <div
      class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak bg-n-solid-1 shrink-0"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="flex items-center justify-center size-8 rounded-lg bg-n-alpha-2 text-n-brand shrink-0"
        >
          <span class="i-lucide-bot size-4" />
        </span>
        <div class="min-w-0">
          <h2 class="text-sm font-semibold text-n-slate-12 truncate">
            {{ t('JABVOX_AI_CHAT.TITLE') }}
          </h2>
          <p
            v-if="selectedAgentName"
            class="text-xs text-n-slate-10 truncate leading-tight"
          >
            {{ selectedAgentName }}
          </p>
        </div>
      </div>
      <div class="flex items-center gap-1 shrink-0">
        <Button
          v-if="hasAgents"
          icon="i-lucide-messages-square"
          variant="ghost"
          :color="showSessions ? 'blue' : 'slate'"
          size="sm"
          :title="t('JABVOX_AI_CHAT.SESSIONS')"
          @click="showSessions = !showSessions"
        />
        <Button
          icon="i-lucide-plus"
          variant="ghost"
          color="slate"
          size="sm"
          :title="t('JABVOX_AI_CHAT.NEW_CHAT')"
          @click="emit('reset')"
        />
        <Button
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="sm"
          @click="emit('close')"
        />
      </div>
    </div>

    <!-- Sin agente Hermes configurado -->
    <div
      v-if="!hasAgents"
      class="flex-1 flex flex-col items-center justify-center gap-3 px-6 text-center"
    >
      <span class="i-lucide-bot-off size-10 text-n-slate-9 opacity-50" />
      <p class="text-sm text-n-slate-10">
        {{ t('JABVOX_AI_CHAT.NO_MODEL') }}
      </p>
    </div>

    <template v-else>
      <!-- Selectores de agente y modelo -->
      <div
        class="flex items-center gap-2 px-3 py-2 border-b border-n-weak bg-n-alpha-1 shrink-0"
      >
        <select
          v-model="agentModel"
          class="flex-1 min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-xs text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
          :title="t('JABVOX_AI_CHAT.AGENT')"
        >
          <option
            v-for="option in agentOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
        <select
          v-if="modelOptions.length"
          v-model="modelKey"
          class="flex-1 min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1 text-xs text-n-slate-12 focus:outline-none focus:ring-1 focus:ring-n-brand"
          :title="t('JABVOX_AI_CHAT.MODEL')"
        >
          <option value="">{{ t('JABVOX_AI_CHAT.DEFAULT_MODEL') }}</option>
          <option
            v-for="option in modelOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </div>

      <!-- Lista de conversaciones (mismas que la página completa) -->
      <div
        v-if="showSessions"
        class="border-b border-n-weak bg-n-solid-1 max-h-48 overflow-y-auto shrink-0"
      >
        <p
          v-if="!sessions.length"
          class="px-4 py-3 text-xs text-n-slate-10 text-center"
        >
          {{ t('JABVOX_AI_CHAT.NO_SESSIONS') }}
        </p>
        <button
          v-for="session in sessions"
          :key="session.session_id"
          type="button"
          class="w-full flex items-center gap-2 px-3 py-2 text-left text-xs hover:bg-n-alpha-1"
          :class="
            session.session_id === currentSessionId
              ? 'bg-n-alpha-2 text-n-brand font-medium'
              : 'text-n-slate-11'
          "
          @click="onSelectSession(session.session_id)"
        >
          <span class="i-lucide-message-circle size-3 shrink-0" />
          <span class="truncate min-w-0">{{ sessionLabel(session) }}</span>
        </button>
      </div>

      <!-- Mensajes -->
      <div
        ref="messagesContainer"
        class="flex-1 overflow-y-auto px-4 py-4 space-y-3"
      >
        <div
          v-if="messages.length === 0"
          class="flex flex-col items-center justify-center gap-3 text-center mt-12 text-n-slate-10"
        >
          <span class="i-lucide-sparkles size-10 text-n-brand opacity-50" />
          <p class="text-sm">{{ t('JABVOX_AI_CHAT.EMPTY_STATE') }}</p>
        </div>
        <div
          v-for="msg in messages"
          :key="msg.id"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[90%] min-w-0 rounded-2xl px-3 py-2 text-sm leading-relaxed"
            :class="
              msg.role === 'user'
                ? 'bg-n-brand text-white rounded-tr-sm'
                : 'bg-n-solid-1 border border-n-weak text-n-slate-12 rounded-tl-sm shadow-sm'
            "
          >
            <p class="whitespace-pre-wrap break-words">
              {{ msg.content || msg.content_jabvox }}
            </p>

            <!-- Herramientas usadas por el agente (expandibles) -->
            <div
              v-if="msg.tools && msg.tools.length"
              class="mt-2 flex flex-col gap-1 border-t border-n-weak pt-2"
            >
              <p class="text-xs font-medium text-n-slate-10">
                {{ t('JABVOX_AI_CHAT.TOOLS_USED') }}
              </p>
              <div v-for="tool in msg.tools" :key="tool.id">
                <button
                  type="button"
                  class="w-full flex items-center gap-2 text-left text-xs rounded-lg px-2 py-1 hover:bg-n-alpha-1"
                  @click="toggleToolDetail(msg.id, tool.id)"
                >
                  <span
                    v-if="tool.status === 'running'"
                    class="i-lucide-loader-2 animate-spin size-3 text-n-slate-10"
                  />
                  <span v-else class="i-lucide-check size-3 text-green-500" />
                  <span class="truncate min-w-0">
                    {{ tool.emoji }} {{ tool.label }}
                  </span>
                  <span
                    v-if="tool.detail"
                    class="i-lucide-chevron-down size-3 text-n-slate-9 ml-auto shrink-0"
                    :class="
                      expandedTool === `${msg.id}:${tool.id}`
                        ? 'rotate-180'
                        : ''
                    "
                  />
                </button>
                <pre
                  v-if="tool.detail && expandedTool === `${msg.id}:${tool.id}`"
                  class="mt-1 ml-5 max-w-full rounded-lg bg-n-alpha-1 p-2 text-xs text-n-slate-11 whitespace-pre-wrap break-all overflow-x-auto"
                  >{{ tool.detail }}</pre
                >
              </div>
            </div>

            <span
              class="text-xs opacity-60 mt-1 block"
              :class="msg.role === 'user' ? 'text-right' : ''"
            >
              {{ formatTime(msg.created_at) }}
            </span>
          </div>
        </div>
      </div>

      <!-- Herramientas en vivo -->
      <div
        v-if="activeTools.length"
        class="border-t border-n-weak bg-n-alpha-1 px-4 py-2 flex flex-wrap gap-2 shrink-0"
      >
        <span
          v-for="tool in activeTools"
          :key="tool.id"
          class="flex items-center gap-1 text-xs text-n-slate-11 rounded-full bg-n-solid-1 border border-n-weak px-2 py-0.5"
        >
          <span
            v-if="tool.status === 'running'"
            class="i-lucide-loader-2 animate-spin size-3"
          />
          <span v-else class="i-lucide-check size-3 text-green-500" />
          {{ tool.emoji }} {{ tool.label }}
        </span>
      </div>

      <!-- Input -->
      <div class="border-t border-n-weak bg-n-solid-1 p-3 shrink-0 relative">
        <!-- Menú de comandos "/" -->
        <div
          v-if="showCommands && filteredCommands.length"
          class="absolute bottom-full left-3 right-3 mb-1 max-h-48 overflow-y-auto rounded-xl border border-n-weak bg-n-solid-1 shadow-lg z-10"
        >
          <button
            v-for="(command, index) in filteredCommands"
            :key="command.cmd"
            type="button"
            class="w-full flex flex-col items-start gap-0.5 px-3 py-2 text-left hover:bg-n-alpha-1"
            :class="index === commandIndex ? 'bg-n-alpha-2' : ''"
            @click="applyCommand(command.cmd)"
          >
            <span class="text-xs font-medium text-n-slate-12">
              {{ command.cmd }}
            </span>
            <span class="text-xs text-n-slate-10 leading-tight">
              {{ command.desc }}
            </span>
          </button>
        </div>

        <div class="flex items-end gap-2">
          <textarea
            v-model="messageInput"
            rows="1"
            class="flex-1 resize-none max-h-32 rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-brand"
            :placeholder="t('JABVOX_AI_CHAT.PLACEHOLDER')"
            @input="onInput"
            @keydown="onKeydown"
          />
          <Button
            v-if="isStreaming"
            icon="i-lucide-square"
            color="ruby"
            size="sm"
            :title="t('JABVOX_AI_CHAT.STOP')"
            @click="emit('stop')"
          />
          <Button
            v-else
            icon="i-lucide-send"
            size="sm"
            :disabled="!messageInput.trim()"
            :title="t('JABVOX_AI_CHAT.SEND')"
            @click="send"
          />
        </div>
      </div>
    </template>
  </div>
</template>
