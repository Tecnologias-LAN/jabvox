<script setup>
// Registros del contacto: sus tablas personalizadas de varias filas (Asesorías, Casos…).
// Lo usan Kanban / Conversaciones / Panel de contacto, que solo conocen el contacto.
//
// Antes resolvía primero el LEAD que respaldaba al contacto y pedía las filas de ese lead;
// un contacto sin lead se quedaba sin registros aunque las filas pudieran colgar de él. Como
// las filas ya cuelgan del contacto, el rodeo sobra y el panel funciona para cualquier
// contacto.
import JabvoxLeadTableRows from './JabvoxLeadTableRows.vue';

defineProps({
  contactId: { type: [Number, String], default: null },
});
</script>

<template>
  <JabvoxLeadTableRows v-if="contactId" :contact-id="contactId" />
</template>
