<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import BoardFormDialog from './BoardFormDialog.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const getters = useStoreGetters();
const { isAdmin } = useAdmin();
const store = useTasksStore();

const showBoardDialog = ref(false);
const editingBoard = ref(null);
const showBoardsDrawer = ref(false); // mobile
const confirmDialog = ref(null);

const accountId = computed(() => getters.getCurrentAccountId.value);
const boards = computed(() => store.boardList);
const isLoading = computed(() => store.uiFlags.fetchingBoards);
const activeBoardId = computed(() =>
  route.params.boardId ? Number(route.params.boardId) : null
);

const goToBoard = id => {
  showBoardsDrawer.value = false;
  router.push({
    name: 'jabvox_tasks_board',
    params: { accountId: accountId.value, boardId: id },
  });
};

const openCreateBoard = () => {
  editingBoard.value = null;
  showBoardDialog.value = true;
};

const openEditBoard = board => {
  editingBoard.value = board;
  showBoardDialog.value = true;
};

const onBoardSubmit = async payload => {
  try {
    if (editingBoard.value) {
      await store.updateBoard(editingBoard.value.id, payload);
      useAlert(t('JABVOX_TASKS.BOARDS.UPDATED'));
    } else {
      const board = await store.createBoard(payload);
      useAlert(t('JABVOX_TASKS.BOARDS.CREATED'));
      goToBoard(board.id);
    }
    showBoardDialog.value = false;
    editingBoard.value = null;
  } catch {
    useAlert(t('JABVOX_TASKS.BOARDS.ERROR'));
  }
};

const onBoardDelete = board => {
  confirmDialog.value?.open({
    title: t('JABVOX_TASKS.BOARDS.DELETE'),
    description: t('JABVOX_TASKS.BOARDS.DELETE_CONFIRM'),
    data: board,
  });
};

const doBoardDelete = async board => {
  try {
    const wasActive = activeBoardId.value === board.id;
    await store.deleteBoard(board.id);
    useAlert(t('JABVOX_TASKS.BOARDS.DELETED'));
    if (wasActive) {
      const next = boards.value[0];
      if (next) {
        goToBoard(next.id);
      } else {
        router.push({
          name: 'jabvox_tasks_index',
          params: { accountId: accountId.value },
        });
      }
    }
  } catch {
    useAlert(t('JABVOX_TASKS.BOARDS.ERROR'));
  }
};

onMounted(async () => {
  try {
    await store.fetchBoards();
  } catch {
    useAlert(t('JABVOX_TASKS.BOARDS.ERROR'));
  }
});
</script>

<template>
  <div class="flex w-full h-full bg-n-background relative">
    <!-- Mobile drawer backdrop -->
    <div
      v-if="showBoardsDrawer"
      class="fixed inset-0 z-30 bg-n-alpha-black2 md:hidden"
      @click="showBoardsDrawer = false"
    />

    <nav
      class="flex-col w-64 md:w-60 shrink-0 h-full border-r border-n-weak bg-n-solid-1 z-40 md:flex md:static"
      :class="
        showBoardsDrawer
          ? 'flex fixed inset-y-0 left-0 shadow-xl'
          : 'hidden md:flex'
      "
    >
      <div
        class="flex items-center justify-between px-4 py-3 border-b border-n-weak shrink-0"
      >
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('JABVOX_TASKS.BOARDS.HEADER') }}
        </h2>
        <button
          v-if="isAdmin"
          type="button"
          class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-1"
          :title="t('JABVOX_TASKS.BOARDS.NEW')"
          @click="openCreateBoard"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
        </button>
      </div>

      <div class="flex-1 min-h-0 overflow-y-auto p-2 space-y-1">
        <p v-if="isLoading" class="px-2 py-2 text-sm text-n-slate-10">
          {{ t('JABVOX_TASKS.BOARDS.LOADING') }}
        </p>

        <template v-else-if="boards.length">
          <div
            v-for="b in boards"
            :key="b.id"
            class="group flex items-center gap-1 rounded-lg transition-colors"
            :class="
              activeBoardId === b.id ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'
            "
          >
            <button
              type="button"
              class="flex items-center gap-2 flex-1 min-w-0 px-2.5 py-2 text-sm text-left"
              :class="
                activeBoardId === b.id ? 'text-n-slate-12' : 'text-n-slate-11'
              "
              @click="goToBoard(b.id)"
            >
              <span
                class="i-lucide-kanban size-4 shrink-0"
                aria-hidden="true"
              />
              <span class="truncate">{{ b.nameJabvox }}</span>
            </button>
            <div
              v-if="isAdmin"
              class="flex items-center gap-0.5 pr-1 opacity-0 group-hover:opacity-100"
            >
              <button
                type="button"
                class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                :title="t('JABVOX_TASKS.BOARDS.FORM.EDIT_TITLE')"
                @click="openEditBoard(b)"
              >
                <span class="i-lucide-pencil size-4" aria-hidden="true" />
              </button>
              <button
                type="button"
                class="p-1 rounded text-n-ruby-11 hover:bg-n-alpha-2"
                :title="t('JABVOX_TASKS.BOARDS.DELETE')"
                @click="onBoardDelete(b)"
              >
                <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
              </button>
            </div>
          </div>
        </template>

        <div v-else class="px-2 py-3 space-y-2">
          <p class="text-sm text-n-slate-10">
            {{ t('JABVOX_TASKS.BOARDS.EMPTY') }}
          </p>
          <p class="text-[11px] text-n-slate-10">
            {{ t('JABVOX_TASKS.BOARDS.CREATE_FIRST') }}
          </p>
          <button
            v-if="isAdmin"
            type="button"
            class="flex items-center gap-1 px-2.5 py-2 text-sm rounded-lg bg-n-brand text-white"
            @click="openCreateBoard"
          >
            <span class="i-lucide-plus size-4" aria-hidden="true" />
            {{ t('JABVOX_TASKS.BOARDS.NEW') }}
          </button>
        </div>
      </div>
    </nav>

    <div class="flex-1 min-w-0 h-full flex flex-col">
      <!-- Mobile: open boards drawer -->
      <button
        type="button"
        class="md:hidden flex items-center gap-2 shrink-0 px-4 py-2.5 border-b border-n-weak bg-n-solid-1 text-sm font-medium text-n-slate-11"
        @click="showBoardsDrawer = true"
      >
        <span class="i-lucide-panel-left size-4" aria-hidden="true" />
        {{ t('JABVOX_TASKS.BOARDS.HEADER') }}
      </button>
      <div class="flex-1 min-h-0">
        <router-view />
      </div>
    </div>

    <BoardFormDialog
      v-if="showBoardDialog"
      :board="editingBoard"
      @submit="onBoardSubmit"
      @close="showBoardDialog = false"
    />

    <ConfirmDialog ref="confirmDialog" @confirm="doBoardDelete" />
  </div>
</template>
