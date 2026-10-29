<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import AudioChip from 'next/message/chips/Audio.vue';
import StorageBlockedNotice from './StorageBlockedNotice.vue';
import { useMessageContext } from '../provider.js';

const { attachments } = useMessageContext();

const attachment = computed(() => {
  return attachments.value[0];
});

const storageBlocked = computed(
  () => attachment.value?.storageBlocked === true
);
</script>

<template>
  <BaseBubble class="bg-transparent" data-bubble-name="audio">
    <StorageBlockedNotice v-if="storageBlocked" file-type="audio" />
    <AudioChip
      v-else
      :attachment="attachment"
      class="p-2 text-n-slate-12 skip-context-menu"
    />
  </BaseBubble>
</template>
