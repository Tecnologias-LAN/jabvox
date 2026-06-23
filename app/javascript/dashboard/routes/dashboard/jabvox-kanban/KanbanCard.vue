<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import JabvoxQuickButtons from 'dashboard/components/widgets/conversation/jabvox/JabvoxQuickButtons.vue';

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
  open: 'bg-n-teal-9',
  resolved: 'bg-n-slate-8',
  pending: 'bg-n-amber-9',
  snoozed: 'bg-n-blue-9',
};

const statusColor = computed(() =>
  isLead.value
    ? 'bg-n-brand'
    : statusColorMap[props.card.status] || 'bg-n-slate-8'
);

const priorityMap = {
  urgent: {
    label: t('JABVOX_KANBAN.PRIORITY.URGENT'),
    class: 'text-n-ruby-11 bg-n-ruby-3',
    dot: 'bg-n-ruby-9',
  },
  high: {
    label: t('JABVOX_KANBAN.PRIORITY.HIGH'),
    class: 'text-n-amber-11 bg-n-amber-3',
    dot: 'bg-n-amber-9',
  },
  medium: {
    label: t('JABVOX_KANBAN.PRIORITY.MEDIUM'),
    class: 'text-n-blue-11 bg-n-blue-3',
    dot: 'bg-n-blue-9',
  },
  low: {
    label: t('JABVOX_KANBAN.PRIORITY.LOW'),
    class: 'text-n-slate-11 bg-n-alpha-2',
    dot: 'bg-n-slate-8',
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
    class="group bg-n-solid-1 rounded-xl border border-n-weak p-3 cursor-grab active:cursor-grabbing hover:border-n-brand/40 hover:shadow-md hover:-translate-y-0.5 transition-all duration-150 select-none"
    draggable="true"
    @click="emit('click', card)"
    @dragstart="onDragStart"
  >
    <div class="flex items-start justify-between gap-2 mb-2">
      <div class="flex items-center gap-1.5 min-w-0">
        <span class="size-2 rounded-full shrink-0" :class="[statusColor]" />
        <span class="text-xs font-mono text-n-slate-10 truncate">
          <template v-if="isLead">#{{ card.lead_number }}</template>
          <template v-else>#{{ card.display_id }} · {{ inboxName }}</template>
        </span>
      </div>
      <span
        v-if="priority"
        class="inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded-md font-medium shrink-0"
        :class="[priority.class]"
      >
        <span class="size-1.5 rounded-full" :class="[priority.dot]" />
        {{ priority.label }}
      </span>
      <span
        v-if="isLead"
        class="text-xs px-1.5 py-0.5 rounded-md font-medium shrink-0 text-n-brand bg-n-alpha-2"
      >
        {{ $t('JABVOX_KANBAN.NO_CONVERSATION') }}
      </span>
    </div>

    <p
      class="text-sm font-semibold text-n-slate-12 leading-tight mb-2 line-clamp-2"
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
        class="text-xs px-1.5 py-0.5 rounded-md bg-n-alpha-1 text-n-slate-11"
      >
        {{ label }}
      </span>
      <span v-if="card.labels.length > 3" class="text-xs text-n-slate-9">
        +{{ card.labels.length - 3 }}
      </span>
    </div>

    <JabvoxQuickButtons
      v-if="card.contact"
      :lead="isLead ? card : null"
      :contact="card.contact"
      size="sm"
      class="mb-2"
      @click.stop
    />
    <div
      class="flex items-center justify-between gap-2 pt-2 border-t border-n-weak"
    >
      <span
        v-if="assigneeName"
        class="inline-flex items-center gap-1 text-xs text-n-slate-11 truncate"
      >
        <span class="i-lucide-user size-3 shrink-0 text-n-slate-9" />
        {{ assigneeName }}
      </span>
      <span
        class="inline-flex items-center gap-1 text-xs text-n-slate-10 ml-auto shrink-0"
      >
        <span class="i-lucide-calendar size-3 text-n-slate-9" />
        {{ formattedDate }}
      </span>
    </div>
  </div>
</template>
