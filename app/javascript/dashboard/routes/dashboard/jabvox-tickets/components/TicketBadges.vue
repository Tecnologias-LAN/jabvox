<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Badge de color para tipo / prioridad / estado de un ticket, con los tokens de la
// app (compatibles claro/oscuro).
const props = defineProps({
  kind: { type: String, required: true }, // 'type' | 'priority' | 'status'
  value: { type: String, default: '' },
});

const { t } = useI18n();

const CLASSES = {
  priority: {
    low: 'bg-n-alpha-1 text-n-slate-11',
    medium: 'bg-n-teal-3 text-n-teal-11',
    high: 'bg-n-amber-3 text-n-amber-11',
    urgent: 'bg-n-ruby-3 text-n-ruby-11',
  },
  status: {
    new_ticket: 'bg-n-blue-3 text-n-blue-11',
    assigned: 'bg-n-blue-3 text-n-blue-11',
    in_progress: 'bg-n-amber-3 text-n-amber-11',
    on_hold: 'bg-n-alpha-1 text-n-slate-11',
    resolved: 'bg-n-teal-3 text-n-teal-11',
    closed: 'bg-n-alpha-1 text-n-slate-10',
    reopened: 'bg-n-ruby-3 text-n-ruby-11',
  },
  type: {
    incident: 'bg-n-ruby-3 text-n-ruby-11',
    requirement: 'bg-n-blue-3 text-n-blue-11',
    request: 'bg-n-teal-3 text-n-teal-11',
  },
};

const badgeClass = computed(
  () => CLASSES[props.kind]?.[props.value] || 'bg-n-alpha-1 text-n-slate-11'
);

const label = computed(() => {
  const ns = { type: 'TYPE', priority: 'PRIORITY', status: 'STATUS' }[
    props.kind
  ];
  return t(`JABVOX_TICKETS.${ns}.${(props.value || '').toUpperCase()}`);
});
</script>

<template>
  <span
    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap"
    :class="badgeClass"
  >
    {{ label }}
  </span>
</template>
