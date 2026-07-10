<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();
const getters = useStoreGetters();

const reassignToId = ref(null);

const agentList = computed(() =>
  getters['agents/getAgents'].value.filter(a => a.id !== props.agent.id)
);

const description = computed(() =>
  t('AGENT_MGMT.DELETE.REASSIGN.DESCRIPTION', { name: props.agent.name })
);

const onConfirm = () => {
  emit('confirm', reassignToId.value || null);
};
</script>

<template>
  <div class="flex flex-col gap-6 p-6 w-full max-w-md">
    <div class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-1">
        <h3 class="text-heading-2 text-n-slate-12">
          {{ t('AGENT_MGMT.DELETE.REASSIGN.TITLE') }}
        </h3>
        <p class="text-body-main text-n-slate-11" v-html="description" />
      </div>
      <button
        type="button"
        class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 shrink-0"
        @click="$emit('close')"
      >
        <span class="i-lucide-x size-5" />
      </button>
    </div>

    <div class="flex flex-col gap-2">
      <label class="text-body-main font-medium text-n-slate-12">
        {{ t('AGENT_MGMT.DELETE.REASSIGN.REASSIGN_LABEL') }}
      </label>
      <select
        v-model="reassignToId"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-body-main text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
      >
        <option :value="null">
          {{ t('AGENT_MGMT.DELETE.REASSIGN.REASSIGN_PLACEHOLDER') }}
        </option>
        <option v-for="a in agentList" :key="a.id" :value="a.id">
          {{ a.name }}
        </option>
      </select>
    </div>

    <div class="flex justify-end gap-3">
      <Button
        :label="t('AGENT_MGMT.DELETE.REASSIGN.CANCEL')"
        ghost
        @click="$emit('close')"
      />
      <Button
        :label="t('AGENT_MGMT.DELETE.REASSIGN.CONFIRM')"
        class="!bg-n-ruby-9 hover:!bg-n-ruby-10 !text-white"
        @click="onConfirm"
      />
    </div>
  </div>
</template>
