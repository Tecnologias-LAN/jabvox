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

// Recarga el tablero tras un cambio hecho desde el detalle (por ejemplo la etapa del
// contacto, que las tarjetas pintan), para que no quede desfasado.
const reloadBoard = () => {
  if (selectedFunnelId.value) {
    store.dispatch('jabvoxKanban/fetchBoard', selectedFunnelId.value);
  }
};

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
      class="flex flex-wrap items-center justify-between gap-3 px-4 sm:px-6 py-3.5 border-b border-n-weak bg-n-solid-1 shrink-0"
    >
      <div class="flex items-center gap-3 min-w-0">
        <span
          class="i-lucide-kanban size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-lg font-semibold tracking-tight text-n-slate-12">
            {{ $t('JABVOX_KANBAN.TITLE') }}
          </h1>
          <p class="text-xs text-n-slate-10 hidden sm:block">
            {{ $t('JABVOX_KANBAN.SUBTITLE') }}
          </p>
        </div>
      </div>

      <div
        class="flex flex-1 sm:flex-none items-center gap-2 sm:gap-3 w-full sm:w-auto"
      >
        <span class="text-sm text-n-slate-10 shrink-0">
          {{ $t('JABVOX_KANBAN.FUNNEL_LABEL') }}
        </span>
        <select
          v-model="selectedFunnelId"
          class="reset-base text-sm border border-n-weak rounded-lg px-3 h-9 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 w-full sm:w-64 transition-colors"
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
      class="flex-1 flex items-center justify-center gap-2 text-n-slate-11 text-sm"
    >
      <span class="i-lucide-loader-circle size-4 animate-spin" />
      {{ $t('JABVOX_KANBAN.LOADING') }}
    </div>

    <div
      v-else-if="activeFunnels.length === 0"
      class="flex-1 flex flex-col items-center justify-center gap-3 text-n-slate-11 px-6 text-center"
    >
      <span class="i-lucide-kanban size-14 text-n-brand opacity-40" />
      <p class="text-sm text-n-slate-12 font-medium">
        {{ $t('JABVOX_KANBAN.NO_FUNNELS') }}
      </p>
      <router-link
        :to="{ name: 'jabvox_kanban_funnels_index' }"
        class="text-sm text-n-brand hover:underline font-medium"
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
        class="flex-[3] min-w-0 max-w-[720px] shrink-0 border-l border-n-weak overflow-hidden"
      >
        <KanbanLeadDetail
          :conversation="selectedConversation"
          @close="onCloseDetail"
          @refresh="reloadBoard"
        />
      </div>
    </div>
  </div>
</template>
