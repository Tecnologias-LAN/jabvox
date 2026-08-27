<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { humanizeMinutes } from '../helper/ticketTime';

// Contador de SLA visual: verde / ámbar / rojo según cuánto falta para vencer.
// Recibe el semáforo (sla_status) y los minutos restantes (minutes_to_due) que ya
// calcula el backend, para no depender del reloj del cliente.
//   size='sm' → chip en línea (fila de la bandeja)
//   size='lg' → tarjeta con anillo grande (panel del detalle)
const props = defineProps({
  status: { type: String, default: 'none' }, // none | green | amber | red
  minutes: { type: Number, default: null },
  size: { type: String, default: 'sm' }, // sm | lg
});

const { t } = useI18n();

const DOT = { green: 'bg-n-teal-9', amber: 'bg-n-amber-9', red: 'bg-n-ruby-9' };
const TEXT = {
  green: 'text-n-teal-11',
  amber: 'text-n-amber-11',
  red: 'text-n-ruby-11',
};
const RING = {
  green: 'ring-n-teal-5 bg-n-teal-3',
  amber: 'ring-n-amber-5 bg-n-amber-3',
  red: 'ring-n-ruby-5 bg-n-ruby-3',
};

const dotClass = computed(() => DOT[props.status] || 'bg-n-slate-8');
const textClass = computed(() => TEXT[props.status] || 'text-n-slate-10');
const ringClass = computed(
  () => RING[props.status] || 'ring-n-weak bg-n-alpha-1'
);

const human = computed(() =>
  props.minutes === null ? '' : humanizeMinutes(Math.abs(props.minutes))
);

const label = computed(() => {
  if (props.status === 'none' || props.minutes === null) {
    return t('JABVOX_TICKETS.SLA.NO_DUE');
  }
  return props.minutes < 0
    ? t('JABVOX_TICKETS.SLA.OVERDUE_BY', { time: human.value })
    : t('JABVOX_TICKETS.SLA.DUE_IN', { time: human.value });
});

const caption = computed(() => {
  if (props.status === 'none' || props.minutes === null) return '';
  return props.minutes < 0
    ? t('JABVOX_TICKETS.SLA.OVERDUE_CAPTION')
    : t('JABVOX_TICKETS.SLA.REMAINING_CAPTION');
});
</script>

<template>
  <!-- Variante compacta (fila) -->
  <span
    v-if="size === 'sm'"
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

  <!-- Variante grande (panel de detalle) -->
  <div
    v-else
    class="flex items-center gap-3 p-3 rounded-2xl ring-1"
    :class="ringClass"
  >
    <span
      class="flex items-center justify-center w-11 h-11 rounded-xl bg-n-solid-1/60"
      aria-hidden="true"
    >
      <span class="i-lucide-timer w-5 h-5" :class="textClass" />
    </span>
    <div class="min-w-0">
      <p class="text-sm font-semibold leading-tight" :class="textClass">
        {{ status === 'none' ? label : human }}
      </p>
      <p class="text-xs text-n-slate-11 truncate">
        {{ caption || t('JABVOX_TICKETS.SLA.NO_DUE') }}
      </p>
    </div>
  </div>
</template>
