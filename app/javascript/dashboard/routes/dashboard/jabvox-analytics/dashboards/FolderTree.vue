<script setup>
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import { useAnalyticsDashboardsStore } from 'dashboard/stores/jabvox/analytics/dashboards';
import FolderTreeNode from './FolderTreeNode.vue';

defineProps({
  selectedId: {
    type: [Number, String, null],
    default: null,
  },
});

const emit = defineEmits(['select', 'delete']);

const { t } = useI18n();
const store = useAnalyticsDashboardsStore();
const { folderTree } = storeToRefs(store);
</script>

<template>
  <nav class="flex flex-col gap-0.5">
    <button
      type="button"
      class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm"
      :class="
        selectedId === null
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:bg-n-alpha-1'
      "
      @click="emit('select', null)"
    >
      <span class="i-lucide-layout-dashboard size-4 shrink-0" />
      <span class="truncate">{{
        t('JABVOX_ANALYTICS.DASHBOARDS.ALL_FOLDERS')
      }}</span>
    </button>
    <FolderTreeNode
      v-for="folder in folderTree"
      :key="folder.id"
      :folder="folder"
      :selected-id="selectedId"
      @select="emit('select', $event)"
      @delete="emit('delete', $event)"
    />
  </nav>
</template>
