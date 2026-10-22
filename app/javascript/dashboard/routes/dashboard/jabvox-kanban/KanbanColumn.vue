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
      <div class="flex items-center gap-1">
        <select
          v-model="pageSize"
          class="reset-base text-[11px] border border-n-weak rounded-md pl-2 pr-5 h-7 bg-n-background text-n-slate-11 focus:outline-none focus:border-n-slate-7"
          :aria-label="$t('JABVOX_KANBAN.PER_PAGE')"
        >
          <option v-for="size in pageSizeOptions" :key="size" :value="size">
            {{ size }}
          </option>
        </select>
        <button
          class="size-7 flex items-center justify-center rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
          :title="$t('JABVOX_KANBAN.AUTOMATIONS.CONFIGURE')"
          @click.stop="showAutomations = true"
        >
          <span class="i-lucide-settings-2 size-3.5" />
        </button>
      </div>
    </div>

    <div
      class="flex-1 overflow-y-auto p-2 space-y-2 transition-colors"
      :class="isDragOver ? 'bg-n-alpha-1' : ''"
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

  <KanbanStageAutomationPanel
    v-if="showAutomations"
    :stage="stage"
    :funnel-id="funnelId"
    @close="showAutomations = false"
  />
</template>
