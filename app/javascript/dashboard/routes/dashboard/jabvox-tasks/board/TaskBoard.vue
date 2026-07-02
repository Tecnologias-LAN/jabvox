<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import TaskColumn from './TaskColumn.vue';
import TaskFormDialog from './TaskFormDialog.vue';
import StageFormDialog from './StageFormDialog.vue';
import StageAutomationsDialog from './StageAutomationsDialog.vue';
import TasksEmptyState from '../components/TasksEmptyState.vue';
import ConfirmDialog from '../components/ConfirmDialog.vue';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const router = useRouter();
const getters = useStoreGetters();
const { isAdmin } = useAdmin();
const store = useTasksStore();

const accountId = computed(() => getters.getCurrentAccountId.value);

const showTaskDialog = ref(false);
const showStageDialog = ref(false);
const showAutomationsDialog = ref(false);
const editingTask = ref(null);
const editingStage = ref(null);
const formStageId = ref(null);
const automationsStage = ref(null);
const confirmDialog = ref(null);

const stages = computed(() => store.stages);
const tasksByStage = computed(() => store.tasksByStage);

const tasksForStage = stageId => tasksByStage.value[stageId] || [];

// Tasks ---------------------------------------------------------------
const openCreateTask = stage => {
  editingTask.value = null;
  formStageId.value = stage?.id || stages.value[0]?.id || null;
  showTaskDialog.value = true;
};

const openTaskDetail = task => {
  router.push({
    name: 'jabvox_tasks_detail',
    params: { accountId: accountId.value, taskId: task.id },
  });
};

const onTaskSubmit = async payload => {
  try {
    if (editingTask.value) {
      await store.updateTask(editingTask.value.id, payload);
      useAlert(t('JABVOX_TASKS.TASK.UPDATED'));
      showTaskDialog.value = false;
      editingTask.value = null;
    } else {
      const created = await store.createTask(payload);
      useAlert(t('JABVOX_TASKS.TASK.CREATED'));
      showTaskDialog.value = false;
      editingTask.value = null;
      // After creating, open the detail view instead of leaving the board.
      if (created?.id) openTaskDetail(created);
    }
  } catch {
    useAlert(t('JABVOX_TASKS.TASK.ERROR'));
  }
};

const onTaskDelete = task => {
  confirmDialog.value?.open({
    title: t('JABVOX_TASKS.TASK.DELETE'),
    description: t('JABVOX_TASKS.TASK.DELETE_CONFIRM'),
    data: task.id,
  });
};

const doTaskDelete = async taskId => {
  try {
    await store.deleteTask(taskId);
    useAlert(t('JABVOX_TASKS.TASK.DELETED'));
    showTaskDialog.value = false;
    editingTask.value = null;
  } catch {
    useAlert(t('JABVOX_TASKS.TASK.ERROR'));
  }
};

const onDropTask = async ({ taskId, stageId }) => {
  const targetTasks = tasksForStage(stageId);
  const position = targetTasks.length;
  try {
    await store.moveTask(taskId, stageId, position);
  } catch {
    useAlert(t('JABVOX_TASKS.TASK.ERROR'));
  }
};

// Stages --------------------------------------------------------------
const openCreateStage = () => {
  editingStage.value = null;
  showStageDialog.value = true;
};

const openEditStage = stage => {
  editingStage.value = stage;
  showStageDialog.value = true;
};

const onStageSubmit = async payload => {
  try {
    if (editingStage.value) {
      await store.updateStage(props.boardId, editingStage.value.id, payload);
      useAlert(t('JABVOX_TASKS.STAGE.UPDATED'));
    } else {
      const position = stages.value.length;
      await store.createStage(props.boardId, {
        ...payload,
        position_jabvox: position,
      });
      useAlert(t('JABVOX_TASKS.STAGE.CREATED'));
    }
    showStageDialog.value = false;
    editingStage.value = null;
  } catch {
    useAlert(t('JABVOX_TASKS.STAGE.ERROR'));
  }
};

// Automations ---------------------------------------------------------
const openAutomations = stage => {
  automationsStage.value = stage;
  showAutomationsDialog.value = true;
};
</script>

<template>
  <div class="flex flex-col h-full min-h-0">
    <TasksEmptyState
      v-if="stages.length === 0"
      icon="i-lucide-columns-3"
      :title="t('JABVOX_TASKS.BOARD.EMPTY_STAGE')"
      :body="t('JABVOX_TASKS.EMPTY_STATE.BODY')"
    >
      <button
        v-if="isAdmin"
        type="button"
        class="mt-2 flex items-center gap-1 px-3 py-2 text-sm rounded-lg bg-n-brand text-white"
        @click="openCreateStage"
      >
        <span class="i-lucide-plus size-4" aria-hidden="true" />
        {{ t('JABVOX_TASKS.BOARD.ADD_STAGE') }}
      </button>
    </TasksEmptyState>

    <div v-else class="flex-1 min-h-0 overflow-x-auto">
      <div class="flex gap-3 h-full pb-2">
        <TaskColumn
          v-for="stage in stages"
          :key="stage.id"
          :stage="stage"
          :tasks="tasksForStage(stage.id)"
          @detail-task="openTaskDetail"
          @add-task="openCreateTask"
          @edit-stage="openEditStage"
          @open-automations="openAutomations"
          @drop-task="onDropTask"
        />

        <div v-if="isAdmin" class="shrink-0 w-[300px]">
          <button
            type="button"
            class="flex items-center justify-center gap-1 w-full py-3 text-sm rounded-xl border border-dashed border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="openCreateStage"
          >
            <span class="i-lucide-plus size-4" aria-hidden="true" />
            {{ t('JABVOX_TASKS.BOARD.ADD_STAGE') }}
          </button>
        </div>
      </div>
    </div>

    <TaskFormDialog
      v-if="showTaskDialog"
      :task="editingTask"
      :board-id="boardId"
      :stages="stages"
      :default-stage-id="formStageId"
      @submit="onTaskSubmit"
      @delete="onTaskDelete"
      @close="showTaskDialog = false"
    />

    <StageFormDialog
      v-if="showStageDialog"
      :stage="editingStage"
      @submit="onStageSubmit"
      @close="showStageDialog = false"
    />

    <StageAutomationsDialog
      v-if="showAutomationsDialog && automationsStage"
      :board-id="boardId"
      :stage="automationsStage"
      :stages="stages"
      @close="showAutomationsDialog = false"
    />

    <ConfirmDialog ref="confirmDialog" @confirm="doTaskDelete" />
  </div>
</template>
