<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import KanbanBoard from './KanbanBoard.vue';
import KanbanLeadDetail from './KanbanLeadDetail.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const funnels = useMapGetter('jabvoxKanban/getFunnels');
const currentBoard = useMapGetter('jabvoxKanban/getCurrentBoard');
const uiFlags = useMapGetter('jabvoxKanban/getUIFlags');

const selectedFunnelId = ref(null);
const selectedConversation = ref(null);
const isDetailOpen = ref(false);

const activeFunnels = computed(() =>
  (funnels.value || []).filter(f => f.active_jabvox)
);

onMounted(async () => {
  await store.dispatch('jabvoxKanban/fetchFunnels');
  if (activeFunnels.value.length === 0) return;

  const routeFunnelId = Number(route.params.funnelId);
  const routeFunnelExists = activeFunnels.value.some(
    f => f.id === routeFunnelId
  );
  selectedFunnelId.value = routeFunnelExists
    ? routeFunnelId
    : activeFunnels.value[0].id;
});

watch(selectedFunnelId, async newId => {
  if (newId) {
    if (
      route.name !== 'jabvox_kanban_funnel' ||
      Number(route.params.funnelId) !== Number(newId)
    ) {
      router.replace({
        name: 'jabvox_kanban_funnel',
        params: { ...route.params, funnelId: newId },
      });
    }
    await store.dispatch('jabvoxKanban/fetchBoard', newId);
  }
});

const onSelectFunnel = id => {
  selectedFunnelId.value = id;
  isDetailOpen.value = false;
  selectedConversation.value = null;
};

const onCardClick = card => {
  if (card.type === 'lead') return; // lead cards don't have a conversation to open
  selectedConversation.value = card;
  isDetailOpen.value = true;
};

const onCloseDetail = () => {
  isDetailOpen.value = false;
  selectedConversation.value = null;
};

const onMoveConversation = async ({ conversationId, stageId }) => {
  if (!selectedFunnelId.value) return;
  try {
    await store.dispatch('jabvoxKanban/moveConversation', {
      funnelId: selectedFunnelId.value,
      conversationId,
      stageId,
    });
  } catch (error) {
    useAlert(t('JABVOX_KANBAN.MOVE_ERROR'));
  }
};

const onMoveLead = async ({ leadId, stageId }) => {
  if (!selectedFunnelId.value) return;
  try {
    await store.dispatch('jabvoxKanban/moveLead', {
      funnelId: selectedFunnelId.value,
      leadId,
      stageId,
    });
  } catch (error) {
    useAlert(t('JABVOX_KANBAN.MOVE_ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-background">
    <div
      class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <div class="flex items-center gap-3">
        <i class="i-lucide-kanban text-slate-600 dark:text-slate-300 text-xl" />
        <h1 class="text-lg font-semibold text-slate-800 dark:text-slate-100">
          {{ $t('JABVOX_KANBAN.TITLE') }}
        </h1>
      </div>

      <div
        class="flex flex-1 sm:flex-none items-center gap-2 sm:gap-3 w-full sm:w-auto"
      >
        <span class="text-sm text-slate-500 dark:text-slate-400 shrink-0">
          {{ $t('JABVOX_KANBAN.FUNNEL_LABEL') }}
        </span>
        <select
          v-model="selectedFunnelId"
          class="text-sm border border-slate-200 dark:border-slate-700 rounded-lg px-3 py-2 bg-white dark:bg-slate-800 text-slate-700 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-woot-500 w-full sm:w-64"
          @change="onSelectFunnel(selectedFunnelId)"
        >
          <option
            v-for="funnel in activeFunnels"
            :key="funnel.id"
            :value="funnel.id"
          >
            {{ funnel.name_jabvox }}
          </option>
        </select>
      </div>
    </div>

    <div
      v-if="uiFlags.isFetchingFunnels || uiFlags.isFetchingBoard"
      class="flex-1 flex items-center justify-center"
    >
      <span class="text-slate-500 dark:text-slate-400 text-sm animate-pulse">
        {{ $t('JABVOX_KANBAN.LOADING') }}
      </span>
    </div>

    <div
      v-else-if="activeFunnels.length === 0"
      class="flex-1 flex flex-col items-center justify-center gap-3 text-slate-500 dark:text-slate-400"
    >
      <i class="i-lucide-kanban text-4xl opacity-30" />
      <p class="text-sm">{{ $t('JABVOX_KANBAN.NO_FUNNELS') }}</p>
      <router-link
        :to="{ name: 'jabvox_kanban_funnels_index' }"
        class="text-sm text-woot-600 hover:underline"
      >
        {{ $t('JABVOX_KANBAN.CONFIGURE_FUNNELS') }}
      </router-link>
    </div>

    <div v-else class="flex flex-1 w-full overflow-hidden">
      <div
        class="overflow-hidden transition-all duration-200 w-full"
        :class="isDetailOpen ? 'flex-[2] min-w-0' : 'flex-1'"
      >
        <KanbanBoard
          v-if="currentBoard"
          :board="currentBoard"
          :funnel-id="selectedFunnelId"
          @card-click="onCardClick"
          @move-conversation="onMoveConversation"
          @move-lead="onMoveLead"
        />
      </div>

      <div
        v-if="isDetailOpen && selectedConversation"
        class="flex-[3] min-w-0 max-w-[720px] shrink-0 border-l border-slate-200 dark:border-slate-700 overflow-hidden"
      >
        <KanbanLeadDetail
          :conversation="selectedConversation"
          @close="onCloseDetail"
        />
      </div>
    </div>
  </div>
</template>
