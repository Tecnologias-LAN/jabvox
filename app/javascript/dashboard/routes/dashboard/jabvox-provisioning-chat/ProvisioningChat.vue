<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { provisioningChatAPI } from 'dashboard/api/jabvox/provisioningChat';
import { deviseAuthHeaders } from 'dashboard/helper/deviseAuthHeaders';

const { t } = useI18n();

// Estado del chat
const messages = ref([]); // [{ id, role, content, metadata, created_at }]
const messageInput = ref('');
const messagesContainer = ref(null);
const isSending = ref(false);
const isLoadingHistory = ref(false);
// Conversaciones: el chat era un hilo único por cuenta y cada turno llegaba a Hermes sin
// historial. Ahora cada conversación tiene su session_id y su contexto propio.
const sessions = ref([]); // [{ session_id, last_at, messages_count }]
const currentSessionId = ref('');
// Modelo elegido en el picker; '' = el default del aprovisionador.
const modelOptions = ref([]); // [{ value, label, model, provider }]
const selectedModelKey = ref('');
// Run activo: el agente trabaja "con estado", así que puede pararse a pedir aprobación
// antes de ejecutar algo que su escaneo de seguridad marcó. Sin esto esa pregunta nunca
// llegaba al operador y el agente se quedaba bloqueado en silencio.
const currentRunId = ref('');
const hermesSessionId = ref('');
// Solicitud de aprobación pendiente: { command, description, choices, request_id }
const pendingApproval = ref(null);
const isResolvingApproval = ref(false);
// Streaming (SSE) como el Chat IA: progreso en vivo + herramientas + detener.
const isStreaming = ref(false);
const streamController = ref(null); // AbortController del stream en curso
const activeTools = ref([]); // chips de herramientas en vivo del turno actual
const expandedTool = ref(null); // clave "msgId:toolId" de la herramienta desplegada

// Error visible (nunca se silencia)
const errorMessage = ref('');

// El input se habilita solo con contenido y sin un stream en curso.
const canSend = computed(
  () => messageInput.value.trim().length > 0 && !isStreaming.value
);

// --- Carga inicial --------------------------------------------------------
// Normaliza las tools guardadas (formato backend) al que espera el render (como upsertTool),
// para que al reabrir el chat las herramientas se vean igual que en vivo.
function normalizeStoredTools(list) {
  if (!Array.isArray(list)) return [];
  return list.map(tool => ({
    id: tool.toolCallId || tool.tool,
    emoji: tool.emoji || '🔧',
    tool: tool.tool || 'tool',
    label: tool.tool || 'tool',
    detail: tool.label || tool.detail || tool.output || '',
    status: tool.status,
  }));
}

async function fetchMessages(sessionId) {
  isLoadingHistory.value = true;
  try {
    const { data } = await provisioningChatAPI.getMessages(sessionId);
    // El backend puede devolver el array directo o envuelto en {payload}.
    const rows = Array.isArray(data) ? data : data?.payload || [];
    // Rehidrata las tools de cada mensaje al formato de render.
    messages.value = rows.map(m => {
      const tools = m.metadata?.tools;
      if (!tools) return m;
      return {
        ...m,
        metadata: { ...m.metadata, tools: normalizeStoredTools(tools) },
      };
    });
    // Si no se pidió una sesión concreta, el backend devolvió la más reciente: se adopta
    // como actual para que el siguiente mensaje continúe esa conversación.
    if (!sessionId && rows.length > 0 && rows[0].session_id) {
      currentSessionId.value = rows[0].session_id;
    }
    // Recupera el run y la sesión de Hermes del último mensaje que los tenga: así /model y
    // /steer siguen funcionando al volver a una conversación.
    const withRun = [...rows]
      .reverse()
      .find(m => m.metadata?.hermes_session_id);
    hermesSessionId.value = withRun?.metadata?.hermes_session_id || '';
    currentRunId.value = withRun?.metadata?.run_id || '';
    // Si el último turno quedó esperando autorización, se restaura la solicitud: el operador
    // vuelve al chat y encuentra los botones donde los dejó, no una conversación muda.
    const last = rows[rows.length - 1];
    const saved =
      last?.status === 'waiting_approval' ? last.metadata?.approval : null;
    pendingApproval.value = saved
      ? {
          command: saved.command || '',
          description: saved.description || '',
          choices: Array.isArray(saved.choices)
            ? saved.choices
            : ['once', 'deny'],
          requestId: saved.request_id || '',
          runId: saved.run_id || last.metadata?.run_id || '',
        }
      : null;
  } catch (e) {
    errorMessage.value =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_PROVISIONING_CHAT.ERROR.LOAD_MESSAGES');
  } finally {
    isLoadingHistory.value = false;
  }
}

// Distintivo del estado de un turno del asistente. Solo se muestra cuando NO terminó bien:
// un turno completado no necesita adorno, pero uno en curso, interrumpido o esperando
// autorización sí — es lo que el usuario necesita ver al volver al chat.
const TURN_BADGES = {
  streaming: {
    icon: 'i-lucide-loader-circle animate-spin',
    class: 'bg-n-alpha-2 text-n-slate-11',
  },
  waiting_approval: {
    icon: 'i-lucide-shield-alert',
    class: 'bg-n-amber-3 text-n-amber-11',
  },
  interrupted: {
    icon: 'i-lucide-circle-slash',
    class: 'bg-n-alpha-2 text-n-slate-10',
  },
  failed: {
    icon: 'i-lucide-alert-circle',
    class: 'bg-n-ruby-3 text-n-ruby-11',
  },
};

function turnBadge(msg) {
  if (msg.role !== 'assistant') return null;
  const badge = TURN_BADGES[msg.status];
  if (!badge) return null;
  return {
    ...badge,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(
      `JABVOX_PROVISIONING_CHAT.TURN_STATUS.${msg.status.toUpperCase()}`
    ),
  };
}

// Etiqueta de la conversación en la lista. No hay campo title, así que se muestra la fecha
// del último mensaje (hoy → solo la hora).
function formatSessionDate(value) {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  const today = new Date();
  const sameDay = d.toDateString() === today.toDateString();
  return sameDay
    ? d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString([], { day: '2-digit', month: 'short' });
}

async function fetchSessions() {
  try {
    const { data } = await provisioningChatAPI.getSessions();
    sessions.value = Array.isArray(data) ? data : data?.payload || [];
  } catch {
    sessions.value = []; // silencioso: sin la lista el chat sigue usable
  }
}

// Modelos del aprovisionador para el picker. Tolera providers[] o array raíz, y modelos
// como string u objeto, igual que el Chat IA. Silencioso si falla.
const modelName = m =>
  typeof m === 'string' ? m : m?.id || m?.name || m?.slug || '';

async function fetchModelOptions() {
  try {
    const { data } = await provisioningChatAPI.getModelOptions();
    const list = data?.data || [];
    const opts = [];
    list.forEach(entry => {
      const name = modelName(entry);
      if (!name) return;
      const provider = entry?.provider || entry?.owned_by || '';
      opts.push({
        value: provider ? `${provider}::${name}` : name,
        label: name,
        model: name,
        provider,
      });
    });
    modelOptions.value = opts;
  } catch {
    modelOptions.value = [];
  }
}

// Opciones del select con "Modelo por defecto" (value '') al frente.
const modelSelectOptions = computed(() => [
  { value: '', label: t('JABVOX_PROVISIONING_CHAT.DEFAULT_MODEL') },
  ...modelOptions.value.map(o => ({ value: o.value, label: o.label })),
]);

// El modelo/proveedor elegidos, o {} si se usa el default.
const llmOverrides = computed(() => {
  const opt = modelOptions.value.find(o => o.value === selectedModelKey.value);
  return opt ? { llm_model: opt.model, llm_provider: opt.provider } : {};
});

async function selectSession(sessionId) {
  if (sessionId === currentSessionId.value) return;
  currentSessionId.value = sessionId;
  await fetchMessages(sessionId);
}

// Conversación nueva: se limpia la vista y se deja el session_id vacío. El backend crea
// uno al enviar el primer mensaje y lo devuelve por el evento `session` del stream.
function newConversation() {
  currentSessionId.value = '';
  messages.value = [];
  activeTools.value = [];
  errorMessage.value = '';
  currentRunId.value = '';
  hermesSessionId.value = '';
  pendingApproval.value = null;
}

async function deleteSession(sessionId) {
  try {
    await provisioningChatAPI.deleteSession(sessionId);
    if (sessionId === currentSessionId.value) newConversation();
    await fetchSessions();
  } catch (e) {
    errorMessage.value = e?.response?.data?.error || e?.message || '';
  }
}

onMounted(async () => {
  await Promise.all([fetchMessages(), fetchSessions(), fetchModelOptions()]);
});

// Autoscroll al final cuando cambian los mensajes o el indicador "pensando".
watch([messages, isSending], async () => {
  await nextTick();
  if (messagesContainer.value) {
    messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight;
  }
});

// --- Acciones -------------------------------------------------------------
// Acumula/actualiza una herramienta del turno (dedup por toolCallId, merge sin perder el
// comando). Espeja el backend y el Chat IA.
function upsertTool(tool) {
  const id = tool.toolCallId || tool.tool;
  const idx = activeTools.value.findIndex(x => x.id === id);
  if (idx === -1) {
    activeTools.value.push({
      id,
      emoji: tool.emoji || '🔧',
      tool: tool.tool || 'tool',
      label: tool.tool || 'tool',
      detail: tool.label || tool.detail || tool.output || '',
      status: tool.status,
    });
    return;
  }
  const prev = activeTools.value[idx];
  activeTools.value[idx] = {
    ...prev,
    status: tool.status || prev.status,
    detail: tool.label || tool.detail || tool.output || prev.detail,
    emoji: tool.emoji || prev.emoji,
  };
}

function appendToMessage(messageId, chunk) {
  const msg = messages.value.find(m => m.id === messageId);
  if (msg) msg.content = (msg.content || '') + chunk;
}

function handleFrame(eventType, data, assistantId) {
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
  // El backend informa en qué sesión quedó el mensaje (clave cuando era conversación nueva).
  if (eventType === 'session') {
    if (json.session_id) currentSessionId.value = json.session_id;
    return;
  }
  // El stream de RUNS no usa la línea `event:` del SSE: el tipo viaja DENTRO del JSON, en
  // `event` (verificado en vivo: message.delta, tool.started, approval.request…). El chat
  // clásico sí usa la línea, así que se aceptan ambos.
  const kind = json.event || eventType;

  // Run iniciado: guarda el run_id, necesario para aprobar, hacer steer o detener.
  if (kind === 'run') {
    if (json.run_id) currentRunId.value = json.run_id;
    if (json.session_id) hermesSessionId.value = json.session_id;
    return;
  }
  // Cualquier evento del run trae su run_id: se aprovecha para tenerlo siempre fresco.
  if (json.run_id && !currentRunId.value) currentRunId.value = json.run_id;

  // El agente pide permiso para ejecutar algo que su escaneo marcó como riesgoso.
  // `choices` es dinámico (p.ej. sin "always" si no admite permiso permanente), así que
  // los botones se renderizan desde ese array y nunca se hardcodean.
  if (kind === 'approval.request') {
    pendingApproval.value = {
      command: json.command || '',
      description: json.description || '',
      choices: Array.isArray(json.choices) ? json.choices : ['once', 'deny'],
      requestId: json.request_id || '',
      runId: json.run_id || currentRunId.value,
    };
    return;
  }
  // El run sigue: se limpia la solicitud (la resolvió este operador u otro).
  if (kind === 'approval.responded') {
    pendingApproval.value = null;
    return;
  }
  if (json.error) {
    appendToMessage(assistantId, `\n\nError: ${json.error}`);
    return;
  }
  // Texto del run (message.delta) o del chat clásico (choices[].delta.content).
  const delta = json.delta || json.choices?.[0]?.delta?.content;
  if (delta && kind !== 'message.interim') appendToMessage(assistantId, delta);
}

function processSseLines(lines, ctx, assistantId) {
  lines.forEach(line => {
    if (line.startsWith('event:')) {
      ctx.eventType = line.slice(6).trim();
    } else if (line.startsWith('data:')) {
      const data = line.slice(5).trim();
      if (data === '[DONE]' || data === '') return;
      handleFrame(ctx.eventType, data, assistantId);
      ctx.eventType = null;
    }
  });
}

async function consumeStream(res, assistantId) {
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  const ctx = { eventType: null };
  let buffer = '';
  let chunk = await reader.read();
  while (!chunk.done) {
    buffer += decoder.decode(chunk.value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();
    processSseLines(lines, ctx, assistantId);
    // eslint-disable-next-line no-await-in-loop
    chunk = await reader.read();
  }
}

// Detiene la respuesta/aprovisionamiento en curso (aborta el stream). El input queda libre.
// Además pide a Hermes que interrumpa el run: abortar solo el stream dejaría al agente
// trabajando del otro lado.
function stopStreaming() {
  if (currentRunId.value) {
    provisioningChatAPI.stopRun(currentRunId.value).catch(() => {});
  }
  streamController.value?.abort();
}

// Responde la aprobación pendiente. Si nadie responde, Hermes la da por denegada a los
// 5 minutos (es un "no" por silencio, deliberado).
async function resolveApproval(choice) {
  const approval = pendingApproval.value;
  if (!approval || isResolvingApproval.value) return;

  isResolvingApproval.value = true;
  try {
    await provisioningChatAPI.approve(
      approval.runId,
      choice,
      approval.requestId
    );
    pendingApproval.value = null;
  } catch (e) {
    errorMessage.value =
      e?.response?.data?.error ||
      e?.message ||
      t('JABVOX_PROVISIONING_CHAT.ERROR.APPROVAL');
  } finally {
    isResolvingApproval.value = false;
  }
}

// Etiqueta del botón de cada opción de aprobación. La clave es dinámica a propósito:
// `choices` lo decide Hermes por solicitud, así que no se puede enumerar aquí. Si llega una
// opción sin traducir, se muestra tal cual en vez de romper.
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const approvalLabel = choice =>
  t(`JABVOX_PROVISIONING_CHAT.APPROVAL.CHOICE.${choice.toUpperCase()}`, choice);

// Añade una nota del sistema al hilo (no es del agente ni del usuario).
function pushSystemNote(text) {
  messages.value.push({
    id: `system_${Date.now()}`,
    role: 'system',
    content: text,
    created_at: new Date().toISOString(),
  });
}

// `/steer <texto>` inyecta guía a un run EN CURSO: no es un mensaje nuevo, va por su propio
// endpoint. Devuelve true si consumió el comando.
async function handleSteerCommand(content) {
  const text = content.replace(/^\/steer\s*/i, '').trim();
  if (!currentRunId.value) {
    pushSystemNote(t('JABVOX_PROVISIONING_CHAT.STEER.NO_RUN'));
    return true;
  }
  if (!text) {
    pushSystemNote(t('JABVOX_PROVISIONING_CHAT.STEER.EMPTY'));
    return true;
  }
  try {
    await provisioningChatAPI.steer(currentRunId.value, text);
    pushSystemNote(t('JABVOX_PROVISIONING_CHAT.STEER.SENT', { text }));
  } catch (e) {
    errorMessage.value = e?.response?.data?.error || e?.message || '';
  }
  return true;
}

// `/model <modelo> [proveedor]` fija el modelo de la sesión de Hermes.
async function handleModelCommand(content) {
  const [model, provider] = content
    .replace(/^\/model\s*/i, '')
    .trim()
    .split(/\s+/);
  if (!model) {
    pushSystemNote(t('JABVOX_PROVISIONING_CHAT.MODEL_CMD.USAGE'));
    return true;
  }
  if (!hermesSessionId.value) {
    pushSystemNote(t('JABVOX_PROVISIONING_CHAT.MODEL_CMD.NO_SESSION'));
    return true;
  }
  try {
    await provisioningChatAPI.setModel(hermesSessionId.value, model, provider);
    pushSystemNote(
      t('JABVOX_PROVISIONING_CHAT.MODEL_CMD.SET', {
        model,
        provider: provider || '—',
      })
    );
  } catch (e) {
    errorMessage.value = e?.response?.data?.error || e?.message || '';
  }
  return true;
}

// Comandos que Jabvox resuelve por su cuenta (endpoints de control de sesión) en vez de
// mandarlos como texto al agente, que no los interpretaría por esa vía.
async function handleLocalCommand(content) {
  if (/^\/steer\b/i.test(content)) return handleSteerCommand(content);
  if (/^\/model\b/i.test(content)) return handleModelCommand(content);
  return false;
}

async function sendMessage() {
  const content = messageInput.value.trim();
  if (!content || isStreaming.value) return;

  errorMessage.value = '';
  if (await handleLocalCommand(content)) {
    messageInput.value = '';
    return;
  }
  // Mensaje del usuario (optimista).
  messages.value.push({
    id: `local_${Date.now()}`,
    role: 'user',
    content,
    created_at: new Date().toISOString(),
  });
  messageInput.value = '';

  // Mensaje del asistente vacío que se irá llenando con el stream.
  const assistantId = `assistant_${Date.now()}`;
  messages.value.push({
    id: assistantId,
    role: 'assistant',
    content: '',
    created_at: new Date().toISOString(),
  });

  isSending.value = true;
  isStreaming.value = true;
  streamController.value = new AbortController();
  activeTools.value = [];

  try {
    const res = await fetch(provisioningChatAPI.streamUrl(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...deviseAuthHeaders() },
      credentials: 'same-origin',
      signal: streamController.value?.signal,
      body: JSON.stringify({
        content,
        session_id: currentSessionId.value || undefined,
        ...llmOverrides.value,
      }),
    });
    if (!res.ok || !res.body) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || t('JABVOX_PROVISIONING_CHAT.ERROR.SEND'));
    }
    await consumeStream(res, assistantId);
  } catch (e) {
    if (e.name === 'AbortError') {
      appendToMessage(
        assistantId,
        `\n\n_${t('JABVOX_PROVISIONING_CHAT.STOPPED')}_`
      );
    } else {
      errorMessage.value =
        e?.message || t('JABVOX_PROVISIONING_CHAT.ERROR.SEND');
      appendToMessage(assistantId, `\n\nError: ${e.message}`);
    }
  } finally {
    // Fija las herramientas usadas al mensaje (quedan expandibles), como el Chat IA.
    const msg = messages.value.find(m => m.id === assistantId);
    if (msg && activeTools.value.length) {
      msg.metadata = { ...(msg.metadata || {}), tools: [...activeTools.value] };
    }
    isSending.value = false;
    isStreaming.value = false;
    streamController.value = null;
    activeTools.value = [];
    fetchSessions(); // refresca la lista (conversación nueva o fecha del último mensaje)
  }
}

function toggleToolDetail(msgId, toolId) {
  const key = `${msgId}:${toolId}`;
  expandedTool.value = expandedTool.value === key ? null : key;
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
  <div class="flex h-full w-full overflow-hidden bg-n-background">
    <!-- Conversaciones -->
    <aside
      class="hidden md:flex flex-col w-64 border-r border-n-weak bg-n-solid-1 flex-shrink-0"
    >
      <div class="p-3 border-b border-n-weak">
        <button
          class="reset-base w-full flex items-center justify-center gap-2 rounded-xl border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1 transition-colors"
          @click="newConversation"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('JABVOX_PROVISIONING_CHAT.NEW_CONVERSATION') }}
        </button>
      </div>
      <div class="flex-1 overflow-y-auto p-2 space-y-1 min-h-0">
        <p
          v-if="!sessions.length"
          class="text-xs text-n-slate-10 text-center py-4"
        >
          {{ t('JABVOX_PROVISIONING_CHAT.NO_CONVERSATIONS') }}
        </p>
        <div
          v-for="s in sessions"
          :key="s.session_id"
          class="group flex items-center gap-1 rounded-lg px-2 py-2 cursor-pointer transition-colors"
          :class="
            s.session_id === currentSessionId
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'hover:bg-n-alpha-1 text-n-slate-11'
          "
          @click="selectSession(s.session_id)"
        >
          <span class="i-lucide-message-square size-4 shrink-0 opacity-70" />
          <span class="flex-1 min-w-0 text-xs truncate">
            {{ formatSessionDate(s.last_at) }}
            <span class="opacity-60">{{ `· ${s.messages_count}` }}</span>
          </span>
          <button
            class="reset-base i-lucide-trash-2 size-3.5 shrink-0 opacity-0 group-hover:opacity-60 hover:!opacity-100"
            :title="t('JABVOX_PROVISIONING_CHAT.DELETE_CONVERSATION')"
            @click.stop="deleteSession(s.session_id)"
          />
        </div>
      </div>
    </aside>

    <div class="flex flex-col flex-1 overflow-hidden min-w-0">
      <!-- Encabezado -->
      <div
        class="border-b border-n-weak bg-n-solid-1 px-4 sm:px-6 py-3 flex items-center gap-3 flex-shrink-0"
      >
        <div
          class="hidden sm:flex items-center justify-center size-10 rounded-xl bg-n-alpha-2 text-n-brand shrink-0"
        >
          <span class="i-lucide-server-cog size-5" />
        </div>
        <div class="min-w-0 flex-1">
          <h1
            class="text-base sm:text-lg font-semibold text-n-slate-12 truncate"
          >
            {{ t('JABVOX_PROVISIONING_CHAT.TITLE') }}
          </h1>
          <p class="text-xs text-n-slate-10 truncate">
            {{ t('JABVOX_PROVISIONING_CHAT.SUBTITLE') }}
          </p>
        </div>
        <!-- Picker de modelo: vacío = el default del aprovisionador -->
        <select
          v-if="modelOptions.length"
          v-model="selectedModelKey"
          class="reset-base text-xs rounded-lg border border-n-weak bg-n-background text-n-slate-11 px-2 py-1.5 max-w-[11rem] shrink-0"
          :disabled="isStreaming"
        >
          <option
            v-for="o in modelSelectOptions"
            :key="o.value"
            :value="o.value"
          >
            {{ o.label }}
          </option>
        </select>
        <button
          class="reset-base md:hidden flex items-center justify-center size-9 rounded-lg border border-n-weak text-n-slate-11 shrink-0"
          :title="t('JABVOX_PROVISIONING_CHAT.NEW_CONVERSATION')"
          @click="newConversation"
        >
          <span class="i-lucide-plus size-4" />
        </button>
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
          <span class="text-sm">{{
            t('JABVOX_PROVISIONING_CHAT.LOADING')
          }}</span>
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

            <!-- Estado del turno: al volver al chat se ve si sigue en curso, si quedó
                 esperando autorización o si se interrumpió. -->
            <div
              v-if="turnBadge(msg)"
              class="mt-2 inline-flex items-center gap-1.5 text-xs rounded-full px-2 py-0.5"
              :class="turnBadge(msg).class"
            >
              <span :class="turnBadge(msg).icon" class="size-3" />
              {{ turnBadge(msg).label }}
            </div>

            <!-- Herramientas usadas (persistidas), expandibles como en el Chat IA -->
            <div
              v-if="msg.role === 'assistant' && msg.metadata?.tools?.length"
              class="mt-2 flex flex-col gap-1"
            >
              <p class="text-xs font-medium opacity-70">
                {{ t('JABVOX_PROVISIONING_CHAT.TOOLS_USED') }}
              </p>
              <div v-for="tool in msg.metadata.tools" :key="tool.id">
                <button
                  type="button"
                  class="reset-base flex items-center gap-1.5 text-xs rounded-md bg-n-alpha-1 px-2 py-1 hover:bg-n-alpha-2 transition-colors"
                  @click="toggleToolDetail(msg.id, tool.id)"
                >
                  <span>{{ tool.emoji }}</span>
                  <span class="font-mono">{{ tool.tool }}</span>
                  <span
                    v-if="tool.status === 'completed'"
                    class="i-lucide-check text-n-teal-11 size-3"
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

        <!-- Chips de herramientas EN VIVO mientras el aprovisionador trabaja -->
        <div
          v-if="isStreaming && activeTools.length"
          class="flex flex-wrap gap-1.5 px-1"
        >
          <span
            v-for="tool in activeTools"
            :key="tool.id"
            class="inline-flex items-center gap-1.5 text-xs rounded-full bg-n-alpha-1 border border-n-weak px-2.5 py-1"
          >
            <span>{{ tool.emoji }}</span>
            <span class="font-mono">{{ tool.label }}</span>
            <span
              v-if="tool.status === 'completed'"
              class="i-lucide-check text-n-teal-11 size-3"
            />
            <span
              v-else
              class="i-lucide-loader-2 animate-spin text-n-slate-10 size-3"
            />
          </span>
        </div>

        <!-- Indicador "pensando" (solo antes de recibir el primer texto/tool) -->
        <div v-if="isStreaming && !activeTools.length" class="flex gap-3">
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

      <!-- Solicitud de aprobación: el agente se detuvo y espera permiso del operador.
           Si nadie responde, Hermes lo toma como denegado a los 5 minutos. -->
      <div
        v-if="pendingApproval"
        class="border-t border-n-amber-6 bg-n-amber-2 px-4 sm:px-6 py-4 flex-shrink-0"
      >
        <div class="max-w-5xl mx-auto w-full flex flex-col gap-3">
          <div class="flex items-start gap-2">
            <span
              class="i-lucide-shield-alert size-5 shrink-0 mt-0.5 text-n-amber-11"
            />
            <div class="min-w-0 flex-1">
              <p class="text-sm font-semibold text-n-slate-12">
                {{ t('JABVOX_PROVISIONING_CHAT.APPROVAL.TITLE') }}
              </p>
              <pre
                v-if="pendingApproval.command"
                class="mt-2 text-xs bg-n-solid-1 border border-n-weak rounded-lg p-2.5 overflow-x-auto text-n-slate-12 whitespace-pre-wrap break-all"
                >{{ pendingApproval.command }}</pre
              >
              <p
                v-if="pendingApproval.description"
                class="mt-2 text-xs text-n-slate-11 break-words"
              >
                {{ pendingApproval.description }}
              </p>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="choice in pendingApproval.choices"
              :key="choice"
              class="reset-base text-xs font-medium rounded-lg px-3 py-2 border transition-colors disabled:opacity-50"
              :class="
                choice === 'deny'
                  ? 'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4'
                  : 'border-n-weak bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-1'
              "
              :disabled="isResolvingApproval"
              @click="resolveApproval(choice)"
            >
              {{ approvalLabel(choice) }}
            </button>
          </div>
          <p class="text-xs text-n-slate-10">
            {{ t('JABVOX_PROVISIONING_CHAT.APPROVAL.TIMEOUT_HINT') }}
          </p>
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
            v-if="isStreaming"
            icon="i-lucide-square"
            color="ruby"
            :label="t('JABVOX_PROVISIONING_CHAT.STOP')"
            class="shrink-0 sm:w-auto justify-center"
            @click="stopStreaming"
          />
          <Button
            v-else
            icon="i-lucide-send"
            :label="t('JABVOX_PROVISIONING_CHAT.SEND')"
            :disabled="!canSend"
            class="shrink-0 sm:w-auto justify-center"
            @click="sendMessage"
          />
        </div>
      </div>
    </div>
  </div>
</template>
