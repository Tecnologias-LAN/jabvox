<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import TaskCard from './TaskCard.vue';

const props = defineProps({
  stage: {
    type: Object,
    required: true,
  },
  tasks: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits([
  'detailTask',
  'addTask',
  'editStage',
  'deleteStage',
  'reorderStage',
  'openAutomations',
  'dropTask',
]);

const { t } = useI18n();
const { isAdmin } = useAdmin();

// Colores del papel de la columna, iguales a los del cajón de automatizaciones.
const ROLE_STYLES = {
  initial: 'bg-n-slate-3 text-n-slate-11',
  done: 'bg-n-teal-3 text-n-teal-11',
  inactive: 'bg-n-ruby-3 text-n-ruby-11',
};

const isDragOver = ref(false);
// Arrastre de la COLUMNA (desde su cabecera). El dato lleva prefijo porque las tarjetas
// ya usan dataTransfer con el id pelado: sin distinguirlos, soltar una columna sobre otra
// se interpretaría como mover una tarjeta.
const STAGE_PREFIX = 'stage:';
const isStageDragOver = ref(false);

const onStageDragStart = event => {
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('text/plain', `${STAGE_PREFIX}${props.stage.id}`);
};

const onStageDragOver = event => {
  if (!event.dataTransfer.types.includes('text/plain')) return;
  event.preventDefault();
  isStageDragOver.value = true;
};

const onStageDragLeave = () => {
  isStageDragOver.value = false;
};

const onStageDrop = event => {
  isStageDragOver.value = false;
  const raw = event.dataTransfer.getData('text/plain');
  if (!raw.startsWith(STAGE_PREFIX)) return;
  event.preventDefault();
  event.stopPropagation();
  const draggedId = parseInt(raw.slice(STAGE_PREFIX.length), 10);
  if (draggedId && draggedId !== props.stage.id) {
    emit('reorderStage', { draggedId, targetId: props.stage.id });
  }
};

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
  if (raw.startsWith(STAGE_PREFIX)) return;
  const taskId = parseInt(raw, 10);
  if (taskId) {
    emit('dropTask', { taskId, stageId: props.stage.id });
  }
};
</script>

<template>
  <div
    class="flex flex-col w-[300px] shrink-0 rounded-xl bg-n-solid-2 border border-n-weak h-full"
  >
    <!-- La cabecera es el asa: se arrastra la columna desde aquí, no desde su cuerpo,
         para no chocar con el arrastre de tarjetas. -->
    <div
      class="flex items-center justify-between gap-2 px-3 py-2.5 border-b border-n-weak shrink-0 transition-colors"
      :class="[
        isAdmin ? 'cursor-grab active:cursor-grabbing' : '',
        isStageDragOver ? 'bg-n-alpha-2' : '',
      ]"
      :draggable="isAdmin"
      @dragstart="onStageDragStart"
      @dragover="onStageDragOver"
      @dragleave="onStageDragLeave"
      @drop="onStageDrop"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="size-2.5 rounded-full shrink-0"
          :style="{ backgroundColor: stage.colorJabvox || '#94a3b8' }"
          aria-hidden="true"
        />
        <h3 class="text-sm font-semibold text-n-slate-12 truncate">
          {{ stage.nameJabvox }}
        </h3>
        <span
          class="text-xs font-medium text-n-slate-10 bg-n-alpha-1 rounded-full px-1.5"
        >
          {{ tasks.length }}
        </span>
        <!-- Papel de la columna: qué hace el sistema con ella (dónde nacen las tareas,
             cuál cierra, cuál recoge lo vencido). -->
        <span
          v-if="stage.roleJabvox"
          class="text-[10px] font-medium rounded px-1.5 py-0.5 shrink-0"
          :class="ROLE_STYLES[stage.roleJabvox]"
        >
          {{ t(`JABVOX_TASKS.STAGE_ROLE.${stage.roleJabvox}`) }}
        </span>
      </div>
      <div class="flex items-center gap-1">
        <button
          v-if="isAdmin"
          type="button"
          class="flex items-center justify-center p-1 rounded text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :title="t('JABVOX_TASKS.STAGE.AUTOMATIONS')"
          @click="emit('openAutomations', stage)"
        >
          <span class="i-lucide-zap size-4" aria-hidden="true" />
        </button>
        <button
          v-if="isAdmin"
          type="button"
          class="flex items-center justify-center p-1 rounded text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :title="t('JABVOX_TASKS.STAGE.FORM.EDIT_TITLE')"
          @click="emit('editStage', stage)"
        >
          <span class="i-lucide-pencil size-4" aria-hidden="true" />
        </button>
        <button
          v-if="isAdmin"
          type="button"
          class="flex items-center justify-center p-1 rounded text-n-ruby-11 hover:bg-n-alpha-2"
          :title="t('JABVOX_TASKS.STAGE.DELETE')"
          @click="emit('deleteStage', stage)"
        >
          <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
        </button>
      </div>
    </div>

    <div
      class="flex-1 min-h-0 overflow-y-auto p-2 space-y-2 transition-colors rounded-b-xl"
      :class="isDragOver ? 'bg-n-alpha-1' : ''"
      @dragover="onDragOver"
      @dragleave="onDragLeave"
      @drop="onDrop"
    >
      <TaskCard
        v-for="task in tasks"
        :key="task.id"
        :task="task"
        @detail="emit('detailTask', $event)"
      />

      <p
        v-if="tasks.length === 0"
        class="px-2 py-6 text-center text-sm text-n-slate-10"
      >
        {{ t('JABVOX_TASKS.BOARD.EMPTY_STAGE') }}
      </p>

      <button
        type="button"
        class="flex items-center justify-center gap-1 w-full py-1.5 text-sm text-n-slate-11 hover:bg-n-alpha-1 rounded-lg transition-colors"
        @click="emit('addTask', stage)"
      >
        <span class="i-lucide-plus size-4" aria-hidden="true" />
        {{ t('JABVOX_TASKS.BOARD.ADD_TASK') }}
      </button>
    </div>
  </div>
</template>
