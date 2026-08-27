<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { provisioningChatAPI } from 'dashboard/api/jabvox/provisioningChat';

const { t } = useI18n();

// Estado del chat
const messages = ref([]); // [{ id, role, content, metadata, created_at }]
const messageInput = ref('');
const messagesContainer = ref(null);
const isSending = ref(false);
const isLoadingHistory = ref(false);

// Estado del aprovisionamiento (banner superior)
const status = ref(null); // { status, contextforge_base_url, virtual_server_id, mcp_servers, has_token, last_error }
const isLoadingStatus = ref(false);
const isProvisioning = ref(false);

// Error visible (nunca se silencia)
const errorMessage = ref('');

// --- Derivados del estado -------------------------------------------------
// Normalizamos el string de estado para comparaciones y clases.
const statusValue = computed(() => status.value?.status || 'unknown');
const isReady = computed(() => statusValue.value === 'ready');
const mcpServers = computed(() => status.value?.mcp_servers || []);

// El botón "Aprovisionar mi cuenta" solo tiene sentido cuando la cuenta
// todavía no está lista y no hay una operación en curso.
const canProvision = computed(
  () =>
    !isReady.value &&
    statusValue.value !== 'provisioning' &&
    !isProvisioning.value
);

// El input se habilita solo con contenido y sin envío en curso.
const canSend = computed(
  () => messageInput.value.trim().length > 0 && !isSending.value
);

// Mapa de presentación por estado: etiqueta, ayuda, ícono y color del banner.
const statusMeta = computed(() => {
  const map = {
    pending: {
      label: t('JABVOX_PROVISIONING_CHAT.STATUS.PENDING'),
      hint: t('JABVOX_PROVISIONING_CHAT.STATUS.PENDING_HINT'),
      icon: 'i-lucide-circle-dashed',
      tone: 'amber',
    },
    provisioning: {
      label: t('JABVOX_PROVISIONING_CHAT.STATUS.PROVISIONING'),
      hint: t('JABVOX_PROVISIONING_CHAT.STATUS.PROVISIONING_HINT'),
      icon: 'i-lucide-loader',
      tone: 'blue',
    },
    ready: {
      label: t('JABVOX_PROVISIONING_CHAT.STATUS.READY'),
      hint: t('JABVOX_PROVISIONING_CHAT.STATUS.READY_HINT'),
      icon: 'i-lucide-check-circle-2',
      tone: 'teal',
    },
    failed: {
      label: t('JABVOX_PROVISIONING_CHAT.STATUS.FAILED'),
      hint: t('JABVOX_PROVISIONING_CHAT.STATUS.FAILED_HINT'),
      icon: 'i-lucide-alert-triangle',
      tone: 'ruby',
    },
  };
  return (
    map[statusValue.value] || {
      label: t('JABVOX_PROVISIONING_CHAT.STATUS.UNKNOWN'),
      hint: '',
      icon: 'i-lucide-help-circle',
      tone: 'slate',
    }
  );
});

// Clases del banner según el tono (mismos tokens n-*).
const bannerClasses = computed(() => {
  const tones = {
    amber: 'bg-n-amber-3 border-n-amber-6 text-n-amber-11',
    blue: 'bg-n-blue-3 border-n-blue-6 text-n-blue-11',
    teal: 'bg-n-teal-3 border-n-teal-6 text-n-teal-11',
    ruby: 'bg-n-ruby-3 border-n-ruby-6 text-n-ruby-11',
    slate: 'bg-n-alpha-2 border-n-weak text-n-slate-11',
  };
  return tones[statusMeta.value.tone] || tones.slate;
});

// --- Carga inicial --------------------------------------------------------
async function fetchStatus() {
  isLoadingStatus.value = true;
  try {
    const { data } = await provisioningChatAPI.getStatus();
    status.value = data;
  } catch (e) {
    errorMessage.value =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_PROVISIONING_CHAT.ERROR.LOAD_STATUS');
  } finally {
    isLoadingStatus.value = false;
  }
}

async function fetchMessages() {
  isLoadingHistory.value = true;
  try {
    const { data } = await provisioningChatAPI.getMessages();
    // El backend puede devolver el array directo o envuelto en {payload}.
    messages.value = Array.isArray(data) ? data : data?.payload || [];
  } catch (e) {
    errorMessage.value =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_PROVISIONING_CHAT.ERROR.LOAD_MESSAGES');
  } finally {
    isLoadingHistory.value = false;
  }
}

onMounted(async () => {
  await Promise.all([fetchStatus(), fetchMessages()]);
});

// Autoscroll al final cuando cambian los mensajes o el indicador "pensando".
watch([messages, isSending], async () => {
  await nextTick();
  if (messagesContainer.value) {
    messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight;
  }
});

// --- Acciones -------------------------------------------------------------
async function provision() {
  errorMessage.value = '';
  isProvisioning.value = true;
  try {
    const { data } = await provisioningChatAPI.provision();
    status.value = data;
  } catch (e) {
    errorMessage.value =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_PROVISIONING_CHAT.ERROR.PROVISION');
  } finally {
    isProvisioning.value = false;
  }
}

async function sendMessage() {
  const content = messageInput.value.trim();
  if (!content || isSending.value) return;

  errorMessage.value = '';

  // Pintamos de inmediato el mensaje del usuario (optimista).
  messages.value.push({
    id: `local_${Date.now()}`,
    role: 'user',
    content,
    created_at: new Date().toISOString(),
  });
  messageInput.value = '';
  isSending.value = true;

  try {
    const { data } = await provisioningChatAPI.sendMessage(content);
    // El endpoint responde con el mensaje del assistant.
    if (data) {
      messages.value.push({
        id: data.id || `assistant_${Date.now()}`,
        role: data.role || 'assistant',
        content: data.content,
        metadata: data.metadata,
        created_at: data.created_at || new Date().toISOString(),
      });
    }
    // Refrescamos el estado por si el bot cambió el aprovisionamiento.
    fetchStatus();
  } catch (e) {
    errorMessage.value =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_PROVISIONING_CHAT.ERROR.SEND');
  } finally {
    isSending.value = false;
  }
}

function handleKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    if (canSend.value) sendMessage();
  }
}

function formatTime(dateStr) {
  if (!dateStr) return '';
  return new Date(dateStr).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });
}
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-background">
    <!-- Encabezado -->
    <div
      class="border-b border-n-weak bg-n-solid-1 px-4 sm:px-6 py-3 flex items-center gap-3 flex-shrink-0"
    >
      <div
        class="hidden sm:flex items-center justify-center size-10 rounded-xl bg-n-alpha-2 text-n-brand shrink-0"
      >
        <span class="i-lucide-server-cog size-5" />
      </div>
      <div class="min-w-0">
        <h1 class="text-base sm:text-lg font-semibold text-n-slate-12 truncate">
          {{ t('JABVOX_PROVISIONING_CHAT.TITLE') }}
        </h1>
        <p class="text-xs text-n-slate-10 truncate">
          {{ t('JABVOX_PROVISIONING_CHAT.SUBTITLE') }}
        </p>
      </div>
    </div>

    <!-- Banner de estado del aprovisionamiento -->
    <div class="px-4 sm:px-6 pt-4">
      <div class="rounded-xl border px-4 py-3" :class="bannerClasses">
        <div class="flex items-start gap-3">
          <span
            class="size-5 shrink-0 mt-0.5"
            :class="[
              statusMeta.icon,
              statusValue === 'provisioning' || isProvisioning
                ? 'animate-spin'
                : '',
            ]"
          />
          <div class="flex-1 min-w-0">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <p class="text-sm font-semibold">
                {{
                  `${t('JABVOX_PROVISIONING_CHAT.STATUS.LABEL')}: ${statusMeta.label}`
                }}
              </p>
              <div class="flex items-center gap-2">
                <Button
                  icon="i-lucide-refresh-cw"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  :is-loading="isLoadingStatus"
                  :title="t('JABVOX_PROVISIONING_CHAT.RELOAD')"
                  @click="fetchStatus"
                />
                <!-- Botón de aprovisionamiento (solo si no está listo) -->
                <Button
                  v-if="canProvision"
                  :label="t('JABVOX_PROVISIONING_CHAT.PROVISION_BUTTON')"
                  icon="i-lucide-sparkles"
                  size="sm"
                  :is-loading="isProvisioning"
                  @click="provision"
                />
              </div>
            </div>
            <p v-if="statusMeta.hint" class="text-xs mt-1 opacity-90">
              {{ statusMeta.hint }}
            </p>

            <!-- Detalle cuando está listo -->
            <div v-if="isReady" class="mt-3 space-y-2 text-xs text-n-slate-11">
              <div
                v-if="status?.virtual_server_id"
                class="flex flex-wrap items-center gap-1.5"
              >
                <span class="font-medium text-n-slate-12">
                  {{
                    `${t('JABVOX_PROVISIONING_CHAT.STATUS.VIRTUAL_SERVER')}:`
                  }}
                </span>
                <code
                  class="px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-12 break-all"
                >
                  {{ status.virtual_server_id }}
                </code>
              </div>
              <div>
                <p class="font-medium text-n-slate-12 mb-1">
                  {{ `${t('JABVOX_PROVISIONING_CHAT.STATUS.MCP_SERVERS')}:` }}
                </p>
                <ul v-if="mcpServers.length" class="flex flex-wrap gap-1.5">
                  <li
                    v-for="(server, idx) in mcpServers"
                    :key="server.id || server.name || idx"
                    class="flex items-center gap-1.5 px-2 py-1 rounded-lg bg-n-alpha-2 text-n-slate-12"
                  >
                    <span class="i-lucide-plug size-3.5 text-n-brand" />
                    {{ server.name || server.id || server }}
                  </li>
                </ul>
                <p v-else class="text-n-slate-10">
                  {{ t('JABVOX_PROVISIONING_CHAT.STATUS.NO_MCP_SERVERS') }}
                </p>
              </div>
            </div>

            <!-- Último error reportado por el estado -->
            <p
              v-if="status?.last_error"
              class="text-xs mt-2 text-n-ruby-11 break-words"
            >
              {{
                `${t('JABVOX_PROVISIONING_CHAT.STATUS.LAST_ERROR')}: ${status.last_error}`
              }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- Error visible de las operaciones (no se silencia) -->
    <div v-if="errorMessage" class="px-4 sm:px-6 pt-3">
      <div
        class="rounded-xl border border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11 px-4 py-2.5 flex items-start gap-2"
      >
        <span class="i-lucide-alert-circle size-4 shrink-0 mt-0.5" />
        <p class="text-sm break-words flex-1">{{ errorMessage }}</p>
        <button
          class="i-lucide-x size-4 shrink-0 mt-0.5 opacity-70 hover:opacity-100"
          @click="errorMessage = ''"
        />
      </div>
    </div>

    <!-- Mensajes -->
    <div
      ref="messagesContainer"
      class="flex-1 overflow-y-auto px-4 sm:px-8 py-6 space-y-4 min-h-0"
    >
      <!-- Cargando historial -->
      <div
        v-if="isLoadingHistory && messages.length === 0"
        class="flex items-center justify-center gap-2 text-n-slate-10 mt-16"
      >
        <span class="i-lucide-loader size-5 animate-spin" />
        <span class="text-sm">{{ t('JABVOX_PROVISIONING_CHAT.LOADING') }}</span>
      </div>

      <!-- Vacío -->
      <div
        v-else-if="messages.length === 0"
        class="flex flex-col items-center justify-center gap-3 text-center mt-16 text-n-slate-10"
      >
        <span
          class="i-lucide-message-square-plus size-12 text-n-brand opacity-50"
        />
        <p class="text-sm">{{ t('JABVOX_PROVISIONING_CHAT.EMPTY') }}</p>
      </div>

      <!-- Burbujas -->
      <div
        v-for="msg in messages"
        :key="msg.id"
        class="flex gap-3"
        :class="msg.role === 'user' ? 'flex-row-reverse' : ''"
      >
        <div
          class="max-w-[min(720px,85%)] rounded-2xl px-4 py-2.5 text-sm leading-relaxed"
          :class="
            msg.role === 'user'
              ? 'bg-n-brand text-white rounded-tr-sm'
              : 'bg-n-solid-1 border border-n-weak text-n-slate-12 rounded-tl-sm shadow-sm'
          "
        >
          <p class="whitespace-pre-wrap break-words">{{ msg.content }}</p>
          <span
            class="text-xs opacity-60 mt-1 block"
            :class="msg.role === 'user' ? 'text-right' : ''"
          >
            {{ formatTime(msg.created_at) }}
          </span>
        </div>
      </div>

      <!-- Indicador "pensando" -->
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

    <!-- Área de entrada -->
    <div class="border-t border-n-weak bg-n-solid-1 p-4 flex-shrink-0">
      <div
        class="flex flex-col sm:flex-row gap-3 items-stretch sm:items-end max-w-5xl mx-auto w-full"
      >
        <textarea
          v-model="messageInput"
          rows="1"
          class="reset-base flex-1 resize-none border border-n-weak rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-n-slate-7 text-n-slate-12 placeholder:text-n-slate-9 bg-n-background transition-colors"
          :placeholder="t('JABVOX_PROVISIONING_CHAT.PLACEHOLDER')"
          @keydown="handleKeydown"
        />
        <Button
          icon="i-lucide-send"
          :label="t('JABVOX_PROVISIONING_CHAT.SEND')"
          :disabled="!canSend"
          :is-loading="isSending"
          class="shrink-0 sm:w-auto justify-center"
          @click="sendMessage"
        />
      </div>
    </div>
  </div>
</template>
