<script setup>
import { computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Icon from 'next/icon/Icon.vue';

// Contenido del item "Solicitudes" en el sidebar: label + dos badges de conteo.
//   verde → pendientes creadas HOY
//   rojo  → pendientes vencidas de días anteriores
// Los counts vienen del store (endpoint /counts, que respeta el scope de permisos).
defineProps({
  label: { type: String, required: true },
  icon: { type: [String, Object], default: null },
});

const store = useStore();
const counts = useMapGetter('jabvoxTickets/getCounts');

const today = computed(() => Number(counts.value?.today) || 0);
const overduePrev = computed(() => Number(counts.value?.overdue_previous) || 0);

const fmt = n => (n > 99 ? '99+' : String(n));

let timer = null;
const refresh = () =>
  store.dispatch('jabvoxTickets/fetchCounts').catch(() => {});

onMounted(() => {
  refresh();
  // Refresco periódico ligero para mantener el badge vivo (cada 60s).
  timer = setInterval(refresh, 60000);
});
onBeforeUnmount(() => {
  if (timer) clearInterval(timer);
});
</script>

<template>
  <span v-if="icon" class="size-4 grid place-content-center rounded-full">
    <Icon :icon="icon" class="size-4 inline-block" />
  </span>
  <div class="flex-1 truncate min-w-0 text-sm">{{ label }}</div>
  <div class="flex items-center gap-1 shrink-0">
    <span
      v-if="today > 0"
      class="inline-grid h-5 min-w-5 place-items-center rounded-full px-1 text-xxs font-medium leading-3 bg-n-teal-3 text-n-teal-11"
      :title="$t('JABVOX_TICKETS.BADGE.TODAY')"
    >
      {{ fmt(today) }}
    </span>
    <span
      v-if="overduePrev > 0"
      class="inline-grid h-5 min-w-5 place-items-center rounded-full px-1 text-xxs font-medium leading-3 bg-n-ruby-3 text-n-ruby-11"
      :title="$t('JABVOX_TICKETS.BADGE.OVERDUE_PREVIOUS')"
    >
      {{ fmt(overduePrev) }}
    </span>
  </div>
</template>
