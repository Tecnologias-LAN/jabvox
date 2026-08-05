<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import TicketBadges from './TicketBadges.vue';
import SlaCountdown from './SlaCountdown.vue';

// Tablero Kanban por estado. Cada columna es un estado; arrastrar una tarjeta a otra
// columna emite 'change-status' (el contenedor llama al endpoint change_status).
// La lógica de datos vive en el contenedor; aquí solo presentación + D&D.
const props = defineProps({
  tickets: { type: Array, default: () => [] },
});
const emit = defineEmits(['open', 'changeStatus']);

const { t } = useI18n();

// Columnas visibles del tablero (los estados operativos principales).
const COLUMNS = [
  { key: 'new_ticket', icon: 'i-lucide-circle-dot' },
  { key: 'assigned', icon: 'i-lucide-user-check' },
  { key: 'in_progress', icon: 'i-lucide-loader' },
  { key: 'on_hold', icon: 'i-lucide-pause' },
  { key: 'resolved', icon: 'i-lucide-check-circle-2' },
];

// Agrupa los tickets por estado. Devuelve arrays independientes por columna
// (vuedraggable muta el array de destino, por eso cada columna tiene el suyo).
const columnLists = computed(() => {
  const map = {};
  COLUMNS.forEach(c => {
    map[c.key] = [];
  });
  props.tickets.forEach(tk => {
    if (map[tk.status]) map[tk.status].push(tk);
  });
  return map;
});

// Al soltar en una columna: si el ticket cambió de estado, avisa al contenedor.
const onDrop = (targetStatus, event) => {
  const moved = event?.added?.element;
  if (moved && moved.status !== targetStatus) {
    emit('changeStatus', { id: moved.id, status: targetStatus });
  }
};
</script>

<template>
  <div class="flex-1 overflow-x-auto overflow-y-hidden px-4 py-4">
    <div class="flex gap-3 h-full min-w-max">
      <section
        v-for="col in COLUMNS"
        :key="col.key"
        class="flex flex-col w-72 shrink-0 rounded-2xl bg-n-alpha-1 border border-n-weak"
      >
        <header
          class="flex items-center justify-between px-3 py-2.5 border-b border-n-weak"
        >
          <span
            class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
          >
            <span
              :class="`${col.icon} w-4 h-4 text-n-slate-10`"
              aria-hidden="true"
            />
            {{ t(`JABVOX_TICKETS.STATUS.${col.key.toUpperCase()}`) }}
          </span>
          <span
            class="text-xs font-medium px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11 tabular-nums"
          >
            {{ columnLists[col.key].length }}
          </span>
        </header>

        <Draggable
          :list="columnLists[col.key]"
          group="tickets"
          item-key="id"
          animation="180"
          ghost-class="tk-ghost"
          class="flex-1 overflow-y-auto p-2 flex flex-col gap-2 min-h-[120px]"
          @change="onDrop(col.key, $event)"
        >
          <template #item="{ element }">
            <article
              class="rounded-xl bg-n-solid-1 border border-n-weak p-3 cursor-pointer shadow-sm hover:shadow-md hover:border-n-strong transition-all"
              :class="element.overdue ? 'ring-1 ring-n-ruby-5' : ''"
              @click="emit('open', element.id)"
            >
              <div class="flex items-center justify-between mb-1.5">
                <span class="text-xs text-n-slate-10 tabular-nums">
                  {{ `#${element.display_id}` }}
                </span>
                <TicketBadges kind="priority" :value="element.priority" />
              </div>
              <p class="text-sm font-medium text-n-slate-12 line-clamp-2 mb-2">
                {{ element.title }}
              </p>
              <div class="flex items-center justify-between gap-2">
                <TicketBadges kind="type" :value="element.category_type" />
                <SlaCountdown
                  :status="element.sla_status"
                  :minutes="element.minutes_to_due"
                />
              </div>
            </article>
          </template>
        </Draggable>
      </section>
    </div>
  </div>
</template>

<style scoped>
.tk-ghost {
  opacity: 0.5;
}
.tk-ghost > article {
  border-style: dashed;
}
</style>
