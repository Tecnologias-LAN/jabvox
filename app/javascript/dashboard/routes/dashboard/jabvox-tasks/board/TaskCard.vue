<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  task: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['detail']);

const { t } = useI18n();

const priorityLabelMap = computed(() => ({
  low: t('JABVOX_TASKS.TASK.PRIORITY_LOW'),
  normal: t('JABVOX_TASKS.TASK.PRIORITY_NORMAL'),
  high: t('JABVOX_TASKS.TASK.PRIORITY_HIGH'),
  urgent: t('JABVOX_TASKS.TASK.PRIORITY_URGENT'),
}));

const priorityClassMap = {
  low: 'bg-n-alpha-1 text-n-slate-10',
  normal: 'bg-n-blue-3 text-n-blue-11',
  high: 'bg-n-teal-3 text-n-teal-11',
  urgent: 'bg-n-ruby-9 text-white',
};

const priority = computed(() => props.task.priorityJabvox || 'normal');
const priorityLabel = computed(
  () => priorityLabelMap.value[priority.value] || priority.value
);
const priorityClass = computed(
  () => priorityClassMap[priority.value] || priorityClassMap.normal
);

const isDone = computed(() => props.task.statusJabvox === 'done');

// Number of active recurring automations on this task (shown as a small badge).
const automationsCount = computed(() => props.task.activeAutomationsCount || 0);

// Una tarea repetitiva se marca en la tarjeta: al completarla nace la siguiente, y eso
// conviene saberlo antes de cerrarla.
const isRecurring = computed(() => Boolean(props.task.recurrenceUnitJabvox));

// Responsibles to show on the card: prefer the multi-assignee list, fall back to legacy single.
const assigneeNames = computed(() => {
  const list = props.task.assignees;
  if (Array.isArray(list) && list.length) return list.map(a => a.name);
  return props.task.assigneeName ? [props.task.assigneeName] : [];
});

const dueLabel = computed(() => {
  if (!props.task.dueAtJabvox) return '';
  const date = new Date(props.task.dueAtJabvox);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });
});

const onDragStart = event => {
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('text/plain', String(props.task.id));
};
</script>

<template>
  <div
    draggable="true"
    class="flex flex-col gap-2 p-3 rounded-lg bg-n-solid-1 border border-n-weak cursor-pointer hover:border-n-strong hover:shadow-sm transition-all"
    @dragstart="onDragStart"
    @click="emit('detail', task)"
  >
    <div class="flex items-start justify-between gap-2">
      <p
        class="text-sm font-medium text-n-slate-12 break-words"
        :class="isDone ? 'line-through text-n-slate-10' : ''"
      >
        {{ task.titleJabvox }}
      </p>
      <span
        class="shrink-0 text-[11px] font-medium rounded-full px-2 py-0.5"
        :class="priorityClass"
      >
        {{ priorityLabel }}
      </span>
    </div>

    <div class="flex flex-wrap items-center gap-1.5">
      <span
        v-if="task.leadName"
        class="inline-flex items-center gap-1 text-[11px] rounded-full px-2 py-0.5 bg-n-alpha-2 text-n-slate-11"
      >
        <span class="i-lucide-user size-4 scale-75" aria-hidden="true" />
        {{ task.leadName }}
      </span>
      <span
        v-for="name in assigneeNames"
        :key="name"
        class="inline-flex items-center gap-1 text-[11px] rounded-full px-2 py-0.5 bg-n-alpha-1 text-n-slate-10"
      >
        <span class="i-lucide-circle-user size-4 scale-75" aria-hidden="true" />
        {{ name }}
      </span>
      <span
        v-if="dueLabel"
        class="inline-flex items-center gap-1 text-[11px] rounded-full px-2 py-0.5 bg-n-alpha-1 text-n-slate-10"
      >
        <span class="i-lucide-calendar size-4 scale-75" aria-hidden="true" />
        {{ dueLabel }}
      </span>
      <span
        v-if="automationsCount"
        class="inline-flex items-center gap-1 text-[11px] rounded-full px-2 py-0.5 bg-n-iris-3 text-n-iris-11"
        :title="t('JABVOX_TASKS.AUTOMATION.CARD_BADGE', automationsCount)"
      >
        <span class="i-lucide-zap size-4 scale-75" aria-hidden="true" />
        {{ automationsCount }}
      </span>
      <span
        v-if="isRecurring"
        class="inline-flex items-center gap-1 text-[11px] rounded-full px-2 py-0.5 bg-n-teal-3 text-n-teal-11"
        :title="t('JABVOX_TASKS.RECURRENCE.BADGE')"
      >
        <span class="i-lucide-repeat size-4 scale-75" aria-hidden="true" />
      </span>
    </div>
  </div>
</template>
