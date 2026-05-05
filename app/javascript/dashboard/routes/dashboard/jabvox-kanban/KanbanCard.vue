<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['click', 'dragstart']);

const { t } = useI18n();

const contactName = computed(
  () => props.conversation.contact?.name || t('JABVOX_KANBAN.UNKNOWN_CONTACT')
);
const assigneeName = computed(() => props.conversation.assignee?.name || null);
const inboxName = computed(() => props.conversation.inbox?.name || '');

const statusColorMap = {
  open: 'bg-green-500',
  resolved: 'bg-slate-400',
  pending: 'bg-yellow-500',
  snoozed: 'bg-blue-400',
};

const statusColor = computed(
  () => statusColorMap[props.conversation.status] || 'bg-slate-400'
);

const priorityMap = {
  urgent: {
    label: t('JABVOX_KANBAN.PRIORITY.URGENT'),
    class: 'text-red-600 bg-red-50',
  },
  high: {
    label: t('JABVOX_KANBAN.PRIORITY.HIGH'),
    class: 'text-orange-600 bg-orange-50',
  },
  medium: {
    label: t('JABVOX_KANBAN.PRIORITY.MEDIUM'),
    class: 'text-yellow-600 bg-yellow-50',
  },
  low: {
    label: t('JABVOX_KANBAN.PRIORITY.LOW'),
    class: 'text-slate-600 bg-slate-100',
  },
};

const priority = computed(() =>
  props.conversation.priority ? priorityMap[props.conversation.priority] : null
);

const formattedDate = computed(() => {
  const date = new Date(props.conversation.created_at);
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
});

const onDragStart = event => {
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('text/plain', String(props.conversation.id));
  emit('dragstart', props.conversation.id);
};
</script>

<template>
  <div
    class="bg-white dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700 p-3 cursor-pointer hover:shadow-md transition-shadow select-none"
    draggable="true"
    @click="emit('click', conversation)"
    @dragstart="onDragStart"
  >
    <div class="flex items-start justify-between gap-2 mb-2">
      <div class="flex items-center gap-1.5 min-w-0">
        <span class="w-2 h-2 rounded-full shrink-0" :class="[statusColor]" />
        <span class="text-xs text-slate-500 dark:text-slate-400 truncate">
          #{{ conversation.display_id }} · {{ inboxName }}
        </span>
      </div>
      <span
        v-if="priority"
        class="text-xs px-1.5 py-0.5 rounded font-medium shrink-0"
        :class="[priority.class]"
      >
        {{ priority.label }}
      </span>
    </div>

    <p
      class="text-sm font-medium text-slate-800 dark:text-slate-100 leading-tight mb-2 line-clamp-2"
    >
      {{ contactName }}
    </p>

    <div v-if="conversation.labels?.length" class="flex flex-wrap gap-1 mb-2">
      <span
        v-for="label in conversation.labels.slice(0, 3)"
        :key="label"
        class="text-xs px-1.5 py-0.5 rounded bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300"
      >
        {{ label }}
      </span>
      <span
        v-if="conversation.labels.length > 3"
        class="text-xs text-slate-400"
      >
        +{{ conversation.labels.length - 3 }}
      </span>
    </div>

    <div class="flex items-center justify-between">
      <span
        v-if="assigneeName"
        class="text-xs text-slate-500 dark:text-slate-400 truncate"
      >
        {{ assigneeName }}
      </span>
      <span class="text-xs text-slate-400 dark:text-slate-500 ml-auto">{{
        formattedDate
      }}</span>
    </div>
  </div>
</template>
