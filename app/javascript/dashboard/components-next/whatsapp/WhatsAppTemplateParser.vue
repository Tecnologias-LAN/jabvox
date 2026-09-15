<script setup>
/**
 * This component handles parsing and sending WhatsApp message templates.
 * It works as follows:
 * 1. Displays the template text with variable placeholders.
 * 2. Generates input fields for each variable in the template.
 * 3. Validates that all variables are filled before sending.
 * 4. Replaces placeholders with user-provided values.
 * 5. Emits events to send the processed message or reset the template.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { requiredIf } from '@vuelidate/validators';
import { useI18n } from 'vue-i18n';

import Input from 'dashboard/components-next/input/Input.vue';
import {
  buildTemplateParameters,
  allKeysRequired,
  replaceTemplateVariables,
  isWhatsAppComplete,
  DEFAULT_LANGUAGE,
  DEFAULT_CATEGORY,
  COMPONENT_TYPES,
  MEDIA_FORMATS,
  findComponentByType,
} from 'dashboard/helper/templateHelper';

const props = defineProps({
  template: {
    type: Object,
    default: () => ({}),
    validator: value => {
      if (!value || typeof value !== 'object') return false;
      if (!value.components || !Array.isArray(value.components)) return false;
      return true;
    },
  },
  // Jabvox opt-in: when provided, each body variable gets a "use a field" selector
  // that auto-fills its value from the contact/lead. Shape: [{ value, label }].
  // Optional map { fieldKey: value } used to resolve the chosen field to a value.
  // When both are empty the component behaves exactly like upstream (manual input).
  fieldOptions: {
    type: Array,
    default: () => [],
  },
  fieldValues: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['sendMessage', 'resetTemplate', 'back']);

const { t } = useI18n();

const processedParams = ref({});

// Jabvox: which lead field was chosen to fill each body variable ({ key: fieldValue }).
const variableFieldMap = ref({});
const showFieldMapping = computed(() => (props.fieldOptions || []).length > 0);

// When a field is picked for a body variable, write its resolved value into the
// same processedParams.body[key] the manual input uses, so nothing else changes.
const onPickField = (key, fieldValue) => {
  variableFieldMap.value[key] = fieldValue;
  if (!processedParams.value.body) return;
  processedParams.value.body[key] = fieldValue
    ? `${props.fieldValues?.[fieldValue] ?? ''}`
    : '';
};

const languageLabel = computed(() => {
  return `${t('WHATSAPP_TEMPLATES.PARSER.LANGUAGE')}: ${props.template.language || DEFAULT_LANGUAGE}`;
});

const categoryLabel = computed(() => {
  return `${t('WHATSAPP_TEMPLATES.PARSER.CATEGORY')}: ${props.template.category || DEFAULT_CATEGORY}`;
});

const headerComponent = computed(() => {
  return findComponentByType(props.template, COMPONENT_TYPES.HEADER);
});

const bodyComponent = computed(() => {
  return findComponentByType(props.template, COMPONENT_TYPES.BODY);
});

const bodyText = computed(() => {
  return bodyComponent.value?.text || '';
});

const hasMediaHeader = computed(() =>
  MEDIA_FORMATS.includes(headerComponent.value?.format)
);

const formatType = computed(() => {
  const format = headerComponent.value?.format;
  return format ? format.charAt(0) + format.slice(1).toLowerCase() : '';
});

const isDocumentTemplate = computed(() => {
  return headerComponent.value?.format?.toLowerCase() === 'document';
});

const hasVariables = computed(() => {
  return bodyText.value?.match(/{{([^}]+)}}/g) !== null;
});

const renderedTemplate = computed(() => {
  return replaceTemplateVariables(bodyText.value, processedParams.value);
});

// FLOW buttons carry no agent-supplied parameter (see initializeTemplateParameters);
// only URL/COPY_CODE buttons need an input here.
const fillableButtons = computed(() => {
  return (processedParams.value.buttons || [])
    .map((button, index) => ({ button, index }))
    .filter(({ button }) => button && button.type !== 'flow');
});

// Completeness validation is shared with the mobile app via @chatwoot/utils.
const isFormInvalid = computed(
  () => !isWhatsAppComplete(props.template, processedParams.value)
);

const v$ = useVuelidate(
  {
    processedParams: {
      requiredIfKeysPresent: requiredIf(hasVariables),
      allKeysRequired,
    },
  },
  { processedParams }
);

// URL de EJEMPLO del media que Meta guarda en la plantilla aprobada (header_handle[0]).
// Sirve para prellenar el campo y que no haya que pegar la URL a mano. El backend de
// Jabvox la resuelve a un media_id al enviar, así que basta con esta.
const templateExampleMediaUrl = computed(() => {
  const ex = headerComponent.value?.example || {};
  const handle = ex.header_handle || ex.header_url || ex.header_handle_url;
  if (Array.isArray(handle)) return handle[0] || '';
  return handle || '';
});

const initializeTemplateParameters = () => {
  processedParams.value = buildTemplateParameters(
    props.template,
    hasMediaHeader.value
  );
  // Prellena la media del header con el ejemplo aprobado de la plantilla, para no
  // pedir la URL a mano (el backend la convierte en media_id al enviar).
  if (hasMediaHeader.value && templateExampleMediaUrl.value) {
    processedParams.value.header ??= {};
    if (!processedParams.value.header.media_url) {
      processedParams.value.header.media_url = templateExampleMediaUrl.value;
    }
  }
  variableFieldMap.value = {};
};

const updateMediaUrl = value => {
  processedParams.value.header ??= {};
  processedParams.value.header.media_url = value;
};

const updateMediaName = value => {
  processedParams.value.header ??= {};
  processedParams.value.header.media_name = value;
};

const sendMessage = () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  const { name, category, language, namespace } = props.template;

  const payload = {
    message: renderedTemplate.value,
    templateParams: {
      name,
      category,
      language,
      namespace,
      processed_params: processedParams.value,
    },
  };
  emit('sendMessage', payload);
};

const resetTemplate = () => {
  emit('resetTemplate');
};

const goBack = () => {
  emit('back');
};

onMounted(initializeTemplateParameters);

watch(
  () => props.template,
  () => {
    initializeTemplateParameters();
    v$.value.$reset();
  },
  { deep: true }
);

defineExpose({
  processedParams,
  hasVariables,
  hasMediaHeader,
  isDocumentTemplate,
  headerComponent,
  renderedTemplate,
  v$,
  updateMediaUrl,
  updateMediaName,
  sendMessage,
  resetTemplate,
  goBack,
});
</script>

<template>
  <div>
    <div class="flex flex-col gap-4 p-4 mb-4 rounded-lg bg-n-alpha-black2">
      <div class="flex justify-between items-center">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ template.name }}
        </h3>
        <span class="text-xs text-n-slate-11">
          {{ languageLabel }}
        </span>
      </div>

      <div class="flex flex-col gap-2">
        <div class="rounded-md">
          <div class="text-sm whitespace-pre-wrap text-n-slate-12">
            {{ renderedTemplate }}
          </div>
        </div>
      </div>

      <div class="text-xs text-n-slate-11">
        {{ categoryLabel }}
      </div>
    </div>

    <div v-if="hasVariables || hasMediaHeader">
      <div v-if="hasMediaHeader" class="mb-4">
        <p class="mb-2.5 text-sm font-semibold">
          {{
            $t('WHATSAPP_TEMPLATES.PARSER.MEDIA_HEADER_LABEL', {
              type: formatType,
            }) || `${formatType} Header`
          }}
        </p>
        <div class="flex items-center mb-2.5">
          <Input
            :model-value="processedParams.header?.media_url || ''"
            type="url"
            class="flex-1"
            :placeholder="
              t('WHATSAPP_TEMPLATES.PARSER.MEDIA_URL_LABEL', {
                type: formatType,
              })
            "
            @update:model-value="updateMediaUrl"
          />
        </div>
        <div v-if="isDocumentTemplate" class="flex items-center mb-2.5">
          <Input
            :model-value="processedParams.header?.media_name || ''"
            type="text"
            class="flex-1"
            :placeholder="
              t('WHATSAPP_TEMPLATES.PARSER.DOCUMENT_NAME_PLACEHOLDER')
            "
            @update:model-value="updateMediaName"
          />
        </div>
      </div>

      <!-- Body Variables Section -->
      <div v-if="processedParams.body">
        <p class="mb-2.5 text-sm font-semibold">
          {{ $t('WHATSAPP_TEMPLATES.PARSER.VARIABLES_LABEL') }}
        </p>
        <div
          v-for="(variable, key) in processedParams.body"
          :key="`body-${key}`"
          class="flex flex-col gap-1.5 mb-2.5"
        >
          <div class="flex items-center gap-2">
            <!-- Jabvox opt-in: pick a contact/lead field to auto-fill this variable -->
            <select
              v-if="showFieldMapping"
              :value="variableFieldMap[key] || ''"
              class="reset-base shrink-0 max-w-[45%] text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-2"
              @change="onPickField(key, $event.target.value)"
            >
              <option value="">
                {{ $t('WHATSAPP_TEMPLATES.PARSER.VARIABLE_MANUAL') }}
              </option>
              <option
                v-for="opt in fieldOptions"
                :key="opt.value"
                :value="opt.value"
              >
                {{ opt.label }}
              </option>
            </select>
            <Input
              v-model="processedParams.body[key]"
              type="text"
              class="flex-1"
              :placeholder="
                t('WHATSAPP_TEMPLATES.PARSER.VARIABLE_PLACEHOLDER', {
                  variable: key,
                })
              "
            />
          </div>
        </div>
      </div>

      <!-- Button Variables Section. FLOW buttons need no agent input — Meta
           requires their component unconditionally, but it carries no
           user-supplied parameter, so they're built into processedParams for
           the send but hidden from this list. -->
      <div v-if="fillableButtons.length">
        <p class="mb-2.5 text-sm font-semibold">
          {{ t('WHATSAPP_TEMPLATES.PARSER.BUTTON_PARAMETERS') }}
        </p>
        <div
          v-for="{ index } in fillableButtons"
          :key="`button-${index}`"
          class="flex items-center mb-2.5"
        >
          <Input
            v-model="processedParams.buttons[index].parameter"
            type="text"
            class="flex-1"
            :placeholder="t('WHATSAPP_TEMPLATES.PARSER.BUTTON_PARAMETER')"
          />
        </div>
      </div>
      <p
        v-if="v$.$dirty && v$.$invalid"
        class="p-2.5 text-center rounded-md bg-n-ruby-9/20 text-n-ruby-9"
      >
        {{ $t('WHATSAPP_TEMPLATES.PARSER.FORM_ERROR_MESSAGE') }}
      </p>
    </div>

    <slot
      name="actions"
      :send-message="sendMessage"
      :reset-template="resetTemplate"
      :go-back="goBack"
      :is-valid="!v$.$invalid"
      :disabled="isFormInvalid"
    />
  </div>
</template>
