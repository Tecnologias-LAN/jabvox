<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters } from 'dashboard/composables/store';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import TaskBoard from './board/TaskBoard.vue';
import BoardAutomationsDrawer from './board/BoardAutomationsDrawer.vue';
import TasksCalendar from './calendar/TasksCalendar.vue';
import TasksEmptyState from './components/TasksEmptyState.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const getters = useStoreGetters();
const store = useTasksStore();

const view = ref('board');
const appliedLeadId = ref(null);
// Búsqueda por nombre de tarea en el tablero (filtra las tarjetas en vivo).
const taskQuery = ref('');
const taskBoardRef = ref(null);
const showAutomations = ref(false);

// Las automatizaciones del tablero se abren desde el rayo de la barra. El cajón solo
// lista; configurar sigue siendo el diálogo por etapa que ya existía, que vive dentro
// de TaskBoard.
const boardStages = computed(() => taskBoardRef.value?.stages || []);

const openStageAutomations = stage => {
  showAutomations.value = false;
  taskBoardRef.value?.openAutomations(stage);
};

const accountId = computed(() => getters.getCurrentAccountId.value);
const boardId = computed(() => route.params.boardId || null);
const board = computed(() => store.board);
const isLoadingBoard = computed(() => store.uiFlags.fetchingBoard);

const viewOptions = computed(() => [
  {
    value: 'board',
    label: t('JABVOX_TASKS.VIEW.BOARD'),
    icon: 'i-lucide-columns-3',
  },
  {
    value: 'calendar',
    label: t('JABVOX_TASKS.VIEW.CALENDAR'),
    icon: 'i-lucide-calendar',
  },
]);

const refreshTasks = async () => {
  if (!boardId.value) return;
  const params = { board_id: boardId.value };
  if (appliedLeadId.value) params.lead_id = appliedLeadId.value;
  await store.fetchTasks(params);
};

const loadBoard = async id => {
  if (!id) return;
  try {
    await store.getBoard(id);
    await refreshTasks();
  } catch {
    useAlert(t('JABVOX_TASKS.BOARD.ERROR'));
  }
};

// Opening a task from the calendar navigates to its detail view (same as the board).
const openCalendarTask = task => {
  router.push({
    name: 'jabvox_tasks_detail',
    params: { accountId: accountId.value, taskId: task.id },
  });
};

watch(boardId, id => loadBoard(id), { immediate: true });

// The calendar reloads tasks for its month range; refetch full board tasks
// when returning to the board view so columns are complete again.
watch(view, value => {
  if (value === 'board') refreshTasks();
});
</script>

<template>
  <div class="flex w-full h-full min-h-0">
    <div class="flex-1 flex flex-col min-w-0 min-h-0">
      <TasksEmptyState
        v-if="!boardId"
        icon="i-lucide-kanban"
        :title="t('JABVOX_TASKS.BOARD.EMPTY_NO_BOARD')"
        :body="t('JABVOX_TASKS.BOARD.EMPTY_NO_BOARD_BODY')"
      />

      <template v-else>
        <div
          class="flex flex-wrap items-center justify-between gap-3 px-3 sm:px-4 py-3 border-b border-n-weak shrink-0"
        >
          <div class="flex items-center gap-2 min-w-0 order-1">
            <h2 class="text-sm font-semibold text-n-slate-12 truncate">
              {{ board?.nameJabvox }}
            </h2>
          </div>

          <div
            class="flex items-center gap-2 sm:gap-3 order-3 sm:order-2 w-full sm:w-auto"
          >
            <div class="flex-1 sm:flex-none sm:w-56">
              <div class="relative">
                <span
                  class="i-lucide-search size-4 absolute left-3 top-1/2 -translate-y-1/2 text-n-slate-10"
                  aria-hidden="true"
                />
                <input
                  v-model="taskQuery"
                  class="reset-base w-full text-sm rounded-lg border border-n-weak bg-n-alpha-1 pl-9 pr-3 py-2"
                  :placeholder="t('JABVOX_TASKS.SEARCH_TASK_PLACEHOLDER')"
                />
              </div>
            </div>

            <button
              v-if="view === 'board'"
              type="button"
              class="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-1 shrink-0"
              :title="t('JABVOX_TASKS.AUTOMATIONS.DRAWER_TITLE')"
              @click="showAutomations = true"
            >
              <span
                class="i-lucide-zap size-4 text-n-amber-11"
                aria-hidden="true"
              />
              <span class="hidden sm:inline">
                {{ t('JABVOX_TASKS.AUTOMATIONS.SHORT') }}
              </span>
            </button>

            <div
              class="flex items-center gap-1 p-0.5 rounded-lg bg-n-alpha-1 shrink-0"
            >
              <button
                v-for="opt in viewOptions"
                :key="opt.value"
                type="button"
                class="flex items-center gap-1 px-2.5 py-1 text-sm rounded-md transition-colors"
                :class="
                  view === opt.value
                    ? 'bg-n-solid-1 text-n-slate-12'
                    : 'text-n-slate-11'
                "
                @click="view = opt.value"
              >
                <span :class="opt.icon" class="size-4" aria-hidden="true" />
                {{ opt.label }}
              </button>
            </div>
          </div>
        </div>

        <div class="flex-1 min-h-0 p-2 sm:p-4">
          <p v-if="isLoadingBoard" class="text-sm text-n-slate-10">
            {{ t('JABVOX_TASKS.BOARD.LOADING') }}
          </p>

          <TaskBoard
            v-else-if="view === 'board'"
            ref="taskBoardRef"
            :key="boardId"
            :board-id="boardId"
            :search-query="taskQuery"
          />

          <TasksCalendar
            v-else
            :board-id="boardId"
            :lead-id="appliedLeadId"
            @open-task="openCalendarTask"
          />
        </div>
      </template>
    </div>

    <BoardAutomationsDrawer
      v-if="showAutomations"
      :board-id="boardId"
      :board="board"
      :stages="boardStages"
      @close="showAutomations = false"
      @configure="openStageAutomations"
    />
  </div>
</template>
