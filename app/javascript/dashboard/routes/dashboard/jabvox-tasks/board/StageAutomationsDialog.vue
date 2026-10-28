<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import ConfirmDialog from '../components/ConfirmDialog.vue';
import TemplateParamsPicker from 'dashboard/components/jabvox/automations/TemplateParamsPicker.vue';
import AssigneeContactMap from '../components/AssigneeContactMap.vue';

const props = defineProps({
  boardId: {
    type: [Number, String],
    required: true,
  },
  stage: {
    type: Object,
    required: true,
  },
  stages: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useTasksStore();
const rootStore = useStore();

// Channel option sources — resolved by name in the channel selector.
const inboxes = useMapGetter('inboxes/getInboxes');
const emailTemplates = computed(
  () => rootStore.getters['jabvoxEmail/getTemplates']
);
const smsProviders = useMapGetter('jabvoxSms/getProviders');
// Agentes de la cuenta = responsables posibles para el mapeo responsable->contacto.
const agents = useMapGetter('agents/getAgents');

const automations = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const editing = ref(null);
const showForm = ref(false);

// Form state
const automationType = ref('send_message');
const channelType = ref('whatsapp_template');
const messageBody = ref('');
const templateName = ref('');
const templateLanguage = ref('');
const templateParams = ref({});
// El disparo se mide en minutos u horas: "avisar 30 minutos antes" y "mover tras 48
// horas sin tocar" son casos igual de reales.
const triggerUnit = ref('hours');
const inboxId = ref('');
const emailTemplateId = ref('');
const smsProviderId = ref('');
const webhookUrl = ref('');
const webhookSecret = ref('');
const hasWebhookSecret = ref(false);
const triggerHours = ref('');
const targetStageId = ref(null);
const active = ref(true);
const confirmDialog = ref(null);

// Destinatario del mensaje (igual que en automatizaciones de tarea específica): a quién
// enviar (lead / responsables / manual). Por defecto al lead, para no cambiar lo existente.
const RECIPIENTS = ['lead', 'assignees', 'manual'];
const recipients = ref(['lead']);
const manualEmail = ref('');
const manualPhone = ref('');
// Mapeo responsable->contacto para WhatsApp: { "<userId>": contactId }. Un responsable no
// tiene teléfono, así que se le asigna un contacto real para poder enviarle la plantilla.
const assigneeContactMap = ref({});

const typeOptions = computed(() => [
  {
    value: 'send_message',
    label: t('JABVOX_TASKS.AUTOMATIONS.TYPE_SEND_MESSAGE'),
  },
  { value: 'webhook', label: t('JABVOX_TASKS.AUTOMATIONS.TYPE_WEBHOOK') },
  {
    value: 'move_after_hours',
    label: t('JABVOX_TASKS.AUTOMATIONS.TYPE_MOVE_AFTER_HOURS'),
  },
  {
    value: 'move_if_inactive',
    label: t('JABVOX_TASKS.AUTOMATIONS.TYPE_MOVE_IF_INACTIVE'),
  },
]);

const typeLabelMap = computed(() =>
  typeOptions.value.reduce((acc, opt) => {
    acc[opt.value] = opt.label;
    return acc;
  }, {})
);

const isMoveType = computed(() =>
  ['move_after_hours', 'move_if_inactive'].includes(automationType.value)
);

// Unified channel selector: a single dropdown that lists WhatsApp inboxes, email
// templates and SMS providers by name. The selected `type:id` key is split
// back into channelType + the matching id field.
const applyChannelKey = key => {
  if (!key) {
    channelType.value = 'whatsapp_template';
    inboxId.value = '';
    emailTemplateId.value = '';
    smsProviderId.value = '';
    return;
  }
  const [type, rawId] = key.split(':');
  channelType.value = type;
  inboxId.value = type === 'whatsapp_template' ? rawId : '';
  emailTemplateId.value = type === 'email' ? rawId : '';
  smsProviderId.value = type === 'sms' ? rawId : '';
};

// Claves de los campos personalizados de contacto, para poder enviarlos como variable
// de la plantilla (p. ej. ciudad, cupo, cédula).
const customAttributeKeys = computed(() =>
  (
    rootStore.getters['attributes/getAttributesByModel']('contact_attribute') ||
    []
  )
    .map(attr => attr.attribute_key)
    .filter(Boolean)
);

// Etiqueta traducida de cada tipo de destinatario (Lead / Responsables / Manual).
const recipientLabel = key =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`JABVOX_TASKS.AUTOMATION.RECIPIENT.${key.toUpperCase()}`);

const toggleRecipient = key => {
  const set = new Set(recipients.value);
  if (set.has(key)) set.delete(key);
  else set.add(key);
  // Nunca quedarse sin destinatario: si se desmarca el último, vuelve a "lead".
  recipients.value = set.size ? [...set] : ['lead'];
};

const hasManual = computed(() => recipients.value.includes('manual'));
const hasAssignees = computed(() => recipients.value.includes('assignees'));

const selectedChannelKey = computed({
  get: () => {
    if (channelType.value === 'whatsapp_template' && inboxId.value)
      return `whatsapp_template:${inboxId.value}`;
    if (channelType.value === 'email' && emailTemplateId.value)
      return `email:${emailTemplateId.value}`;
    if (channelType.value === 'sms' && smsProviderId.value)
      return `sms:${smsProviderId.value}`;
    return '';
  },
  set: applyChannelKey,
});

const resetForm = () => {
  automationType.value = 'send_message';
  channelType.value = 'whatsapp_template';
  messageBody.value = '';
  templateName.value = '';
  templateLanguage.value = '';
  templateParams.value = {};
  triggerUnit.value = 'hours';
  inboxId.value = '';
  emailTemplateId.value = '';
  smsProviderId.value = '';
  webhookUrl.value = '';
  webhookSecret.value = '';
  hasWebhookSecret.value = false;
  triggerHours.value = '';
  targetStageId.value = null;
  active.value = true;
  recipients.value = ['lead'];
  manualEmail.value = '';
  manualPhone.value = '';
  assigneeContactMap.value = {};
  editing.value = null;
};

const load = async () => {
  isLoading.value = true;
  try {
    automations.value = await store.fetchAutomations(
      props.boardId,
      props.stage.id
    );
  } catch {
    useAlert(t('JABVOX_TASKS.AUTOMATIONS.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const openCreate = () => {
  resetForm();
  showForm.value = true;
};

const openEdit = automation => {
  editing.value = automation;
  automationType.value = automation.automationTypeJabvox || 'send_message';
  channelType.value = automation.channelTypeJabvox || 'whatsapp_template';
  messageBody.value = automation.messageBodyJabvox || '';
  templateName.value = automation.templateNameJabvox || '';
  templateLanguage.value = automation.templateLanguageJabvox || '';
  templateParams.value = automation.templateParamsJabvox || {};
  triggerUnit.value = automation.triggerUnitJabvox || 'hours';
  inboxId.value = automation.inboxId ? String(automation.inboxId) : '';
  emailTemplateId.value = automation.emailTemplateId
    ? String(automation.emailTemplateId)
    : '';
  smsProviderId.value = automation.smsProviderId
    ? String(automation.smsProviderId)
    : '';
  webhookUrl.value = automation.webhookUrlJabvox || '';
  webhookSecret.value = '';
  hasWebhookSecret.value = Boolean(automation.hasWebhookSecret);
  triggerHours.value = automation.triggerHoursJabvox
    ? String(automation.triggerHoursJabvox)
    : '';
  targetStageId.value = automation.targetStageId || null;
  active.value = automation.activeJabvox !== false;
  recipients.value = (automation.recipientsJabvox || 'lead')
    .split(',')
    .map(r => r.trim())
    .filter(Boolean);
  if (!recipients.value.length) recipients.value = ['lead'];
  manualEmail.value = automation.manualEmailJabvox || '';
  manualPhone.value = automation.manualPhoneJabvox || '';
  assigneeContactMap.value = automation.assigneeContactMapJabvox || {};
  showForm.value = true;
};

const buildPayload = () => {
  const payload = {
    automation_type_jabvox: automationType.value,
    active_jabvox: active.value,
  };
  if (automationType.value === 'send_message') {
    payload.channel_type_jabvox = channelType.value;
    payload.message_body_jabvox = messageBody.value;
    payload.template_name_jabvox = templateName.value;
    payload.template_language_jabvox = templateLanguage.value;
    payload.template_params_jabvox = templateParams.value;
    payload.inbox_id = inboxId.value ? Number(inboxId.value) : null;
    payload.email_template_id = emailTemplateId.value
      ? Number(emailTemplateId.value)
      : null;
    payload.sms_provider_id = smsProviderId.value
      ? Number(smsProviderId.value)
      : null;
    // Destinatario: a quién enviar y los datos que cada opción necesita.
    payload.recipients_jabvox = recipients.value.join(',');
    payload.manual_email_jabvox = manualEmail.value;
    payload.manual_phone_jabvox = manualPhone.value;
    payload.assignee_contact_map_jabvox = assigneeContactMap.value;
  } else if (automationType.value === 'webhook') {
    payload.webhook_url_jabvox = webhookUrl.value;
    if (webhookSecret.value) {
      payload.webhook_secret_jabvox = webhookSecret.value;
    }
  } else {
    // `trigger_value_jabvox` + unidad sustituyen a las horas fijas; se sigue enviando
    // trigger_hours_jabvox para no romper lo ya guardado.
    payload.trigger_value_jabvox = triggerHours.value
      ? Number(triggerHours.value)
      : null;
    payload.trigger_unit_jabvox = triggerUnit.value;
    payload.trigger_hours_jabvox =
      triggerUnit.value === 'hours' && triggerHours.value
        ? Number(triggerHours.value)
        : null;
    payload.target_stage_id = targetStageId.value
      ? Number(targetStageId.value)
      : null;
  }
  return payload;
};

const onSubmit = async () => {
  isSaving.value = true;
  try {
    const payload = buildPayload();
    if (editing.value) {
      await store.updateAutomation(
        props.boardId,
        props.stage.id,
        editing.value.id,
        payload
      );
      useAlert(t('JABVOX_TASKS.AUTOMATIONS.UPDATED'));
    } else {
      await store.createAutomation(props.boardId, props.stage.id, payload);
      useAlert(t('JABVOX_TASKS.AUTOMATIONS.CREATED'));
    }
    showForm.value = false;
    resetForm();
    await load();
  } catch {
    useAlert(t('JABVOX_TASKS.AUTOMATIONS.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const onDelete = automation => {
  confirmDialog.value?.open({
    title: t('JABVOX_TASKS.AUTOMATIONS.DELETE'),
    description: t('JABVOX_TASKS.AUTOMATIONS.DELETE_CONFIRM'),
    confirmLabel: t('JABVOX_TASKS.AUTOMATIONS.DELETE'),
    cancelLabel: t('JABVOX_TASKS.AUTOMATIONS.CANCEL'),
    data: automation.id,
  });
};

const doDelete = async automationId => {
  try {
    await store.deleteAutomation(props.boardId, props.stage.id, automationId);
    useAlert(t('JABVOX_TASKS.AUTOMATIONS.DELETED'));
    await load();
  } catch {
    useAlert(t('JABVOX_TASKS.AUTOMATIONS.ERROR'));
  }
};

onMounted(() => {
  load();
  rootStore.dispatch('inboxes/get');
  rootStore.dispatch('jabvoxEmail/fetchTemplates');
  rootStore.dispatch('jabvoxSms/fetchProviders');
  rootStore.dispatch('attributes/get');
  // Responsables posibles para el mapeo responsable->contacto (son todos los agentes de la
  // cuenta, porque la automatización de etapa aplica a cualquier tarea que entre a la etapa).
  rootStore.dispatch('agents/get');
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-3"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-2xl rounded-xl bg-n-solid-1 border border-n-weak shadow-lg max-h-[90vh] flex flex-col"
    >
      <div
        class="flex items-start justify-between px-5 py-4 border-b border-n-weak shrink-0"
      >
        <div>
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ t('JABVOX_TASKS.AUTOMATIONS.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-10">
            {{ stage.nameJabvox }}
          </p>
        </div>
        <button
          type="button"
          class="text-n-slate-10 hover:text-n-slate-12"
          :title="t('JABVOX_TASKS.AUTOMATIONS.CLOSE')"
          @click="emit('close')"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </div>

      <div class="flex-1 min-h-0 overflow-y-auto px-5 py-4 space-y-4">
        <p class="text-sm text-n-slate-10">
          {{ t('JABVOX_TASKS.AUTOMATIONS.SUBTITLE') }}
        </p>

        <p v-if="isLoading" class="text-sm text-n-slate-10">
          {{ t('JABVOX_TASKS.CALENDAR.LOADING') }}
        </p>

        <ul v-else-if="automations.length" class="space-y-2">
          <li
            v-for="automation in automations"
            :key="automation.id"
            class="flex items-center justify-between gap-3 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <div class="flex items-center gap-2 min-w-0">
              <span
                class="size-2.5 rounded-full shrink-0"
                :class="
                  automation.activeJabvox ? 'bg-n-teal-3' : 'bg-n-alpha-2'
                "
                aria-hidden="true"
              />
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ typeLabelMap[automation.automationTypeJabvox] }}
              </p>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <button
                type="button"
                class="p-1.5 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                @click="openEdit(automation)"
              >
                <span class="i-lucide-pencil size-4" aria-hidden="true" />
              </button>
              <button
                type="button"
                class="p-1.5 rounded text-n-ruby-11 hover:bg-n-alpha-2"
                @click="onDelete(automation)"
              >
                <span class="i-lucide-trash-2 size-4" aria-hidden="true" />
              </button>
            </div>
          </li>
        </ul>

        <p v-else class="text-sm text-n-slate-10">
          {{ t('JABVOX_TASKS.AUTOMATIONS.EMPTY') }}
        </p>

        <button
          v-if="!showForm"
          type="button"
          class="flex items-center gap-1 px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3"
          @click="openCreate"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
          {{ t('JABVOX_TASKS.AUTOMATIONS.ADD') }}
        </button>

        <form
          v-if="showForm"
          class="space-y-4 p-4 rounded-lg border border-n-weak bg-n-alpha-1"
          @submit.prevent="onSubmit"
        >
          <div class="space-y-1">
            <label class="block text-sm font-medium text-n-slate-11">
              {{ t('JABVOX_TASKS.AUTOMATIONS.TYPE') }}
            </label>
            <select
              v-model="automationType"
              class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
            >
              <option
                v-for="opt in typeOptions"
                :key="opt.value"
                :value="opt.value"
              >
                {{ opt.label }}
              </option>
            </select>
          </div>

          <template v-if="automationType === 'send_message'">
            <!-- Destinatario: a quién enviar el mensaje (lead / responsables / manual). -->
            <div class="space-y-1">
              <label class="block text-sm font-medium text-n-slate-11">
                {{ t('JABVOX_TASKS.AUTOMATION.RECIPIENTS') }}
              </label>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="r in RECIPIENTS"
                  :key="r"
                  type="button"
                  class="px-3 py-1.5 rounded-full text-xs border transition-colors"
                  :class="
                    recipients.includes(r)
                      ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                      : 'border-n-weak text-n-slate-10'
                  "
                  @click="toggleRecipient(r)"
                >
                  {{ recipientLabel(r) }}
                </button>
              </div>
            </div>

            <!-- Destinatario manual (email o teléfono según el canal). -->
            <div v-if="hasManual" class="space-y-1">
              <input
                v-if="channelType === 'email'"
                v-model="manualEmail"
                type="email"
                :placeholder="t('JABVOX_TASKS.AUTOMATION.MANUAL_EMAIL')"
                class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
              />
              <input
                v-else
                v-model="manualPhone"
                :placeholder="t('JABVOX_TASKS.AUTOMATION.MANUAL_PHONE')"
                class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
              />
            </div>

            <div class="space-y-1">
              <label class="block text-sm font-medium text-n-slate-11">
                {{ t('JABVOX_TASKS.AUTOMATIONS.CHANNEL') }}
              </label>
              <select
                v-model="selectedChannelKey"
                class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
              >
                <option value="" disabled>
                  {{ t('JABVOX_TASKS.AUTOMATIONS.CHANNEL_PLACEHOLDER') }}
                </option>
                <optgroup :label="t('JABVOX_TASKS.AUTOMATIONS.CHANNEL_INBOX')">
                  <option
                    v-for="inbox in inboxes"
                    :key="inbox.id"
                    :value="`whatsapp_template:${inbox.id}`"
                  >
                    {{ inbox.name }}
                  </option>
                  <option v-if="!inboxes.length" value="" disabled>
                    {{ t('JABVOX_TASKS.AUTOMATIONS.CHANNEL_NONE') }}
                  </option>
                </optgroup>
                <optgroup :label="t('JABVOX_TASKS.AUTOMATIONS.CHANNEL_EMAIL')">
                  <option
                    v-for="tpl in emailTemplates"
                    :key="tpl.id"
                    :value="`email:${tpl.id}`"
                  >
                    {{ tpl.name }}
                  </option>
                  <option v-if="!emailTemplates.length" value="" disabled>
                    {{ t('JABVOX_TASKS.AUTOMATIONS.CHANNEL_NONE') }}
                  </option>
                </optgroup>
                <optgroup :label="t('JABVOX_TASKS.AUTOMATIONS.CHANNEL_SMS')">
                  <option
                    v-for="p in smsProviders"
                    :key="p.id"
                    :value="`sms:${p.id}`"
                  >
                    {{ p.name }}
                  </option>
                  <option v-if="!smsProviders.length" value="" disabled>
                    {{ t('JABVOX_TASKS.AUTOMATIONS.CHANNEL_NONE') }}
                  </option>
                </optgroup>
              </select>
            </div>
            <TemplateParamsPicker
              v-if="channelType === 'whatsapp_template'"
              v-model:template-name="templateName"
              v-model:template-language="templateLanguage"
              v-model:params="templateParams"
              :inbox-id="inboxId"
              allow-task
              :custom-attribute-keys="customAttributeKeys"
            />
            <!-- Mapeo responsable->contacto: solo si se envía por WhatsApp a responsables.
                 Un responsable no tiene teléfono, así que se le asigna un contacto real. -->
            <div
              v-if="channelType === 'whatsapp_template' && hasAssignees"
              class="pt-3 mt-1 border-t border-n-weak"
            >
              <label class="block mb-2 text-xs font-medium text-n-slate-12">
                {{ t('JABVOX_TASKS.AUTOMATION.ASSIGNEE_MAP.TITLE') }}
              </label>
              <AssigneeContactMap
                v-model="assigneeContactMap"
                :assignees="agents"
              />
            </div>
            <div v-if="channelType === 'sms'" class="space-y-1">
              <label class="block text-sm font-medium text-n-slate-11">
                {{ t('JABVOX_TASKS.AUTOMATIONS.MESSAGE_BODY') }}
              </label>
              <textarea
                v-model="messageBody"
                rows="3"
                :placeholder="
                  t('JABVOX_TASKS.AUTOMATIONS.MESSAGE_BODY_PLACEHOLDER')
                "
                class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
              />
            </div>
          </template>

          <template v-if="automationType === 'webhook'">
            <div class="space-y-1">
              <label class="block text-sm font-medium text-n-slate-11">
                {{ t('JABVOX_TASKS.AUTOMATIONS.WEBHOOK_URL') }}
              </label>
              <input
                v-model="webhookUrl"
                type="url"
                :placeholder="
                  t('JABVOX_TASKS.AUTOMATIONS.WEBHOOK_URL_PLACEHOLDER')
                "
                class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
              />
              <p class="text-[11px] text-n-slate-10">
                {{ t('JABVOX_TASKS.AUTOMATIONS.WEBHOOK_SECURITY_NOTE') }}
              </p>
            </div>
            <div class="space-y-1">
              <label class="block text-sm font-medium text-n-slate-11">
                {{ t('JABVOX_TASKS.AUTOMATIONS.WEBHOOK_SECRET') }}
              </label>
              <input
                v-model="webhookSecret"
                type="text"
                :placeholder="
                  t('JABVOX_TASKS.AUTOMATIONS.WEBHOOK_SECRET_PLACEHOLDER')
                "
                class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
              />
              <p v-if="hasWebhookSecret" class="text-[11px] text-n-teal-11">
                {{ t('JABVOX_TASKS.AUTOMATIONS.WEBHOOK_SECRET_SET') }}
              </p>
            </div>
          </template>

          <template v-if="isMoveType">
            <div class="space-y-1">
              <label class="block text-sm font-medium text-n-slate-11">
                {{ t('JABVOX_TASKS.AUTOMATIONS.TRIGGER_HOURS') }}
              </label>
              <div class="flex gap-2">
                <input
                  v-model="triggerHours"
                  type="number"
                  min="0"
                  class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
                />
                <select
                  v-model="triggerUnit"
                  class="px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
                >
                  <option value="minutes">
                    {{ t('JABVOX_TASKS.AUTOMATIONS.UNIT_MINUTES') }}
                  </option>
                  <option value="hours">
                    {{ t('JABVOX_TASKS.AUTOMATIONS.UNIT_HOURS') }}
                  </option>
                </select>
              </div>
            </div>
            <div class="space-y-1">
              <label class="block text-sm font-medium text-n-slate-11">
                {{ t('JABVOX_TASKS.AUTOMATIONS.TARGET_STAGE') }}
              </label>
              <select
                v-model="targetStageId"
                class="w-full px-3 py-2 text-sm rounded-lg bg-n-solid-1 border border-n-weak text-n-slate-12 focus:outline-none focus:border-n-strong"
              >
                <option v-for="s in stages" :key="s.id" :value="s.id">
                  {{ s.nameJabvox }}
                </option>
              </select>
            </div>
          </template>

          <label class="flex items-center gap-2 text-sm text-n-slate-11">
            <input v-model="active" type="checkbox" class="rounded" />
            {{ t('JABVOX_TASKS.AUTOMATIONS.ACTIVE') }}
          </label>

          <div class="flex items-center justify-end gap-2 pt-1">
            <button
              type="button"
              class="px-3 py-2 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
              @click="showForm = false"
            >
              {{ t('JABVOX_TASKS.AUTOMATIONS.CANCEL') }}
            </button>
            <button
              type="submit"
              class="px-3 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
              :disabled="isSaving"
            >
              {{ t('JABVOX_TASKS.AUTOMATIONS.SAVE') }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="doDelete" />
  </div>
</template>
