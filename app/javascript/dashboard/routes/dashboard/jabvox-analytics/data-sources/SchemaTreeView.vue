<script setup>
import SchemaTreeNode from './SchemaTreeNode.vue';

defineProps({
  schema: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['view-data']);
</script>

<template>
  <div class="flex flex-col gap-2">
    <SchemaTreeNode
      v-for="node in schema"
      :key="node.name"
      :node="node"
      @view-data="emit('view-data', $event)"
    />
  </div>
</template>
