<script setup>
import { computed } from 'vue';

const props = defineProps({
  folder: {
    type: Object,
    required: true,
  },
  selectedId: {
    type: [Number, String, null],
    default: null,
  },
  depth: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['select', 'delete']);

const children = computed(() => props.folder.children || []);
const isSelected = computed(() => props.selectedId === props.folder.id);
</script>

<template>
  <div>
    <div
      class="group flex w-full items-center gap-2 rounded-lg pr-1 text-sm"
      :class="
        isSelected
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:bg-n-alpha-1'
      "
    >
      <button
        type="button"
        class="flex min-w-0 flex-1 items-center gap-2 px-2 py-1.5 text-left"
        :style="{ paddingLeft: `${depth * 12 + 8}px` }"
        @click="emit('select', folder.id)"
      >
        <span class="i-lucide-folder size-4 shrink-0" />
        <span class="truncate">{{ folder.nameJabvox || folder.name }}</span>
      </button>
      <button
        type="button"
        class="shrink-0 rounded p-1 text-n-slate-10 opacity-0 hover:bg-n-alpha-2 hover:text-n-ruby-11 focus:opacity-100 group-hover:opacity-100"
        :title="$t('JABVOX_ANALYTICS.FOLDERS.DELETE')"
        @click.stop="emit('delete', folder)"
      >
        <span class="i-lucide-trash-2 size-4" />
      </button>
    </div>
    <FolderTreeNode
      v-for="child in children"
      :key="child.id"
      :folder="child"
      :selected-id="selectedId"
      :depth="depth + 1"
      @select="emit('select', $event)"
      @delete="emit('delete', $event)"
    />
  </div>
</template>
