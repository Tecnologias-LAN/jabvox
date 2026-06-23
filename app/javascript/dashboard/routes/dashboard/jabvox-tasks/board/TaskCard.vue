<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  task: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['open']);

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
    class="flex flex-col gap-2 p-3 rounded-lg bg-n-solid-1 border border-n-weak cursor-grab hover:border-n-strong transition-colors"
    @dragstart="onDragStart"
    @click="emit('open', task)"
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
        v-if="task.assigneeName"
        class="inline-flex items-center gap-1 text-[11px] rounded-full px-2 py-0.5 bg-n-alpha-1 text-n-slate-10"
      >
        <span class="i-lucide-circle-user size-4 scale-75" aria-hidden="true" />
        {{ task.assigneeName }}
      </span>
      <span
        v-if="dueLabel"
        class="inline-flex items-center gap-1 text-[11px] rounded-full px-2 py-0.5 bg-n-alpha-1 text-n-slate-10"
      >
        <span class="i-lucide-calendar size-4 scale-75" aria-hidden="true" />
        {{ dueLabel }}
      </span>
    </div>
  </div>
</template>
