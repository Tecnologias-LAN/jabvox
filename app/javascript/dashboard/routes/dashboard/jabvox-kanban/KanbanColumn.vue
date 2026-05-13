<script setup>
import { ref, computed, watch } from 'vue';
import KanbanCard from './KanbanCard.vue';
import KanbanStageAutomationPanel from './KanbanStageAutomationPanel.vue';

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

const showAutomations = ref(false);

const isDragOver = ref(false);
const showAll = ref(false);
const pageSize = ref(10);
const pageSizeOptions = [5, 10, 25, 50];

watch(
  () => pageSize.value,
  () => {
    showAll.value = false;
  }
);

const allCards = computed(() => [
  ...props.conversations.map(c => ({ ...c, type: 'conversation' })),
  ...props.leadCards,
]);

const cardCount = computed(() => allCards.value.length);
const visibleCards = computed(() =>
  showAll.value ? allCards.value : allCards.value.slice(0, pageSize.value)
);
const hiddenCount = computed(() =>
  Math.max(0, allCards.value.length - pageSize.value)
);

const onDragOver = event => {
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
  isDragOver.value = true;
};

const onDragLeave = () => {
  isDragOver.value = false;
};

const onDrop = event => {
  event.preventDefault();
  isDragOver.value = false;
  const raw = event.dataTransfer.getData('text/plain');
  if (raw.startsWith('lead_')) {
    const leadId = parseInt(raw.replace('lead_', ''), 10);
    if (leadId) emit('drop', { leadId, stageId: props.stage.id });
  } else {
    const conversationId = parseInt(raw, 10);
    if (conversationId)
      emit('drop', { conversationId, stageId: props.stage.id });
  }
};
</script>

<template>
  <div
    class="flex flex-col min-w-[260px] w-[280px] sm:w-[300px] lg:w-[320px] flex-shrink-0 bg-slate-50 dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-700 h-full"
  >
    <div
      class="flex items-center justify-between px-3 py-2.5 border-b border-slate-200 dark:border-slate-700"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="w-3 h-3 rounded-full shrink-0"
          :style="{ backgroundColor: stage.color_jabvox }"
        />
        <h3
          class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate"
        >
          {{ stage.name_jabvox }}
        </h3>
      </div>
      <div class="flex items-center gap-2">
        <select
          v-model="pageSize"
          class="text-[11px] border border-slate-200 dark:border-slate-700 rounded-md px-2 py-1 bg-white dark:bg-slate-800 text-slate-600 dark:text-slate-300 focus:outline-none focus:ring-2 focus:ring-woot-500"
          :aria-label="$t('JABVOX_KANBAN.PER_PAGE')"
        >
          <option v-for="size in pageSizeOptions" :key="size" :value="size">
            {{ size }}
          </option>
        </select>
        <button
          class="w-6 h-6 flex items-center justify-center rounded text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors"
          :title="$t('JABVOX_KANBAN.AUTOMATIONS.CONFIGURE')"
          @click="showAutomations = true"
        >
          <span class="i-lucide-settings-2 w-3.5 h-3.5" />
        </button>
        <span
          class="text-xs font-medium text-slate-500 dark:text-slate-400 bg-slate-200 dark:bg-slate-700 rounded-full px-2 py-0.5"
        >
          {{ cardCount }}
        </span>
      </div>
    </div>

    <div
      class="flex-1 overflow-y-auto p-2 space-y-2 transition-colors"
      :class="isDragOver ? 'bg-slate-100 dark:bg-slate-800' : ''"
      @dragover="onDragOver"
      @dragleave="onDragLeave"
      @drop="onDrop"
    >
      <KanbanCard
        v-for="card in visibleCards"
        :key="card.type === 'lead' ? `lead_${card.lead_id}` : card.id"
        :card="card"
        @click="emit('card-click', $event)"
      />

      <div
        v-if="allCards.length === 0"
        class="flex items-center justify-center py-8 text-slate-400 dark:text-slate-600 text-sm"
      >
        {{ $t('JABVOX_KANBAN.EMPTY_COLUMN') }}
      </div>

      <button
        v-if="!showAll && hiddenCount > 0"
        class="w-full text-xs text-woot-600 dark:text-woot-400 hover:underline py-1"
        @click="showAll = true"
      >
        {{ $t('JABVOX_KANBAN.SHOW_MORE', { count: hiddenCount }) }}
      </button>

      <button
        v-if="showAll && cardCount > pageSize"
        class="w-full text-xs text-slate-500 dark:text-slate-400 hover:underline py-1"
        @click="showAll = false"
      >
        {{ $t('JABVOX_KANBAN.SHOW_LESS') }}
      </button>
    </div>
  </div>

  <KanbanStageAutomationPanel
    v-if="showAutomations"
    :stage="stage"
    :funnel-id="funnelId"
    @close="showAutomations = false"
  />
</template>
