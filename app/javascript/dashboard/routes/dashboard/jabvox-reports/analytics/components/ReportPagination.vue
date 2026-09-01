<script setup>
import { useI18n } from 'vue-i18n';
import { PAGE_SIZES } from '../reportMetrics.js';

// Cursor pagination controls. Because the API is keyset (no page numbers), this
// exposes page-size selection, a "load more" action while a cursor remains, and
// the total count (marked approximate when the backend capped it).
defineProps({
  perPage: { type: Number, default: 25 },
  totalCount: { type: Number, default: 0 },
  totalIsApprox: { type: Boolean, default: false },
  loadedCount: { type: Number, default: 0 },
  hasMore: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});
const emit = defineEmits(['update:perPage', 'load-more']);

const { t } = useI18n();
const numberFmt = new Intl.NumberFormat('es-CO');
</script>

<template>
  <div
    class="flex flex-wrap items-center justify-between gap-3 py-3 text-sm text-n-slate-11"
  >
    <div class="flex items-center gap-2">
      <span>{{ t('JABVOX_REPORTS.ANALYTICS.PER_PAGE') }}</span>
      <select
        :value="perPage"
        class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
        @change="emit('update:perPage', Number($event.target.value))"
      >
        <option v-for="size in PAGE_SIZES" :key="size" :value="size">
          {{ size }}
        </option>
      </select>
    </div>

    <div class="flex items-center gap-3">
      <span>
        {{ numberFmt.format(loadedCount) }}
        {{ t('JABVOX_REPORTS.ANALYTICS.OF') }}
        {{ totalIsApprox ? '≥\xa0' : '' }}{{ numberFmt.format(totalCount) }}
      </span>
      <button
        v-if="hasMore"
        type="button"
        :disabled="loading"
        class="flex items-center gap-1.5 rounded-lg border border-n-weak px-3 py-1.5 text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50"
        @click="emit('load-more')"
      >
        <span
          v-if="loading"
          class="i-lucide-loader-circle size-4 animate-spin"
        />
        <span v-else class="i-lucide-chevron-down size-4" />
        {{ t('JABVOX_REPORTS.ANALYTICS.LOAD_MORE') }}
      </button>
    </div>
  </div>
</template>
