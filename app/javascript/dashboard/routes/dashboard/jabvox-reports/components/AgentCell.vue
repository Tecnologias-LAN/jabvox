<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

defineProps({
  agent: { type: Object, required: true },
  size: { type: Number, default: 28 },
  compact: { type: Boolean, default: false },
});
</script>

<template>
  <div class="flex items-center gap-2.5 min-w-0">
    <Avatar
      :name="agent.name || agent.email || '?'"
      :src="agent.avatar_url"
      :size="size"
      rounded-full
    />
    <div v-if="!compact" class="min-w-0">
      <p class="font-medium text-n-slate-12 leading-tight truncate">
        {{ agent.name }}
      </p>
      <p class="text-xs text-n-slate-10 truncate">{{ agent.email }}</p>
    </div>
    <span
      v-else
      class="font-medium text-n-slate-12 text-xs truncate max-w-[120px]"
    >
      {{ agent.name }}
    </span>
  </div>
</template>
