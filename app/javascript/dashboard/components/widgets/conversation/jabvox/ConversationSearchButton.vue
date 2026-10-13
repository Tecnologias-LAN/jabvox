<script setup>
// Barra de búsqueda de mensajes DENTRO de la conversación abierta: botón lupa en el header
// que despliega un input + dropdown de resultados. Busca texto, transcripción de audio y
// nombre de adjuntos (backend: /search/conversation_messages, acotado y aislado por cuenta).
// Al elegir un resultado, navega a la conversación con ?messageId=<id>, reutilizando el flujo
// probado de la búsqueda global (ConversationView carga el hilo alrededor del mensaje y hace
// scroll + resaltado vía BUS_EVENTS.SCROLL_TO_MESSAGE).
import { ref, computed, nextTick, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { onClickOutside } from '@vueuse/core';
import { frontendURL } from 'dashboard/helper/URLHelper';
import SearchAPI from 'dashboard/api/search';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  // Pasa conversationId (buscar en ESA conversación) O contactId (todas las conversaciones
  // del contacto). Exactamente uno.
  conversationId: { type: [Number, String], default: null },
  contactId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();

const isOpen = ref(false);
const query = ref('');
const results = ref([]);
const isLoading = ref(false);
const rootRef = ref(null);
const inputRef = ref(null);
let debounceTimer = null;

const hasQuery = computed(() => query.value.trim().length >= 2);

const toggle = async () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    await nextTick();
    inputRef.value?.focus();
  }
};

const close = () => {
  isOpen.value = false;
};

onClickOutside(rootRef, close);

const runSearch = async () => {
  if (!hasQuery.value) {
    results.value = [];
    return;
  }
  isLoading.value = true;
  try {
    const { data } = await SearchAPI.conversationMessages({
      q: query.value.trim(),
      conversationId: props.conversationId,
      contactId: props.contactId,
    });
    results.value = data.messages || [];
  } catch (error) {
    results.value = [];
  } finally {
    isLoading.value = false;
  }
};

const onInput = () => {
  clearTimeout(debounceTimer);
  // Debounce: no dispara una petición por cada tecla (rápido y sin martillar al backend).
  debounceTimer = setTimeout(runSearch, 300);
};

const goToMessage = result => {
  const accountId = store.getters.getCurrentAccountId;
  const displayId = result.conversation_display_id;
  if (!displayId) return;
  // Navega a la conversación con messageId: ConversationView carga el hilo alrededor del
  // mensaje y dispara el scroll + resaltado (mismo flujo que la búsqueda global).
  router.push(
    frontendURL(`accounts/${accountId}/conversations/${displayId}`, {
      messageId: result.id,
    })
  );
  close();
};

const formatDate = unixSeconds => {
  if (!unixSeconds) return '';
  return new Date(unixSeconds * 1000).toLocaleDateString();
};

onBeforeUnmount(() => clearTimeout(debounceTimer));
</script>

<template>
  <div ref="rootRef" class="relative">
    <NextButton
      v-tooltip.bottom="t('CONVERSATION.SEARCH_MESSAGES.TOOLTIP')"
      icon="i-lucide-search"
      color="slate"
      variant="ghost"
      size="sm"
      @click="toggle"
    />
    <div
      v-if="isOpen"
      class="absolute ltr:right-0 rtl:left-0 top-full mt-1 z-50 w-80 bg-n-background rounded-lg shadow-lg border border-n-weak"
    >
      <div class="p-2 border-b border-n-weak">
        <input
          ref="inputRef"
          v-model="query"
          type="text"
          class="reset-base w-full px-2 py-1.5 text-sm bg-n-alpha-1 rounded-md text-n-slate-12 placeholder:text-n-slate-10"
          :placeholder="t('CONVERSATION.SEARCH_MESSAGES.PLACEHOLDER')"
          @input="onInput"
          @keyup.esc="close"
        />
      </div>

      <div class="max-h-80 overflow-y-auto">
        <div v-if="isLoading" class="p-3 text-xs text-n-slate-11 text-center">
          {{ t('CONVERSATION.SEARCH_MESSAGES.SEARCHING') }}
        </div>
        <div
          v-else-if="hasQuery && !results.length"
          class="p-3 text-xs text-n-slate-11 text-center"
        >
          {{ t('CONVERSATION.SEARCH_MESSAGES.NO_RESULTS') }}
        </div>
        <button
          v-for="result in results"
          :key="result.id"
          class="reset-base w-full text-left px-3 py-2 border-b border-n-weak last:border-b-0 hover:bg-n-alpha-1 cursor-pointer"
          @click="goToMessage(result)"
        >
          <p class="text-xs text-n-slate-12 line-clamp-2">
            {{ result.snippet }}
          </p>
          <p class="text-[11px] text-n-slate-10 mt-0.5">
            <span v-if="result.sender_name" class="ltr:mr-1 rtl:ml-1">{{
              result.sender_name
            }}</span>
            <span>{{ formatDate(result.created_at) }}</span>
          </p>
        </button>
      </div>
    </div>
  </div>
</template>
