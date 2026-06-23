import { ref, computed, watch } from 'vue';

// Client-side pagination shared by every list in the Customization screen so
// all tables paginate the same way (page size selector, range, prev/next).
// `source` is a ref/computed returning the full (already-filtered) array.
export function useClientPagination(source, { pageSize = 10 } = {}) {
  const size = ref(pageSize);
  const page = ref(1);

  const total = computed(() => source.value.length);
  const totalPages = computed(() =>
    Math.max(1, Math.ceil(total.value / size.value))
  );

  const paged = computed(() => {
    const start = (page.value - 1) * size.value;
    return source.value.slice(start, start + size.value);
  });

  const rangeStart = computed(() =>
    total.value === 0 ? 0 : (page.value - 1) * size.value + 1
  );
  const rangeEnd = computed(() =>
    Math.min(page.value * size.value, total.value)
  );

  // Keep the page in range when the data set shrinks (search, delete) or the
  // page size changes.
  watch([total, size], () => {
    if (page.value > totalPages.value) page.value = totalPages.value;
  });

  const goPrev = () => {
    if (page.value > 1) page.value -= 1;
  };
  const goNext = () => {
    if (page.value < totalPages.value) page.value += 1;
  };
  const reset = () => {
    page.value = 1;
  };

  return {
    page,
    pageSize: size,
    total,
    totalPages,
    paged,
    rangeStart,
    rangeEnd,
    goPrev,
    goNext,
    reset,
  };
}
