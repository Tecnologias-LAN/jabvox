<script setup>
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  page: { type: Number, required: true },
  totalPages: { type: Number, required: true },
  rangeStart: { type: Number, required: true },
  rangeEnd: { type: Number, required: true },
  total: { type: Number, required: true },
  pageSizeOptions: { type: Array, default: () => [] },
});

const emit = defineEmits(['prev', 'next']);

// pageSize is a v-model so both the top and bottom bars stay in sync.
const pageSize = defineModel('pageSize', { type: Number, required: true });

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-3">
    <div class="flex items-center gap-2 text-xs text-n-slate-11">
      <span>{{ t('JABVOX_AUDIO.ANALYZER.PER_PAGE') }}</span>
      <div class="w-20">
        <Select v-model="pageSize" :options="pageSizeOptions" />
      </div>
      <span>
        {{
          t('JABVOX_AUDIO.ANALYZER.RANGE', {
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
      <span class="text-xs text-n-slate-11 tabular-nums">
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
