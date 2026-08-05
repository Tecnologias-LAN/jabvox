<script setup>
import { onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';

// Contenedor del módulo de Tickets: carga permisos y categorías una vez, y expone
// el router-view de las sub-rutas (lista, detalle, métricas, categorías).
const store = useStore();

onMounted(() => {
  store.dispatch('jabvoxTickets/fetchPermissions');
  store.dispatch('jabvoxTickets/fetchCategories');
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <router-view />
  </div>
</template>
