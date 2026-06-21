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

const emit = defineEmits(['select']);

const children = computed(() => props.folder.children || []);
const isSelected = computed(() => props.selectedId === props.folder.id);
</script>

<template>
  <div>
    <button
      type="button"
      class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm"
      :class="
        isSelected
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:bg-n-alpha-1'
      "
      :style="{ paddingLeft: `${depth * 12 + 8}px` }"
      @click="emit('select', folder.id)"
    >
      <span class="i-lucide-folder size-4 shrink-0" />
      <span class="truncate">{{ folder.name }}</span>
    </button>
    <FolderTreeNode
      v-for="child in children"
      :key="child.id"
      :folder="child"
      :selected-id="selectedId"
      :depth="depth + 1"
      @select="emit('select', $event)"
    />
  </div>
</template>
