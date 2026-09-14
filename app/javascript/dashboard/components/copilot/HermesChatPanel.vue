<script setup>
// Vista compacta del Chat IA para la burbuja flotante. Es el mismo agente Hermes que la
// página completa; aquí solo se muestra la conversación en curso (sin lista de sesiones).
import { ref, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

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
});

const emit = defineEmits(['sendMessage', 'stop', 'reset', 'close']);

const { t } = useI18n();

const messageInput = ref('');
const messagesContainer = ref(null);
const expandedTool = ref(null);

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

const send = () => {
  const content = messageInput.value.trim();
  if (!content || !props.hasAgents) return;
  emit('sendMessage', content);
  messageInput.value = '';
};

// Enter envía; Shift+Enter hace salto de línea.
const onKeydown = e => {
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
        <h2 class="text-sm font-semibold text-n-slate-12 truncate">
          {{ t('JABVOX_AI_CHAT.TITLE') }}
        </h2>
      </div>
      <div class="flex items-center gap-1 shrink-0">
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
      <div class="border-t border-n-weak bg-n-solid-1 p-3 shrink-0">
        <div class="flex items-end gap-2">
          <textarea
            v-model="messageInput"
            rows="1"
            class="flex-1 resize-none max-h-32 rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:ring-2 focus:ring-n-brand"
            :placeholder="t('JABVOX_AI_CHAT.PLACEHOLDER')"
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
