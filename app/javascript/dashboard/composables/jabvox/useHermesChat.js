import { ref } from 'vue';
import { useStore } from 'vuex';
import { aiChatAPI } from 'dashboard/api/jabvox/aiChat';
import { deviseAuthHeaders } from 'dashboard/helper/deviseAuthHeaders';

// Lógica de conversación con el agente Hermes de la cuenta (streaming SSE + chips de
// herramientas). Vive en un composable porque la usan dos superficies distintas: la página
// completa de Chat IA y la burbuja flotante del dashboard. Ambas hablan con el MISMO Hermes.

export { deviseAuthHeaders };

export function useHermesChat({ errorLabel = 'Error' } = {}) {
  const store = useStore();

  const isStreaming = ref(false);
  // Permite ABORTAR el streaming en curso (botón Detener) para no bloquear al usuario.
  const streamController = ref(null);
  const activeTools = ref([]); // chips de herramientas en vivo (Telegram-like)

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

  // Detiene la respuesta en curso (aborta el stream). El input queda libre de inmediato.
  function stopStreaming() {
    streamController.value?.abort();
  }

  // Envía el mensaje al agente Hermes en STREAMING (SSE): pinta el texto que fluye y los chips
  // de herramientas en vivo. Al terminar, refresca la sesión.
  async function streamAssistant({
    content,
    apiSessionId,
    displaySessionId,
    isNewChat,
    attachments = [],
    connectionId = null,
    modelOverride = {},
  }) {
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
          connection_id: connectionId,
          attachments,
          // Modelo/proveedor elegidos en el picker (vacío = default del agente en Hermes).
          ...modelOverride,
        }),
      });
      if (!res.ok || !res.body) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.error || errorLabel);
      }
      await consumeStream(res, displaySessionId, assistantId);
      if (isNewChat) await store.dispatch('jabvoxAiChat/fetchSessions');
    } catch (e) {
      // Si el usuario detuvo el stream (AbortController), no es un error: marca el corte.
      if (e.name === 'AbortError') {
        appendToMessage(displaySessionId, assistantId, '\n\n_(detenido)_');
      } else {
        appendToMessage(
          displaySessionId,
          assistantId,
          `\n\nError: ${e.message}`
        );
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

  return {
    isStreaming,
    activeTools,
    streamAssistant,
    stopStreaming,
    appendToMessage,
  };
}
