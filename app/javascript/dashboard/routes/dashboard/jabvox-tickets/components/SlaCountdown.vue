<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Contador de SLA visual: verde / ámbar / rojo según cuánto falta para vencer.
// Recibe el semáforo (sla_status) y los minutos restantes (minutes_to_due) que ya
// calcula el backend, para no depender del reloj del cliente.
const props = defineProps({
  status: { type: String, default: 'none' }, // none | green | amber | red
  minutes: { type: Number, default: null },
});

const { t } = useI18n();

const DOT = {
  green: 'bg-n-teal-9',
  amber: 'bg-n-amber-9',
  red: 'bg-n-ruby-9',
};

const TEXT = {
  green: 'text-n-teal-11',
  amber: 'text-n-amber-11',
  red: 'text-n-ruby-11',
};

const dotClass = computed(() => DOT[props.status] || 'bg-n-slate-8');
const textClass = computed(() => TEXT[props.status] || 'text-n-slate-10');

// Etiqueta legible: "vence en 2h 30m" / "vencido hace 1h 5m".
const label = computed(() => {
  if (props.status === 'none' || props.minutes === null) {
    return t('JABVOX_TICKETS.SLA.NO_DUE');
  }
  const abs = Math.abs(props.minutes);
  const hours = Math.floor(abs / 60);
  const mins = abs % 60;
  const parts = [];
  if (hours > 0) parts.push(`${hours}h`);
  parts.push(`${mins}m`);
  const human = parts.join(' ');
  return props.minutes < 0
    ? t('JABVOX_TICKETS.SLA.OVERDUE_BY', { time: human })
    : t('JABVOX_TICKETS.SLA.DUE_IN', { time: human });
});
</script>

<template>
  <span
    class="inline-flex items-center gap-1 text-xs font-medium whitespace-nowrap"
    :class="textClass"
    :title="label"
  >
    <span
      class="inline-block w-2 h-2 rounded-full"
      :class="dotClass"
      aria-hidden="true"
    />
    {{ label }}
  </span>
</template>
