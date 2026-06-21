<script setup>
import { computed } from 'vue';
import AnalyticsDataTable from '../../data-sources/AnalyticsDataTable.vue';

const props = defineProps({
  data: {
    type: Object,
    default: null,
  },
});

const columns = computed(() => props.data?.columns || []);

// AnalyticsDataTable expects row objects keyed by column name; the widget data
// returns rows as arrays aligned to columns, so map them across.
const rows = computed(() => {
  const cols = columns.value;
  return (props.data?.rows || []).map(row => {
    const obj = {};
    cols.forEach((name, index) => {
      obj[name] = row[index];
    });
    return obj;
  });
});
</script>

<template>
  <AnalyticsDataTable :rows="rows" :columns="columns" />
</template>
