<script setup>
import { toRef } from 'vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useI18n } from 'vue-i18n';
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

const emit = defineEmits(['sendMessage', 'back']);

const { t } = useI18n();

// Field options + resolved values to auto-fill {{n}} variables from this lead.
const { fieldOptions, fieldValues } = useLeadTemplateFields(
  toRef(props, 'contactId')
);

const handleSendMessage = payload => {
  emit('sendMessage', payload);
};

const handleBack = () => {
  emit('back');
};
</script>

<template>
  <div class="flex flex-col gap-4 px-4 pt-6 pb-5 items-start w-[28.75rem]">
    <div class="w-full">
      <WhatsAppTemplateParser
        :template="template"
        :field-options="fieldOptions"
        :field-values="fieldValues"
        @send-message="handleSendMessage"
        @back="handleBack"
      >
        <template #actions="{ sendMessage, goBack, disabled }">
          <div class="flex gap-3 justify-between items-end w-full h-14">
            <Button
              :label="
                t(
                  'COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_OPTIONS.TEMPLATE_PARSER.BACK'
                )
              "
              color="slate"
              variant="faded"
              class="w-full font-medium"
              @click="goBack"
            />
            <Button
              :label="
                t(
                  'COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_OPTIONS.TEMPLATE_PARSER.SEND_MESSAGE'
                )
              "
              class="w-full font-medium"
              :disabled="disabled"
              @click="sendMessage"
            />
          </div>
        </template>
      </WhatsAppTemplateParser>
    </div>
  </div>
</template>
