<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

// Agentes de la cuenta para elegir a quién escalar la conversación (handoff).
const verifiedAgents = useMapGetter('agents/getVerifiedAgents');

const initialState = {
  name: '',
  description: '',
  productName: '',
  features: {
    conversationFaqs: false,
    memories: false,
    citations: false,
    contactAttributes: false,
  },
  agendaTools: {
    checkAvailability: true,
    scheduleAppointment: true,
    listBoards: true,
    createTask: true,
  },
  handoffAgentIds: [],
};

const state = reactive({ ...initialState });

const toggleHandoffAgent = agentId => {
  const id = Number(agentId);
  if (state.handoffAgentIds.includes(id)) {
    state.handoffAgentIds = state.handoffAgentIds.filter(a => a !== id);
  } else {
    state.handoffAgentIds = [...state.handoffAgentIds, id];
  }
};

const validationRules = {
  name: { required, minLength: minLength(1) },
  description: { required, minLength: minLength(1) },
  productName: { required, minLength: minLength(1) },
};

const v$ = useVuelidate(validationRules, state);

const getErrorMessage = field => {
  return v$.value[field].$error ? v$.value[field].$errors[0].$message : '';
};

const formErrors = computed(() => ({
  name: getErrorMessage('name'),
  description: getErrorMessage('description'),
  productName: getErrorMessage('productName'),
}));

const updateStateFromAssistant = assistant => {
  const { config = {} } = assistant;
  state.name = assistant.name;
  state.description = assistant.description;
  state.productName = config.product_name;
  state.features = {
    conversationFaqs: config.feature_faq || false,
    memories: config.feature_memory || false,
    citations: config.feature_citation || false,
    contactAttributes: config.feature_contact_attributes || false,
  };
  // Tools de agenda/tareas: activas por defecto (solo false las desactiva).
  state.agendaTools = {
    checkAvailability: config.feature_check_availability !== false,
    scheduleAppointment: config.feature_schedule_appointment !== false,
    listBoards: config.feature_list_boards !== false,
    createTask: config.feature_create_task !== false,
  };
  state.handoffAgentIds = (config.handoff_agent_ids || []).map(Number);
};

const handleBasicInfoUpdate = async () => {
  const result = await Promise.all([
    v$.value.name.$validate(),
    v$.value.description.$validate(),
    v$.value.productName.$validate(),
  ]).then(results => results.every(Boolean));
  if (!result) return;

  const payload = {
    name: state.name,
    description: state.description,
    config: {
      ...props.assistant.config,
      product_name: state.productName,
      feature_faq: state.features.conversationFaqs,
      feature_memory: state.features.memories,
      feature_citation: state.features.citations,
      feature_contact_attributes: state.features.contactAttributes,
      feature_check_availability: state.agendaTools.checkAvailability,
      feature_schedule_appointment: state.agendaTools.scheduleAppointment,
      feature_list_boards: state.agendaTools.listBoards,
      feature_create_task: state.agendaTools.createTask,
      handoff_agent_ids: state.handoffAgentIds,
    },
  };

  emit('submit', payload);
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) updateStateFromAssistant(newAssistant);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <Input
      v-model="state.name"
      :label="t('CAPTAIN.ASSISTANTS.FORM.NAME.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.NAME.PLACEHOLDER')"
      :message="formErrors.name"
      :message-type="formErrors.name ? 'error' : 'info'"
    />

    <Input
      v-model="state.productName"
      :label="t('CAPTAIN.ASSISTANTS.FORM.PRODUCT_NAME.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.PRODUCT_NAME.PLACEHOLDER')"
      :message="formErrors.productName"
      :message-type="formErrors.productName ? 'error' : 'info'"
    />

    <Editor
      v-model="state.description"
      :max-length="500"
      :label="t('CAPTAIN.ASSISTANTS.FORM.DESCRIPTION.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.DESCRIPTION.PLACEHOLDER')"
      :message="formErrors.description"
      :message-type="formErrors.description ? 'error' : 'info'"
      class="z-0"
    />

    <div class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.TITLE') }}
      </label>
      <div class="flex flex-col gap-2">
        <label class="flex items-center gap-2">
          <input v-model="state.features.conversationFaqs" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONVERSATION_FAQS') }}
        </label>
        <label class="flex items-center gap-2">
          <input v-model="state.features.memories" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_MEMORIES') }}
        </label>
        <label class="flex items-center gap-2">
          <input v-model="state.features.citations" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CITATIONS') }}
        </label>
        <label class="flex items-center gap-2">
          <input v-model="state.features.contactAttributes" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONTACT_ATTRIBUTES') }}
        </label>
      </div>
    </div>

    <div class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.AGENDA_TOOLS.TITLE') }}
      </label>
      <p class="text-xs text-n-slate-11 -mt-1">
        {{ t('CAPTAIN.ASSISTANTS.FORM.AGENDA_TOOLS.DESCRIPTION') }}
      </p>
      <div class="flex flex-col gap-2">
        <label class="flex items-center gap-2">
          <input
            v-model="state.agendaTools.checkAvailability"
            type="checkbox"
          />
          {{ t('CAPTAIN.ASSISTANTS.FORM.AGENDA_TOOLS.CHECK_AVAILABILITY') }}
        </label>
        <label class="flex items-center gap-2">
          <input
            v-model="state.agendaTools.scheduleAppointment"
            type="checkbox"
          />
          {{ t('CAPTAIN.ASSISTANTS.FORM.AGENDA_TOOLS.SCHEDULE_APPOINTMENT') }}
        </label>
        <label class="flex items-center gap-2">
          <input v-model="state.agendaTools.listBoards" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.AGENDA_TOOLS.LIST_BOARDS') }}
        </label>
        <label class="flex items-center gap-2">
          <input v-model="state.agendaTools.createTask" type="checkbox" />
          {{ t('CAPTAIN.ASSISTANTS.FORM.AGENDA_TOOLS.CREATE_TASK') }}
        </label>
      </div>
    </div>

    <div class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.HANDOFF.TITLE') }}
      </label>
      <p class="text-xs text-n-slate-11 -mt-1">
        {{ t('CAPTAIN.ASSISTANTS.FORM.HANDOFF.DESCRIPTION') }}
      </p>
      <div
        v-if="verifiedAgents.length"
        class="flex flex-col gap-2 max-h-56 overflow-y-auto rounded-xl border border-n-weak p-3"
      >
        <label
          v-for="agent in verifiedAgents"
          :key="agent.id"
          class="flex items-center gap-2"
        >
          <input
            type="checkbox"
            :checked="state.handoffAgentIds.includes(Number(agent.id))"
            @change="toggleHandoffAgent(agent.id)"
          />
          <span class="text-sm text-n-slate-12">{{ agent.name }}</span>
          <span class="text-xs text-n-slate-10">{{ agent.email }}</span>
        </label>
      </div>
      <p v-else class="text-xs text-n-slate-10 italic">
        {{ t('CAPTAIN.ASSISTANTS.FORM.HANDOFF.NO_AGENTS') }}
      </p>
      <p class="text-xs text-n-slate-10">
        {{ t('CAPTAIN.ASSISTANTS.FORM.HANDOFF.HELP') }}
      </p>
    </div>

    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleBasicInfoUpdate"
      />
    </div>
  </div>
</template>
