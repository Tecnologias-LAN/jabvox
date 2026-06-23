<script setup>
import Input from 'dashboard/components-next/input/Input.vue';

defineProps({
  placeholder: { type: String, default: '' },
});

const model = defineModel({ type: String, default: '' });
</script>

<template>
  <div class="relative w-full sm:w-64">
    <Input
      v-model="model"
      :placeholder="placeholder"
      custom-input-class="!pl-9"
    >
      <template #prefix>
        <span
          class="i-lucide-search size-4 text-n-slate-10 absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none"
        />
      </template>
    </Input>
  </div>
</template>
