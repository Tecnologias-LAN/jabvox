<script setup>
import TableWidget from './TableWidget.vue';

// v1: a pivot table renders as a flat table. A true pivot can be layered later.
defineProps({
  widget: {
    type: Object,
    required: true,
  },
  data: {
    type: Object,
    default: null,
  },
});
</script>

<template>
  <TableWidget :widget="widget" :data="data" />
</template>
