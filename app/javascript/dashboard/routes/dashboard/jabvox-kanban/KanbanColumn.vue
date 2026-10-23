<script setup>
import { ref, computed, watch } from 'vue';
import { useStore } from 'vuex';
import KanbanCard from './KanbanCard.vue';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
  funnelId: {
    type: Number,
    default: null,
  },
  conversations: {
    type: Array,
    default: () => [],
  },
  leadCards: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['card-click', 'drop']);
const store = useStore();

const isDragOver = ref(false);
const showAll = ref(false);
const pageSize = ref(10);
const pageSizeOptions = [5, 10, 25, 50];

// Orden de las tarjetas de ESTA columna. Se inicializa del valor guardado en el
// stage (card_sort_jabvox) y al cambiarlo se persiste en BD por columna.
const cardSort = ref(props.stage.card_sort_jabvox || 'manual');
watch(
  () => props.stage.card_sort_jabvox,
  value => {
    cardSort.value = value || 'manual';
  }
);

const onSortChange = () => {
  store.dispatch('jabvoxKanban/updateStage', {
    funnelId: props.funnelId,
    stageId: props.stage.id,
    card_sort_jabvox: cardSort.value,
  });
};

watch(
  () => pageSize.value,
  () => {
    showAll.value = false;
  }
);

// Número (#display_id) de una tarjeta; las que no tienen (lead cards) van al final.
const cardNumber = card =>
  card.type === 'lead' ? null : (card.display_id ?? card.id);

// Las tarjetas ya vienen ordenadas del backend según card_sort. Aquí solo se
// aplica el orden en cliente para que el cambio del selector se vea al instante,
// sin esperar a recargar el tablero.
const sortedCards = computed(() => {
  const list = [
    ...props.conversations.map(c => ({ ...c, type: 'conversation' })),
    ...props.leadCards,
  ];
  if (cardSort.value === 'manual') return list;
  const dir = cardSort.value === 'number_desc' ? -1 : 1;
  return [...list].sort((a, b) => {
    const na = cardNumber(a);
    const nb = cardNumber(b);
    if (na == null && nb == null) return 0;
    if (na == null) return 1; // sin número al final
    if (nb == null) return -1;
    return dir * (na - nb);
  });
});

const allCards = sortedCards;

const cardCount = computed(() => allCards.value.length);
const visibleCards = computed(() =>
  showAll.value ? allCards.value : allCards.value.slice(0, pageSize.value)
);
const hiddenCount = computed(() =>
  Math.max(0, allCards.value.length - pageSize.value)
);

const cardsContainer = ref(null);
// Índice donde caería la tarjeta ahora mismo (para dibujar la línea indicadora). null = no
// se está arrastrando sobre esta columna.
const dropIndex = ref(null);

// Índice de destino dentro de la columna según la posición Y del cursor: cuenta
// cuántas tarjetas quedan por ENCIMA del punto donde se soltó (su punto medio).
// Así soltar entre dos tarjetas inserta en medio, no siempre al final.
const dropIndexFromEvent = event => {
  const container = cardsContainer.value;
  if (!container) return null;
  const cards = [...container.querySelectorAll('[data-card-index]')];
  let index = cards.length;
  for (let i = 0; i < cards.length; i += 1) {
    const rect = cards[i].getBoundingClientRect();
    if (event.clientY < rect.top + rect.height / 2) {
      index = i;
      break;
    }
  }
  return index;
};

const onDragOver = event => {
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
  isDragOver.value = true;
  dropIndex.value = dropIndexFromEvent(event);
};

const onDragLeave = () => {
  isDragOver.value = false;
  dropIndex.value = null;
};

const onDrop = event => {
  event.preventDefault();
  isDragOver.value = false;
  dropIndex.value = null;
  const raw = event.dataTransfer.getData('text/plain');
  // Si el usuario arrastra una tarjeta a una posición concreta, manda el arrastre: la
  // columna pasa a orden Manual (si estaba en N° asc/desc) y respeta dónde se soltó. Así
  // mover una ficha nunca queda bloqueado por tener un filtro de orden activo.
  if (cardSort.value !== 'manual') {
    cardSort.value = 'manual';
    onSortChange();
  }
  const position = dropIndexFromEvent(event);
  if (raw.startsWith('lead_')) {
    const leadId = parseInt(raw.replace('lead_', ''), 10);
    if (leadId) emit('drop', { leadId, stageId: props.stage.id, position });
  } else {
    const conversationId = parseInt(raw, 10);
    if (conversationId) {
      emit('drop', { conversationId, stageId: props.stage.id, position });
    }
  }
};
</script>

<template>
  <div
    class="flex flex-col min-w-[280px] w-[280px] sm:w-[300px] lg:w-[324px] flex-shrink-0 bg-n-solid-1 rounded-2xl border border-n-weak h-full shadow-sm overflow-hidden transition-all duration-200"
    :class="isDragOver ? 'ring-2 ring-inset ring-n-brand/40' : ''"
  >
    <!-- Stage accent bar -->
    <div
      class="h-1 w-full shrink-0"
      :style="{ backgroundColor: stage.color_jabvox }"
    />

    <div
      class="flex items-center justify-between px-3 py-2.5 border-b border-n-weak"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="size-2.5 rounded-full shrink-0 ring-2 ring-inset ring-white/40"
          :style="{ backgroundColor: stage.color_jabvox }"
        />
        <h3 class="text-sm font-semibold text-n-slate-12 truncate">
          {{ stage.name_jabvox }}
        </h3>
        <span
          class="text-xs font-semibold text-n-slate-11 bg-n-alpha-2 rounded-full px-2 py-0.5 shrink-0 tabular-nums"
        >
          {{ cardCount }}
        </span>
      </div>
      <div class="flex items-center gap-1.5">
        <!-- Orden de las tarjetas de esta columna (persiste por columna en BD). -->
        <select
          v-model="cardSort"
          class="reset-base text-xs border border-n-weak rounded-md pl-2 pr-6 h-8 bg-n-background text-n-slate-11 cursor-pointer focus:outline-none focus:border-n-slate-7"
          :aria-label="$t('JABVOX_KANBAN.SORT.LABEL')"
          @change="onSortChange"
        >
          <option value="manual">{{ $t('JABVOX_KANBAN.SORT.MANUAL') }}</option>
          <option value="number_asc">
            {{ $t('JABVOX_KANBAN.SORT.NUMBER_ASC') }}
          </option>
          <option value="number_desc">
            {{ $t('JABVOX_KANBAN.SORT.NUMBER_DESC') }}
          </option>
        </select>
        <!-- Cuántas tarjetas ver por columna. -->
        <select
          v-model="pageSize"
          class="reset-base text-xs border border-n-weak rounded-md pl-2 pr-6 h-8 bg-n-background text-n-slate-11 cursor-pointer focus:outline-none focus:border-n-slate-7"
          :aria-label="$t('JABVOX_KANBAN.PER_PAGE')"
        >
          <option v-for="size in pageSizeOptions" :key="size" :value="size">
            {{ size }}
          </option>
        </select>
      </div>
    </div>

    <div
      ref="cardsContainer"
      class="flex-1 overflow-y-auto p-2 space-y-2 transition-colors"
      :class="isDragOver ? 'bg-n-alpha-1' : ''"
      @dragover="onDragOver"
      @dragleave="onDragLeave"
      @drop="onDrop"
    >
      <template
        v-for="(card, idx) in visibleCards"
        :key="card.type === 'lead' ? `lead_${card.lead_id}` : card.id"
      >
        <!-- Línea que marca dónde quedaría la tarjeta al soltar. -->
        <div
          v-if="dropIndex === idx"
          class="h-0.5 -my-1 rounded-full bg-n-brand shadow-[0_0_0_1px] shadow-n-brand/40"
        />
        <KanbanCard
          data-card-index
          :card="card"
          @click="emit('card-click', $event)"
        />
      </template>
      <!-- Indicador al final de la columna (soltar debajo de todas). -->
      <div
        v-if="dropIndex !== null && dropIndex >= visibleCards.length"
        class="h-0.5 -my-1 rounded-full bg-n-brand shadow-[0_0_0_1px] shadow-n-brand/40"
      />

      <div
        v-if="allCards.length === 0"
        class="flex flex-col items-center justify-center gap-1.5 py-10 text-n-slate-9 text-sm"
      >
        <span class="i-lucide-inbox size-6 opacity-50" />
        {{ $t('JABVOX_KANBAN.EMPTY_COLUMN') }}
      </div>

      <button
        v-if="!showAll && hiddenCount > 0"
        class="w-full text-xs font-medium text-n-brand hover:bg-n-alpha-1 rounded-lg py-1.5 transition-colors"
        @click="showAll = true"
      >
        {{ $t('JABVOX_KANBAN.SHOW_MORE', { count: hiddenCount }) }}
      </button>

      <button
        v-if="showAll && cardCount > pageSize"
        class="w-full text-xs font-medium text-n-slate-10 hover:bg-n-alpha-1 rounded-lg py-1.5 transition-colors"
        @click="showAll = false"
      >
        {{ $t('JABVOX_KANBAN.SHOW_LESS') }}
      </button>
    </div>
  </div>
</template>
