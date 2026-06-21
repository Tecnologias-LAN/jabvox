import { computed } from 'vue';

// Shared helpers for chart widgets. Most visual queries return [dimension, measure]
// rows aligned to `columns`. These computeds expose the category axis and the
// numeric series in a consistent shape.
export function useWidgetData(dataRef) {
  const columns = computed(() => dataRef.value?.columns || []);
  const rows = computed(() => dataRef.value?.rows || []);
  const hasData = computed(() => rows.value.length > 0);

  const categories = computed(() => rows.value.map(row => row[0]));
  const values = computed(() => rows.value.map(row => Number(row[1] ?? 0)));

  // [{ name, value }] pairs, handy for pie/funnel/treemap.
  const pairs = computed(() =>
    rows.value.map(row => ({ name: String(row[0]), value: Number(row[1] ?? 0) }))
  );

  const categoryLabel = computed(() => columns.value[0] || '');
  const valueLabel = computed(() => columns.value[1] || '');

  return {
    columns,
    rows,
    hasData,
    categories,
    values,
    pairs,
    categoryLabel,
    valueLabel,
  };
}
