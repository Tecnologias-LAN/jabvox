<script setup>
import { ref, computed, watch } from 'vue';
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
  'sortChange',
]);

const { t } = useI18n();
const { isAdmin } = useAdmin();

// Orden de las tarjetas de ESTA columna. Se inicializa del valor guardado en la etapa
// (card_sort_jabvox) y al cambiarlo se persiste en BD por columna.
const cardSort = ref(props.stage.cardSortJabvox || 'manual');
watch(
  () => props.stage.cardSortJabvox,
  value => {
    cardSort.value = value || 'manual';
  }
);

const onSortChange = () => {
  emit('sortChange', { stageId: props.stage.id, cardSort: cardSort.value });
};

// Las tareas ya vienen ordenadas por posición del store; aquí se aplica el orden elegido
// (fecha o título) en cliente para que el cambio del selector se vea al instante.
const sortedTasks = computed(() => {
  const list = [...props.tasks];
  switch (cardSort.value) {
    case 'date_desc':
      return list.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    case 'date_asc':
      return list.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
    case 'title_asc':
      return list.sort((a, b) =>
        (a.titleJabvox || '').localeCompare(b.titleJabvox || '')
      );
    case 'title_desc':
      return list.sort((a, b) =>
        (b.titleJabvox || '').localeCompare(a.titleJabvox || '')
      );
    default:
      return list; // manual: respeta el orden por posición
  }
});

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

const cardsContainer = ref(null);
// Índice donde caería la tarjeta ahora mismo (para dibujar la línea indicadora).
const dropIndex = ref(null);

// Índice de destino dentro de la columna según la posición Y del cursor: cuenta cuántas
// tarjetas quedan por ENCIMA del punto donde se soltó (su punto medio). Así soltar entre
// dos tarjetas inserta en medio, no siempre al final.
const dropIndexFromEvent = event => {
  const container = cardsContainer.value;
  if (!container) return null;
  const cards = [...container.querySelectorAll('[data-task-index]')];
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
  if (!event.dataTransfer.types.includes('text/plain')) return;
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
  if (raw.startsWith(STAGE_PREFIX)) return;
  const taskId = parseInt(raw, 10);
  if (taskId) {
    const position = dropIndexFromEvent(event);
    // Si el usuario arrastra a una posición concreta, manda el arrastre: la columna pasa a
    // orden Manual (si tenía fecha/título) para que el movimiento se respete.
    if (cardSort.value !== 'manual') {
      cardSort.value = 'manual';
      onSortChange();
    }
    emit('dropTask', { taskId, stageId: props.stage.id, position });
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

    <!-- Orden de las tarjetas de esta columna (persiste por columna en BD). -->
    <div class="px-2 py-1.5 border-b border-n-weak shrink-0">
      <select
        v-model="cardSort"
        class="reset-base w-full text-xs border border-n-weak rounded-md pl-2 pr-6 h-7 bg-n-background text-n-slate-11 cursor-pointer focus:outline-none focus:border-n-slate-7"
        :aria-label="t('JABVOX_TASKS.SORT.LABEL')"
        @change="onSortChange"
      >
        <option value="manual">{{ t('JABVOX_TASKS.SORT.MANUAL') }}</option>
        <option value="date_desc">
          {{ t('JABVOX_TASKS.SORT.DATE_DESC') }}
        </option>
        <option value="date_asc">{{ t('JABVOX_TASKS.SORT.DATE_ASC') }}</option>
        <option value="title_asc">
          {{ t('JABVOX_TASKS.SORT.TITLE_ASC') }}
        </option>
        <option value="title_desc">
          {{ t('JABVOX_TASKS.SORT.TITLE_DESC') }}
        </option>
      </select>
    </div>

    <div
      ref="cardsContainer"
      class="flex-1 min-h-0 overflow-y-auto p-2 space-y-2 transition-colors rounded-b-xl"
      :class="isDragOver ? 'bg-n-alpha-1' : ''"
      @dragover="onDragOver"
      @dragleave="onDragLeave"
      @drop="onDrop"
    >
      <template v-for="(task, idx) in sortedTasks" :key="task.id">
        <!-- Línea que marca dónde quedaría la tarjeta al soltar. -->
        <div
          v-if="dropIndex === idx"
          class="h-0.5 -my-1 rounded-full bg-n-brand shadow-[0_0_0_1px] shadow-n-brand/40"
        />
        <TaskCard
          data-task-index
          :task="task"
          @detail="emit('detailTask', $event)"
        />
      </template>
      <!-- Indicador al final de la columna (soltar debajo de todas). -->
      <div
        v-if="dropIndex !== null && dropIndex >= sortedTasks.length"
        class="h-0.5 -my-1 rounded-full bg-n-brand shadow-[0_0_0_1px] shadow-n-brand/40"
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
