<script setup>
import {
  ref,
  computed,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

/**
 * Búsqueda DENTRO del hilo de la conversación abierta (estilo WhatsApp):
 * escribe un término → cuenta coincidencias, navega entre ellas (↑/↓ o Enter),
 * hace scroll a cada mensaje coincidente y lo resalta temporalmente.
 *
 * No reescribe el contenido de cada burbuja (seguro para todos los tipos de
 * mensaje): resalta el CONTENEDOR del mensaje (#message<id>) por un instante.
 */
const props = defineProps({
  // Lista de mensajes cargados del chat actual (sin transformar).
  messages: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

const isOpen = ref(false);
const term = ref('');
const activeIndex = ref(0);
const inputRef = ref(null);

// Texto buscable de un mensaje: su contenido de texto. Se ignoran mensajes sin
// texto (adjuntos puros, actividades) para la búsqueda por palabra.
const searchableText = message => (message?.content || '').toString();

// IDs de los mensajes que coinciden con el término, en el orden del hilo.
const matches = computed(() => {
  const query = term.value.trim().toLowerCase();
  if (!query) return [];
  return props.messages
    .filter(m => searchableText(m).toLowerCase().includes(query))
    .map(m => m.id);
});

const total = computed(() => matches.value.length);
const hasMatches = computed(() => total.value > 0);

// Etiqueta "actual/total" (1/5). 0/0 cuando no hay término o no hay coincidencias.
const counterLabel = computed(() => {
  if (!term.value.trim()) return '';
  if (!hasMatches.value) return t('CONVERSATION.SEARCH_IN_CHAT.NO_RESULTS');
  return `${activeIndex.value + 1}/${total.value}`;
});

const HIGHLIGHT_CLASS = 'jabvox-chat-search-hit';

const clearHighlights = () => {
  document
    .querySelectorAll('.' + HIGHLIGHT_CLASS)
    .forEach(el => el.classList.remove(HIGHLIGHT_CLASS));
};

// Lleva el foco visual a la coincidencia activa: scroll + resaltado del contenedor.
const focusMatch = () => {
  if (!hasMatches.value) return;
  const messageId = matches.value[activeIndex.value];
  clearHighlights();
  nextTick(() => {
    const el = document.getElementById('message' + messageId);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      el.classList.add(HIGHLIGHT_CLASS);
    } else {
      // El mensaje no está en el DOM (fuera del rango cargado): pedir scroll
      // por el bus, que además dispara la carga de mensajes previos.
      emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
    }
  });
};

const next = () => {
  if (!hasMatches.value) return;
  activeIndex.value = (activeIndex.value + 1) % total.value;
  focusMatch();
};

const prev = () => {
  if (!hasMatches.value) return;
  activeIndex.value = (activeIndex.value - 1 + total.value) % total.value;
  focusMatch();
};

// Al cambiar el término, reiniciar al primer resultado y enfocarlo.
watch(term, () => {
  activeIndex.value = 0;
  if (hasMatches.value) focusMatch();
  else clearHighlights();
});

const close = () => {
  isOpen.value = false;
  term.value = '';
  activeIndex.value = 0;
  clearHighlights();
};

const open = () => {
  isOpen.value = true;
  nextTick(() => inputRef.value?.focus());
};

const toggle = () => {
  if (isOpen.value) close();
  else open();
};

const onKeydown = e => {
  if (e.key === 'Escape') {
    close();
  } else if (e.key === 'Enter') {
    e.preventDefault();
    if (e.shiftKey) prev();
    else next();
  }
};

onMounted(() => {
  emitter.on(BUS_EVENTS.TOGGLE_CONVERSATION_SEARCH, toggle);
});

onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.TOGGLE_CONVERSATION_SEARCH, toggle);
  clearHighlights();
});
</script>

<template>
  <div
    v-show="isOpen"
    class="flex items-center gap-2 px-3 py-2 mx-2 mt-2 rounded-lg border border-n-weak bg-n-solid-1 shadow-sm"
  >
    <span class="i-lucide-search size-4 text-n-slate-10 shrink-0" />
    <input
      ref="inputRef"
      v-model="term"
      type="text"
      class="flex-grow min-w-0 bg-transparent border-0 outline-none text-sm text-n-slate-12 placeholder:text-n-slate-10"
      :placeholder="t('CONVERSATION.SEARCH_IN_CHAT.PLACEHOLDER')"
      @keydown="onKeydown"
    />
    <span
      v-if="counterLabel"
      class="text-xs text-n-slate-11 tabular-nums shrink-0"
    >
      {{ counterLabel }}
    </span>
    <button
      type="button"
      class="p-1 rounded hover:bg-n-alpha-2 disabled:opacity-40"
      :disabled="!hasMatches"
      :title="t('CONVERSATION.SEARCH_IN_CHAT.PREVIOUS')"
      @click="prev"
    >
      <span class="i-lucide-chevron-up size-4 text-n-slate-11" />
    </button>
    <button
      type="button"
      class="p-1 rounded hover:bg-n-alpha-2 disabled:opacity-40"
      :disabled="!hasMatches"
      :title="t('CONVERSATION.SEARCH_IN_CHAT.NEXT')"
      @click="next"
    >
      <span class="i-lucide-chevron-down size-4 text-n-slate-11" />
    </button>
    <button
      type="button"
      class="p-1 rounded hover:bg-n-alpha-2"
      :title="t('CONVERSATION.SEARCH_IN_CHAT.CLOSE')"
      @click="close"
    >
      <span class="i-lucide-x size-4 text-n-slate-11" />
    </button>
  </div>
</template>

<style>
/* Resaltado temporal del mensaje coincidente al navegar la búsqueda. */
.jabvox-chat-search-hit > div,
.jabvox-chat-search-hit {
  animation: jabvox-chat-search-pulse 1.8s ease-out;
  border-radius: 0.5rem;
}
@keyframes jabvox-chat-search-pulse {
  0%,
  40% {
    box-shadow: 0 0 0 3px rgba(64, 181, 180, 0.55);
    background-color: rgba(64, 181, 180, 0.12);
  }
  100% {
    box-shadow: 0 0 0 0 rgba(64, 181, 180, 0);
    background-color: transparent;
  }
}
</style>
