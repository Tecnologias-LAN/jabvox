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
    rows.value.map(row => ({
      name: String(row[0]),
      value: Number(row[1] ?? 0),
    }))
  );

  const categoryLabel = computed(() => columns.value[0] || '');
  const valueLabel = computed(() => columns.value[1] || '');

  // One series per numeric column after the category (column 0). Lets a chart
  // draw multiple lines/bars when a report section returns several measures
  // (e.g. CDR series: date, total, analyzed, passed). Falls back to a single
  // series when there is only one value column, so existing widgets are
  // unaffected. Columns whose values are non-numeric are skipped.
  const series = computed(() => {
    const cols = columns.value;
    const data = rows.value;
    if (cols.length <= 1 || data.length === 0) {
      return [{ name: valueLabel.value, data: values.value }];
    }
    const out = [];
    for (let c = 1; c < cols.length; c += 1) {
      const colValues = data.map(row => Number(row[c] ?? 0));
      const isNumeric = data.every(row => !Number.isNaN(Number(row[c])));
      if (isNumeric) out.push({ name: cols[c], data: colValues });
    }
    return out.length ? out : [{ name: valueLabel.value, data: values.value }];
  });

  return {
    columns,
    rows,
    hasData,
    categories,
    values,
    series,
    pairs,
    categoryLabel,
    valueLabel,
  };
}
