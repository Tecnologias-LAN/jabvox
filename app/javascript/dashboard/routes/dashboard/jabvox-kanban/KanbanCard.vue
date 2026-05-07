<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  card: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['click', 'dragstart']);

const { t } = useI18n();

const isLead = computed(() => props.card.type === 'lead');

const contactName = computed(
  () => props.card.contact?.name || t('JABVOX_KANBAN.UNKNOWN_CONTACT')
);
const assigneeName = computed(() =>
  isLead.value ? null : props.card.assignee?.name || null
);
const inboxName = computed(() =>
  isLead.value ? '' : props.card.inbox?.name || ''
);

const statusColorMap = {
  open: 'bg-green-500',
  resolved: 'bg-slate-400',
  pending: 'bg-yellow-500',
  snoozed: 'bg-blue-400',
};

const statusColor = computed(() =>
  isLead.value
    ? 'bg-indigo-400'
    : statusColorMap[props.card.status] || 'bg-slate-400'
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
  !isLead.value && props.card.priority ? priorityMap[props.card.priority] : null
);

const formattedDate = computed(() => {
  const val = props.card.created_at;
  const ms = typeof val === 'number' ? val * 1000 : val;
  return new Date(ms).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });
});

const onDragStart = event => {
  event.dataTransfer.effectAllowed = 'move';
  const data = isLead.value
    ? `lead_${props.card.lead_id}`
    : String(props.card.id);
  event.dataTransfer.setData('text/plain', data);
  emit('dragstart', data);
};
</script>

<template>
  <div
    class="bg-white dark:bg-slate-800 rounded-lg border border-slate-200 dark:border-slate-700 p-3 cursor-pointer hover:shadow-md transition-shadow select-none"
    draggable="true"
    @click="emit('click', card)"
    @dragstart="onDragStart"
  >
    <div class="flex items-start justify-between gap-2 mb-2">
      <div class="flex items-center gap-1.5 min-w-0">
        <span class="w-2 h-2 rounded-full shrink-0" :class="[statusColor]" />
        <span class="text-xs text-slate-500 dark:text-slate-400 truncate">
          <template v-if="isLead">#{{ card.lead_number }}</template>
          <template v-else>#{{ card.display_id }} · {{ inboxName }}</template>
        </span>
      </div>
      <span
        v-if="priority"
        class="text-xs px-1.5 py-0.5 rounded font-medium shrink-0"
        :class="[priority.class]"
      >
        {{ priority.label }}
      </span>
      <span
        v-if="isLead"
        class="text-xs px-1.5 py-0.5 rounded font-medium shrink-0 text-indigo-600 bg-indigo-50 dark:text-indigo-300 dark:bg-indigo-900/30"
      >
        {{ $t('JABVOX_KANBAN.NO_CONVERSATION') }}
      </span>
    </div>

    <p
      class="text-sm font-medium text-slate-800 dark:text-slate-100 leading-tight mb-2 line-clamp-2"
    >
      {{ contactName }}
    </p>

    <div
      v-if="!isLead && card.labels?.length"
      class="flex flex-wrap gap-1 mb-2"
    >
      <span
        v-for="label in card.labels.slice(0, 3)"
        :key="label"
        class="text-xs px-1.5 py-0.5 rounded bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300"
      >
        {{ label }}
      </span>
      <span v-if="card.labels.length > 3" class="text-xs text-slate-400">
        +{{ card.labels.length - 3 }}
      </span>
    </div>

    <div class="flex items-center justify-between">
      <span
        v-if="assigneeName"
        class="text-xs text-slate-500 dark:text-slate-400 truncate"
      >
        {{ assigneeName }}
      </span>
      <span class="text-xs text-slate-400 dark:text-slate-500 ml-auto">
        {{ formattedDate }}
      </span>
    </div>
  </div>
</template>
