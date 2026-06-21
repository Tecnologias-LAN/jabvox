<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ColumnList from './ColumnList.vue';

defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['view-data']);

const { t } = useI18n();

const expanded = ref(false);

const toggle = () => {
  expanded.value = !expanded.value;
};
</script>

<template>
  <div class="rounded-lg border border-n-weak">
    <div class="flex items-center gap-2 px-3 py-2">
      <button
        type="button"
        class="flex min-w-0 flex-1 items-center gap-2 text-left"
        @click="toggle"
      >
        <span
          class="size-4 shrink-0 text-n-slate-10"
          :class="expanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
        />
        <span
          class="size-4 shrink-0 text-n-slate-11"
          :class="node.type === 'view' ? 'i-lucide-eye' : 'i-lucide-table-2'"
        />
        <span class="truncate text-sm font-medium text-n-slate-12">
          {{ node.name }}
        </span>
      </button>
      <button
        type="button"
        class="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-12"
        @click="emit('view-data', node.name)"
      >
        <span class="i-lucide-list size-4" />
        {{ t('JABVOX_ANALYTICS.SCHEMA.VIEW_DATA') }}
      </button>
    </div>
    <div v-if="expanded" class="border-t border-n-weak px-3 py-2">
      <ColumnList :columns="node.columns || []" />
    </div>
  </div>
</template>
