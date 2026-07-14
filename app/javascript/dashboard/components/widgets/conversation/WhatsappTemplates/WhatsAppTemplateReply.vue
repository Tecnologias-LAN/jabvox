<script setup>
import { toRef } from 'vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useLeadTemplateFields } from 'dashboard/composables/jabvox/useLeadTemplateFields';

const props = defineProps({
  template: {
    type: Object,
    default: () => ({}),
  },
  // Jabvox: contact whose lead fields can auto-fill template variables.
  contactId: {
    type: [Number, String],
    default: undefined,
  },
});

const emit = defineEmits(['sendMessage', 'resetTemplate']);

// Field options + resolved values to auto-fill {{n}} variables from this lead.
const { fieldOptions, fieldValues } = useLeadTemplateFields(
  toRef(props, 'contactId')
);

const handleSendMessage = payload => {
  emit('sendMessage', payload);
};

const handleResetTemplate = () => {
  emit('resetTemplate');
};
</script>

<template>
  <div class="w-full">
    <WhatsAppTemplateParser
      :template="template"
      :field-options="fieldOptions"
      :field-values="fieldValues"
      @send-message="handleSendMessage"
      @reset-template="handleResetTemplate"
    >
      <template #actions="{ sendMessage, resetTemplate, disabled }">
        <footer class="flex gap-2 justify-end">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('WHATSAPP_TEMPLATES.PARSER.GO_BACK_LABEL')"
            @click="resetTemplate"
          />
          <NextButton
            type="button"
            :label="$t('WHATSAPP_TEMPLATES.PARSER.SEND_MESSAGE_LABEL')"
            :disabled="disabled"
            @click="sendMessage"
          />
        </footer>
      </template>
    </WhatsAppTemplateParser>
  </div>
</template>
