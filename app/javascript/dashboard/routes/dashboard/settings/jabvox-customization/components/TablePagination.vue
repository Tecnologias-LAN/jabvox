<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Reusable pagination bar for every list in the Customization screen.
const props = defineProps({
  page: { type: Number, required: true },
  totalPages: { type: Number, required: true },
  rangeStart: { type: Number, required: true },
  rangeEnd: { type: Number, required: true },
  total: { type: Number, required: true },
  pageSizeOptions: { type: Array, default: () => [5, 10, 25, 50] },
});

const emit = defineEmits(['prev', 'next']);

// v-model so multiple bars (top/bottom) stay in sync.
const pageSize = defineModel('pageSize', { type: Number, required: true });

const { t } = useI18n();

const sizeOptions = computed(() =>
  props.pageSizeOptions.map(n => ({ value: n, label: String(n) }))
);
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-3">
    <div class="flex items-center gap-2 text-xs text-n-slate-11">
      <span>{{ t('JABVOX_CUSTOMIZATION.PAGINATION.PER_PAGE') }}</span>
      <div class="w-20">
        <Select v-model="pageSize" :options="sizeOptions" />
      </div>
      <span class="tabular-nums">
        {{
          t('JABVOX_CUSTOMIZATION.PAGINATION.RANGE', {
            from: rangeStart,
            to: rangeEnd,
            total,
          })
        }}
      </span>
    </div>
    <div class="flex items-center gap-2">
      <Button
        icon="i-lucide-chevron-left"
        variant="outline"
        color="slate"
        size="sm"
        :disabled="page <= 1"
        @click="emit('prev')"
      />
      <span
        class="text-xs text-n-slate-11 tabular-nums min-w-[3rem] text-center"
      >
        {{ page }} / {{ totalPages }}
      </span>
      <Button
        icon="i-lucide-chevron-right"
        variant="outline"
        color="slate"
        size="sm"
        :disabled="page >= totalPages"
        @click="emit('next')"
      />
    </div>
  </div>
</template>
