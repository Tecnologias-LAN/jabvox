<script setup>
import { computed } from 'vue';
import KanbanColumn from './KanbanColumn.vue';

const props = defineProps({
  board: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['card-click', 'moveConversation', 'moveLead']);

const stages = computed(() => props.board?.stages || []);

const onDrop = ({ conversationId, leadId, stageId }) => {
  if (leadId) {
    emit('moveLead', { leadId, stageId });
  } else {
    emit('moveConversation', { conversationId, stageId });
  }
};
</script>

<template>
  <div class="flex gap-3 h-full w-full overflow-x-auto pb-4 px-2 sm:px-4 pt-2">
    <KanbanColumn
      v-for="stageData in stages"
      :key="stageData.id"
      :stage="stageData"
      :conversations="stageData.conversations"
      :lead-cards="stageData.lead_cards || []"
      @card-click="emit('card-click', $event)"
      @drop="onDrop"
    />
  </div>
</template>
