<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { deviseAuthHeaders } from 'dashboard/helper/deviseAuthHeaders';
import { useAlert } from 'dashboard/composables';
import { aiChatAPI, hermesConnectionsAPI } from 'dashboard/api/jabvox/aiChat';
import { useHermesCommands } from 'dashboard/composables/jabvox/useHermesCommands';
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

// Comandos "/" de Hermes: la lista, el filtrado y la navegación del menú viven en
// useHermesCommands, compartido con la burbuja flotante para que ambas superficies
// ofrezcan exactamente los mismos comandos.
const {
  showCommands,
  commandIndex,
  filteredCommands,
  onInput,
  applyCommand,
  handleCommandKeydown,
  isNewChatCommand,
  isModelCommand,
} = useHermesCommands(messageInput);

const messagesContainer = ref(null);
const hermesAgents = ref([]); // agentes Hermes ligados a este usuario (N:N)
const selectedAgentId = ref(null); // conexión Hermes elegida en el chat
// Picker de MODELO LLM del agente (glm-5, etc.). Vacío = usa el default del agente en Hermes.
const modelOptions = ref([]); // [{ value:'zai::glm-5', label:'glm-5', model, provider }]
const selectedModelKey = ref(''); // 'provider::model' elegido; '' = default del agente
const isStreaming = ref(false);
// Permite ABORTAR el streaming en curso (botón Detener) para no bloquear al usuario.
const streamController = ref(null);
const activeTools = ref([]); // chips de herramientas en vivo (Telegram-like)
const expandedTool = ref(null); // clave "msgId:toolId" de la herramienta desplegada
const fileInput = ref(null);
const attachments = ref([]); // [{ type:'image'|'file', name, url(base64 o http) }]

// Lee un archivo como data URL (base64) para enviarlo inline (imágenes vision).
function readAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

async function onFilesSelected(e) {
  const files = Array.from(e.target.files || []);
  // Imágenes → base64 inline (formato vision); docs/audios → data URL para que Hermes lo lea.
  const loaded = await Promise.all(
    files.map(async file => ({
      type: file.type.startsWith('image/') ? 'image' : 'file',
      name: file.name,
      url: await readAsDataUrl(file),
    }))
  );
  attachments.value.push(...loaded);
  e.target.value = ''; // permite re-seleccionar el mismo archivo
}

function removeAttachment(i) {
  attachments.value.splice(i, 1);
}

function toggleToolDetail(msgId, toolId) {
  const key = `${msgId}:${toolId}`;
  expandedTool.value = expandedTool.value === key ? null : key;
}
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
const myAccess = computed(() => store.getters['jabvoxAiChat/getMyAccess']);
const uiFlags = computed(() => store.getters['jabvoxAiChat/getUIFlags']);

const isSending = computed(() => uiFlags.value.isSending || isStreaming.value);
const canUse = computed(() => !myAccess.value || myAccess.value.can_use);
// El usuario chatea si tiene al menos un agente Hermes ligado.
const hasAgents = computed(() => (hermesAgents.value || []).length > 0);
// Hay contenido listo para enviar (texto o adjuntos), con acceso y agente disponibles.
// NO depende de isSending: el usuario puede escribir su siguiente mensaje mientras el
// bot responde. El envío efectivo (ver sendMessage) espera/aborta la respuesta anterior.
const canSend = computed(
  () =>
    (messageInput.value.trim().length > 0 || attachments.value.length > 0) &&
    canUse.value &&
    hasAgents.value
);
// Selector de agente Hermes (cada opción es una conexión ligada al usuario).
const agentOptions = computed(() =>
  (hermesAgents.value || []).map(a => ({ value: a.id, label: a.name }))
);

// El modelo/proveedor elegidos en el picker, o {} si se usa el default del agente.
const selectedModelOverride = computed(() => {
  const opt = modelOptions.value.find(o => o.value === selectedModelKey.value);
  return opt ? { llm_model: opt.model, llm_provider: opt.provider } : {};
});

// Opciones del Select de modelo con "Modelo por defecto" (value '') al frente.
const modelSelectOptions = computed(() => [
  { value: '', label: t('JABVOX_AI_CHAT.DEFAULT_MODEL') },
  ...modelOptions.value.map(o => ({ value: o.value, label: o.label })),
]);

function selectSession(sessionId) {
  currentSessionId.value = sessionId;
  showSessions.value = false;
  // Cada sesión pertenece a UN agente: al abrirla, se selecciona ese agente para que la
  // conversación continúe SIEMPRE con el mismo (no se puede responder con otro).
  const session = sessions.value.find(s => s.session_id === sessionId);
  if (session?.connection_id) selectedAgentId.value = session.connection_id;
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

async function loadHermesAgents() {
  try {
    const { data } = await hermesConnectionsAPI.mine();
    hermesAgents.value = data;
    if (data.length) selectedAgentId.value = data[0].id;
  } catch {
    hermesAgents.value = [];
  }
}

onMounted(async () => {
  await Promise.all([
    store.dispatch('jabvoxAiChat/fetchMyAccess'),
    store.dispatch('jabvoxAiChat/fetchSessions'),
    loadHermesAgents(),
  ]);
  syncPushStatus();
  if (sessions.value.length > 0) selectSession(sessions.value[0].session_id);
});

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

function appendToMessage(sessionId, messageId, text) {
  store.commit('jabvoxAiChat/APPEND_MESSAGE_CONTENT', {
    sessionId,
    messageId,
    text,
  });
}

// Chips de herramientas: running → spinner; completed (mismo toolCallId) → ✓.
// El evento 'running' trae el comando/código en `label`; el 'completed' solo trae status.
// Por eso preservamos el label del primer evento y NO lo pisamos con el segundo.
function upsertTool(tool) {
  const id = tool.toolCallId || tool.tool;
  const idx = activeTools.value.findIndex(x => x.id === id);
  if (idx === -1) {
    activeTools.value.push({
      id,
      emoji: tool.emoji || '🔧',
      tool: tool.tool || 'tool',
      label: tool.tool || 'tool', // nombre corto para el chip (terminal, execute_code…)
      detail: tool.label || tool.detail || tool.output || '', // comando/código completo
      status: tool.status,
    });
    return;
  }
  // Actualiza solo lo que llega (status siempre; detalle si viene más completo).
  const prev = activeTools.value[idx];
  activeTools.value[idx] = {
    ...prev,
    status: tool.status || prev.status,
    detail: tool.label || tool.detail || tool.output || prev.detail,
    emoji: tool.emoji || prev.emoji,
  };
}

function handleFrame(eventType, data, sessionId, assistantId) {
  let json;
  try {
    json = JSON.parse(data);
  } catch {
    return;
  }
  if (eventType === 'hermes.tool.progress') {
    upsertTool(json);
    return;
  }
  if (json.error) {
    appendToMessage(sessionId, assistantId, `\n\nError: ${json.error}`);
    return;
  }
  const delta = json.choices?.[0]?.delta?.content;
  if (delta) appendToMessage(sessionId, assistantId, delta);
}

// Procesa un bloque de líneas SSE ya separadas por salto de línea.
function processSseLines(lines, ctx, sessionId, assistantId) {
  lines.forEach(line => {
    if (line.startsWith('event:')) {
      ctx.eventType = line.slice(6).trim();
    } else if (line.startsWith('data:')) {
      const data = line.slice(5).trim();
      if (data === '[DONE]' || data === '') return;
      handleFrame(ctx.eventType, data, sessionId, assistantId);
      ctx.eventType = null;
    }
  });
}

// Lee el stream SSE: frames de texto (delta.content) y eventos hermes.tool.progress.
async function consumeStream(res, sessionId, assistantId) {
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  const ctx = { eventType: null };
  let buffer = '';
  let chunk = await reader.read();
  while (!chunk.done) {
    buffer += decoder.decode(chunk.value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();
    processSseLines(lines, ctx, sessionId, assistantId);
    // eslint-disable-next-line no-await-in-loop
    chunk = await reader.read();
  }
}

// Envía el mensaje al agente Hermes en STREAMING (SSE): pinta el texto que fluye y los chips
// de herramientas en vivo (como Telegram). Al terminar, refresca la sesión.
async function streamAssistant(
  content,
  apiSessionId,
  displaySessionId,
  isNewChat,
  sentAttachments
) {
  const assistantId = Date.now() + 1;
  isStreaming.value = true;
  streamController.value = new AbortController();
  activeTools.value = [];
  store.commit('jabvoxAiChat/ADD_MESSAGE', {
    sessionId: displaySessionId,
    message: {
      id: assistantId,
      role: 'assistant',
      content: '',
      created_at: new Date(),
    },
  });

  try {
    const res = await fetch(aiChatAPI.streamUrl(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...deviseAuthHeaders(),
      },
      credentials: 'same-origin',
      signal: streamController.value?.signal,
      body: JSON.stringify({
        content,
        session_id: apiSessionId,
        connection_id: selectedAgentId.value,
        attachments: sentAttachments,
        // Modelo/proveedor elegidos en el picker (vacío = default del agente en Hermes).
        // Con "/model ..." se omite: el usuario está eligiendo modelo por comando y mandar
        // además el del picker sobrescribiría justo lo que el comando pide.
        ...(isModelCommand(content) ? {} : selectedModelOverride.value),
      }),
    });
    if (!res.ok || !res.body) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || t('JABVOX_AI_CHAT.ERROR'));
    }
    await consumeStream(res, displaySessionId, assistantId);
    if (isNewChat) await store.dispatch('jabvoxAiChat/fetchSessions');
  } catch (e) {
    // Si el usuario detuvo el stream (AbortController), no es un error: marca el corte.
    if (e.name === 'AbortError') {
      appendToMessage(displaySessionId, assistantId, '\n\n_(detenido)_');
    } else {
      appendToMessage(displaySessionId, assistantId, `\n\nError: ${e.message}`);
    }
  } finally {
    // Guarda las herramientas usadas al final del mensaje (quedan expandibles).
    if (activeTools.value.length) {
      store.commit('jabvoxAiChat/SET_MESSAGE_TOOLS', {
        sessionId: displaySessionId,
        messageId: assistantId,
        tools: [...activeTools.value],
      });
    }
    isStreaming.value = false;
    streamController.value = null;
    activeTools.value = [];
  }
}

// Detiene la respuesta en curso (aborta el stream). El input queda libre de inmediato.
function stopStreaming() {
  streamController.value?.abort();
}

// Carga los modelos LLM que ofrece el agente elegido (para el picker /model). Jabvox
// reenvía la respuesta de Hermes sin validarla, así que su forma no está garantizada:
// toleramos providers[] o array raíz, models[] u options[], slug/name/provider, y modelos
// como string o como objeto {id|name|slug}. Silencioso si falla: sin modelos, el chat sigue
// usando el default del agente.
const providerSlug = p => p?.slug || p?.name || p?.provider || '';
const modelName = m =>
  typeof m === 'string' ? m : m?.id || m?.name || m?.slug || '';

const providerList = data => {
  if (Array.isArray(data?.providers)) return data.providers;
  if (Array.isArray(data)) return data;
  return [];
};

async function loadModelOptions(connectionId) {
  modelOptions.value = [];
  selectedModelKey.value = '';
  if (!connectionId) return;
  try {
    const { data } = await hermesConnectionsAPI.modelOptions(connectionId);
    const providers = providerList(data);
    const opts = [];
    let current = '';
    providers.forEach(p => {
      if (p?.authenticated === false) return; // solo proveedores utilizables
      const slug = providerSlug(p);
      if (!slug) return;
      (p.models || p.options || []).forEach(m => {
        const name = modelName(m);
        if (!name) return;
        const value = `${slug}::${name}`;
        opts.push({ value, label: name, provider: slug, model: name });
        if (p.is_current && data?.model === name) current = value;
      });
    });
    modelOptions.value = opts;
    selectedModelKey.value = current; // '' si no hay match → default del agente
  } catch {
    modelOptions.value = [];
  }
}

// Si el usuario cambia de agente mientras está en una sesión que pertenece a OTRO agente,
// se abre una conversación nueva: una sesión existente solo se ejecuta con su propio agente.
watch(selectedAgentId, (newId, oldId) => {
  // Al cambiar de agente, recarga sus modelos disponibles (cada agente puede ofrecer otros).
  loadModelOptions(newId);
  if (!oldId || newId === oldId || !currentSessionId.value) return;
  const session = sessions.value.find(
    s => s.session_id === currentSessionId.value
  );
  // Solo forzamos sesión nueva si la actual ya tiene dueño y es distinto al elegido.
  if (session?.connection_id && session.connection_id !== newId) {
    if (isStreaming.value) stopStreaming();
    newChat();
  }
});

async function sendMessage() {
  const content = messageInput.value.trim();
  const hasAttachments = attachments.value.length > 0;
  if (!content && !hasAttachments) return;
  if (!hasAgents.value) {
    alert(t('JABVOX_AI_CHAT.NO_MODEL'));
    return;
  }

  // Si el bot aún responde, detén esa respuesta antes de enviar el nuevo mensaje: así el
  // usuario nunca queda bloqueado y no se solapan dos streams.
  if (isStreaming.value) {
    stopStreaming();
    await nextTick();
  }

  // "/new", "/reset" y "/clear" inician una conversación nueva en Jabvox (aparece en la
  // lista izquierda) en vez de enviarse a Hermes. Las demás (/model, /status, /retry...)
  // sí van a Hermes para que él las interprete.
  if (isNewChatCommand(content)) {
    if (isStreaming.value) stopStreaming();
    newChat();
    showCommands.value = false;
    messageInput.value = '';
    return;
  }

  // "/stop" a secas: detiene la respuesta en curso sin enviar nada a Hermes.
  if (content === '/stop' && isStreaming.value) {
    stopStreaming();
    showCommands.value = false;
    messageInput.value = '';
    return;
  }

  const isNewChat = !currentSessionId.value;
  const apiSessionId = currentSessionId.value || null;
  const displaySessionId = apiSessionId || `pending_${Date.now()}`;
  if (isNewChat) currentSessionId.value = displaySessionId;

  const sentAttachments = [...attachments.value];
  const shownContent =
    content || `📎 ${sentAttachments.map(a => a.name).join(', ')}`;
  store.commit('jabvoxAiChat/ADD_MESSAGE', {
    sessionId: displaySessionId,
    message: {
      id: Date.now(),
      role: 'user',
      content: shownContent,
      created_at: new Date(),
    },
  });
  messageInput.value = '';
  attachments.value = [];
  showCommands.value = false;

  await streamAssistant(
    content,
    apiSessionId,
    displaySessionId,
    isNewChat,
    sentAttachments
  );

  // Hermes no anuncia el cambio de modelo por el stream, así que tras un "/model" releemos
  // model/options para que el picker refleje el modelo realmente activo.
  if (isModelCommand(content)) await loadModelOptions(selectedAgentId.value);
}

function handleKeydown(e) {
  // El menú de comandos consume primero flechas/Tab/Enter/Escape.
  if (handleCommandKeydown(e)) return;
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
              <!-- Agente al que pertenece la sesión (solo se ejecuta con este). -->
              <span
                v-if="session.agent"
                class="flex items-center gap-1 text-xs text-n-slate-10 mt-0.5 truncate"
                :title="session.agent"
              >
                <span class="i-lucide-bot size-3 shrink-0" />
                {{ session.agent }}
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
            <!-- Selector de agente Hermes (los ligados a este usuario) -->
            <div v-if="hasAgents" class="w-48">
              <Select v-model="selectedAgentId" :options="agentOptions" />
            </div>
            <!-- Selector de MODELO del agente (equivale a /model). Solo si el agente
                 reporta modelos disponibles; la 1ª opción usa el default del agente. -->
            <div v-if="hasAgents && modelOptions.length" class="w-44">
              <Select
                v-model="selectedModelKey"
                :options="modelSelectOptions"
              />
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

        <!-- Sin agente Hermes asignado -->
        <div
          v-else-if="!hasAgents"
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
                class="max-w-[min(720px,85%)] sm:max-w-[min(720px,100%)] min-w-0 rounded-2xl px-4 py-2.5 text-sm leading-relaxed"
                :class="
                  msg.role === 'user'
                    ? 'bg-n-brand text-white rounded-tr-sm'
                    : 'bg-n-solid-1 border border-n-weak text-n-slate-12 rounded-tl-sm shadow-sm'
                "
              >
                <p class="whitespace-pre-wrap break-words">
                  {{ msg.content || msg.content_jabvox }}
                </p>

                <!-- Herramientas usadas por el agente (al final, expandibles) -->
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
                      <span
                        v-else
                        class="i-lucide-check size-3 text-green-500"
                      />
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
                      v-if="
                        tool.detail && expandedTool === `${msg.id}:${tool.id}`
                      "
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

          <!-- Herramientas del agente en vivo (como Telegram) -->
          <div
            v-if="activeTools.length"
            class="border-t border-n-weak bg-n-alpha-1 px-4 py-2 flex flex-wrap gap-2 max-w-5xl mx-auto w-full"
          >
            <span
              v-for="tool in activeTools"
              :key="tool.id"
              class="inline-flex items-center gap-1.5 text-xs rounded-full px-2.5 py-1 bg-n-solid-1 border border-n-weak"
            >
              <span
                v-if="tool.status === 'running'"
                class="i-lucide-loader-2 animate-spin size-3 text-n-slate-10"
              />
              <span v-else class="i-lucide-check size-3 text-green-500" />
              {{ tool.label }}
            </span>
          </div>

          <!-- Adjuntos seleccionados (preview) -->
          <div
            v-if="attachments.length"
            class="border-t border-n-weak bg-n-alpha-1 px-4 py-2 flex flex-wrap gap-2 max-w-5xl mx-auto w-full"
          >
            <span
              v-for="(att, i) in attachments"
              :key="i"
              class="inline-flex items-center gap-1.5 text-xs rounded-lg px-2 py-1 bg-n-solid-1 border border-n-weak max-w-full"
            >
              <span
                :class="
                  att.type === 'image' ? 'i-lucide-image' : 'i-lucide-file'
                "
                class="size-3 shrink-0"
              />
              <span class="truncate">{{ att.name }}</span>
              <button
                type="button"
                class="i-lucide-x size-3 shrink-0 text-n-slate-10 hover:text-n-slate-12"
                @click="removeAttachment(i)"
              />
            </span>
          </div>

          <!-- Input area -->
          <div class="border-t border-n-weak bg-n-solid-1 p-4 flex-shrink-0">
            <div
              class="flex flex-col sm:flex-row gap-3 items-stretch sm:items-end max-w-5xl mx-auto w-full"
            >
              <input
                ref="fileInput"
                type="file"
                class="hidden"
                accept="image/*,.pdf,.txt,.doc,.docx,audio/*"
                multiple
                @change="onFilesSelected"
              />
              <Button
                icon="i-lucide-paperclip"
                variant="ghost"
                color="slate"
                class="shrink-0"
                :title="t('JABVOX_AI_CHAT.ATTACH')"
                @click="fileInput?.click()"
              />
              <div class="relative flex-1">
                <!-- Menú de comandos "/" (Hermes los interpreta) -->
                <div
                  v-if="showCommands"
                  class="absolute bottom-full mb-2 left-0 right-0 z-20 rounded-xl border border-n-weak bg-n-solid-1 shadow-lg overflow-hidden"
                >
                  <button
                    v-for="(c, i) in filteredCommands"
                    :key="c.cmd"
                    type="button"
                    class="w-full text-left px-4 py-2.5 flex items-center gap-3 hover:bg-n-alpha-1"
                    :class="i === commandIndex ? 'bg-n-alpha-2' : ''"
                    @mousedown.prevent="applyCommand(c.cmd)"
                    @mouseenter="commandIndex = i"
                  >
                    <span class="font-mono text-sm text-n-slate-12">{{
                      c.cmd
                    }}</span>
                    <span class="text-xs text-n-slate-10">{{ c.desc }}</span>
                  </button>
                </div>
                <textarea
                  v-model="messageInput"
                  rows="1"
                  class="reset-base w-full resize-none border border-n-weak rounded-xl px-4 py-3 text-sm focus:outline-none focus:border-n-slate-7 text-n-slate-12 placeholder:text-n-slate-9 bg-n-background transition-colors"
                  :placeholder="t('JABVOX_AI_CHAT.PLACEHOLDER')"
                  @keydown="handleKeydown"
                  @input="onInput"
                />
              </div>
              <!-- Mientras el bot responde, el botón "Detener" aborta el stream. Si no,
                   envía. El textarea nunca se bloquea: puedes escribir en cualquier momento. -->
              <Button
                v-if="isStreaming"
                icon="i-lucide-square"
                :label="t('JABVOX_AI_CHAT.STOP')"
                color="ruby"
                class="shrink-0 sm:w-auto justify-center"
                @click="stopStreaming"
              />
              <Button
                v-else
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
