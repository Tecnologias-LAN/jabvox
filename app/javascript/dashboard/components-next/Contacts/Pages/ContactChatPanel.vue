<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MessagesView from 'dashboard/components/widgets/conversation/MessagesView.vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

// Chat del contacto dentro de su ficha: selector de bandeja arriba y, debajo, la
// conversación elegida con su caja de respuesta completa (plantillas, adjuntos, audio y el
// asistente de IA).
//
// Reutiliza MessagesView y ReplyBox de conversaciones en vez de reescribirlos: ambos leen la
// conversación activa del store (`getSelectedChat`), así que basta con activarla aquí. Eso
// hereda gratis todo lo que ya funciona en la bandeja, incluido el botón de la estrella.
const props = defineProps({
  conversations: { type: Array, default: () => [] },
});

const store = useStore();
const { t } = useI18n();

// Abre/cierra la barra de búsqueda dentro del hilo (la barra vive en MessagesView).
const toggleConversationSearch = () => {
  emitter.emit(BUS_EVENTS.TOGGLE_CONVERSATION_SEARCH);
};

const selectedId = ref(null);
const isLoadingChat = ref(false);

const currentChat = useMapGetter('getSelectedChat');
const chatList = useMapGetter('getAllConversations');

// Una pestaña por conversación, etiquetada con su bandeja: el contacto puede haber escrito
// por WhatsApp y por Facebook y cada canal es una conversación distinta.
const tabs = computed(() =>
  props.conversations.map(conv => ({
    id: conv.display_id,
    label: conv.inbox?.name || t('JABVOX_CONTACTS.DETAIL.CHAT.NO_INBOX'),
    channel: conv.inbox?.channel_type,
    status: conv.status,
    unread: conv.unread_count || 0,
  }))
);

// Icono por canal, para reconocer la bandeja de un vistazo.
const CHANNEL_ICONS = {
  'Channel::Whatsapp': 'i-ri-whatsapp-fill',
  'Channel::FacebookPage': 'i-ri-messenger-fill',
  'Channel::WebWidget': 'i-ri-global-fill',
  'Channel::Email': 'i-ri-mail-fill',
  'Channel::Sms': 'i-ri-message-2-fill',
  'Channel::TwilioSms': 'i-ri-message-2-fill',
  'Channel::Telegram': 'i-ri-telegram-fill',
  'Channel::Instagram': 'i-ri-instagram-fill',
};
const channelIcon = channel => CHANNEL_ICONS[channel] || 'i-ri-chat-1-fill';

// La conversación normalizada del store, que es la que `setActiveChat` espera recibir.
function findInStore(displayId) {
  const id = Number(displayId);
  return (chatList.value || []).find(c => c.id === id);
}

// Activa la conversación en el store: es lo que hace que MessagesView y ReplyBox la muestren.
//
// `getConversation` no devuelve la conversación: la mete en el store (`chatList`) ya
// normalizada, con su array `messages`. Hay que leerla de ahí y no del valor de retorno —
// `setActiveChat` accede a `data.messages[0].id` y, si el objeto no trae `messages`, lanza un
// TypeError que su propio catch se traga: el chat nunca marca `dataFetched` y el spinner de
// MessagesView se queda girando para siempre.
async function selectConversation(displayId) {
  if (!displayId || selectedId.value === displayId) return;

  selectedId.value = displayId;
  isLoadingChat.value = true;
  try {
    await store.dispatch('getConversation', displayId);
    const data = findInStore(displayId);
    if (!data) throw new Error('conversation-not-in-store');
    await store.dispatch('setActiveChat', { data });
  } catch {
    // Si falla la carga se muestra el estado vacío en vez de romper la ficha.
    selectedId.value = null;
  } finally {
    isLoadingChat.value = false;
  }
}

// Al abrir la ficha se selecciona la conversación más reciente.
watch(
  () => props.conversations,
  convs => {
    if (convs.length && !selectedId.value)
      selectConversation(convs[0].display_id);
  },
  { immediate: true }
);

onMounted(() => {
  if (props.conversations.length) {
    selectConversation(props.conversations[0].display_id);
  }
});

// Sin esto la bandeja se abriría en la conversación que quedó activa aquí.
onBeforeUnmount(() => {
  store.dispatch('clearSelectedState');
});
</script>

<template>
  <div class="flex flex-col h-full min-h-0 bg-n-background">
    <!-- Bandejas del contacto -->
    <div
      v-if="tabs.length > 1"
      class="flex items-center gap-1 px-3 py-2 border-b border-n-weak bg-n-solid-1 overflow-x-auto flex-shrink-0"
    >
      <button
        v-for="tab in tabs"
        :key="tab.id"
        class="reset-base flex items-center gap-1.5 text-xs rounded-lg px-2.5 py-1.5 whitespace-nowrap transition-colors"
        :class="
          selectedId === tab.id
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2'
        "
        @click="selectConversation(tab.id)"
      >
        <span :class="channelIcon(tab.channel)" class="size-3.5" />
        {{ tab.label }}
        <span
          v-if="tab.unread"
          class="rounded-full bg-n-ruby-9 text-white text-[10px] px-1.5 tabular-nums"
        >
          {{ tab.unread }}
        </span>
      </button>
      <button
        v-if="currentChat?.id"
        type="button"
        class="ml-auto shrink-0 flex items-center justify-center size-7 rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
        :title="t('CONVERSATION.SEARCH_IN_CHAT.BUTTON')"
        @click="toggleConversationSearch"
      >
        <span class="i-lucide-search size-4" />
      </button>
    </div>

    <!-- Una sola bandeja: se indica cuál sin ocupar una fila de pestañas -->
    <div
      v-else-if="tabs.length === 1"
      class="flex items-center gap-1.5 px-3 py-2 border-b border-n-weak bg-n-solid-1 text-xs text-n-slate-11 flex-shrink-0"
    >
      <span :class="channelIcon(tabs[0].channel)" class="size-3.5" />
      {{ tabs[0].label }}
      <span class="text-n-slate-10">{{ `· ${tabs[0].status}` }}</span>
      <button
        v-if="currentChat?.id"
        type="button"
        class="ml-auto shrink-0 flex items-center justify-center size-7 rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
        :title="t('CONVERSATION.SEARCH_IN_CHAT.BUTTON')"
        @click="toggleConversationSearch"
      >
        <span class="i-lucide-search size-4" />
      </button>
    </div>

    <!-- Conversación -->
    <div v-if="isLoadingChat" class="flex-1 flex items-center justify-center">
      <Spinner />
    </div>

    <div
      v-else-if="!tabs.length"
      class="flex-1 flex flex-col items-center justify-center gap-3 px-6 text-center"
    >
      <span class="i-lucide-message-circle-off size-8 text-n-slate-9" />
      <p class="text-sm text-n-slate-11">
        {{ t('JABVOX_CONTACTS.DETAIL.CHAT.EMPTY') }}
      </p>
      <p class="text-xs text-n-slate-10 max-w-xs">
        {{ t('JABVOX_CONTACTS.DETAIL.CHAT.EMPTY_HINT') }}
      </p>
    </div>

    <!-- MessagesView trae la lista de mensajes Y la caja de respuesta completa: plantillas,
         adjuntos, audio y el asistente de IA. -->
    <MessagesView
      v-else-if="currentChat?.id"
      :key="selectedId"
      class="flex-1 min-h-0"
    />
  </div>
</template>
