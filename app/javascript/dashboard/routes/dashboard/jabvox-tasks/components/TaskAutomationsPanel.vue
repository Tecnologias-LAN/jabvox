<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useTasksStore } from 'dashboard/stores/jabvox/tasks';
import ConfirmDialog from './ConfirmDialog.vue';
import TemplateParamsPicker from 'dashboard/components/jabvox/automations/TemplateParamsPicker.vue';

const props = defineProps({
  taskId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const rootStore = useStore();
const store = useTasksStore();

const automations = ref([]);
const runs = ref([]);
const isLoading = ref(true);
const showForm = ref(false);
const editing = ref(null);
const saving = ref(false);
const runningId = ref(null);
const confirmDialog = ref(null);

const inboxes = useMapGetter('inboxes/getInboxes');
const smsProviders = useMapGetter('jabvoxSms/getProviders');
const emailTemplates = computed(
  () => rootStore.getters['jabvoxEmail/getTemplates'] || []
);

// Por WhatsApp solo se envía plantilla aprobada: el texto libre únicamente sale dentro de
// la ventana de 24h, y una automatización programada dispara casi siempre fuera de ella.
// Claves de los campos personalizados de contacto, para enviarlos como variable de la
// plantilla (p. ej. ciudad, cupo, cédula).
const customAttributeKeys = computed(() =>
  (
    rootStore.getters['attributes/getAttributesByModel']('contact_attribute') ||
    []
  )
    .map(attr => attr.attribute_key)
    .filter(Boolean)
);

const CHANNELS = ['email', 'sms', 'whatsapp_template'];
// Minuto y hora permiten recordatorios intradía ("cada 2 horas").
const UNITS = ['minute', 'hour', 'day', 'week', 'month'];
const RECIPIENTS = ['lead', 'assignees', 'lead_contacts', 'manual'];

const emptyForm = () => ({
  name_jabvox: '',
  channel_jabvox: 'email',
  recipients: ['lead'],
  manual_email_jabvox: '',
  manual_phone_jabvox: '',
  interval_unit_jabvox: 'day',
  interval_count_jabvox: 1,
  // Por defecto, 3 avisos antes del vencimiento: acotado y con final claro, en vez de un
  // ciclo que no para hasta que alguien lo desactive.
  schedule_mode_jabvox: 'before_due',
  max_runs_jabvox: 3,
  email_template_id: '',
  inbox_id: '',
  sms_provider_id: '',
  subject_jabvox: '',
  body_jabvox: '',
  template_name_jabvox: '',
  template_language_jabvox: '',
  template_params_jabvox: {},
  active_jabvox: true,
});
const form = ref(emptyForm());

// Resumen en lenguaje natural de lo configurado: "3 avisos cada 2 horas antes de que
// venza la tarea". Sin esto hay que deducir el comportamiento de tres campos sueltos.
const scheduleSummary = computed(() => {
  const count = Number(form.value.max_runs_jabvox) || 0;
  const every = Number(form.value.interval_count_jabvox) || 1;
  const unit = t(
    `JABVOX_TASKS.AUTOMATION.UNIT.${String(form.value.interval_unit_jabvox).toUpperCase()}`,
    every
  );
  const key =
    form.value.schedule_mode_jabvox === 'before_due'
      ? 'JABVOX_TASKS.AUTOMATION.SUMMARY.BEFORE_DUE'
      : 'JABVOX_TASKS.AUTOMATION.SUMMARY.RECURRING';
  return t(key, { count, every, unit });
});

const channelIcon = ch =>
  ({
    email: 'i-lucide-mail',
    sms: 'i-lucide-message-square',
    whatsapp_template: 'i-lucide-messages-square',
  })[ch] || 'i-lucide-zap';

const recipientLabel = key =>
  t(`JABVOX_TASKS.AUTOMATION.RECIPIENT.${key.toUpperCase()}`);

const intervalSummary = a =>
  t('JABVOX_TASKS.AUTOMATION.EVERY', {
    count: a.intervalCountJabvox,
    unit: t(
      `JABVOX_TASKS.AUTOMATION.UNIT.${(a.intervalUnitJabvox || 'day').toUpperCase()}`,
      a.intervalCountJabvox
    ),
  });

const recipientsOf = a =>
  (a.recipientsJabvox || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

const hasManual = computed(() => form.value.recipients.includes('manual'));

const formatDate = value => {
  if (!value) return '—';
  const d = new Date(value);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
};

const load = async () => {
  isLoading.value = true;
  try {
    [automations.value, runs.value] = await Promise.all([
      store.fetchTaskAutomations(props.taskId),
      store.fetchTaskAutomationRuns(props.taskId),
    ]);
  } catch {
    useAlert(t('JABVOX_TASKS.AUTOMATION.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const openCreate = () => {
  editing.value = null;
  form.value = emptyForm();
  showForm.value = true;
};

const openEdit = a => {
  editing.value = a;
  form.value = {
    name_jabvox: a.nameJabvox || '',
    channel_jabvox: a.channelJabvox,
    recipients: recipientsOf(a),
    manual_email_jabvox: a.manualEmailJabvox || '',
    manual_phone_jabvox: a.manualPhoneJabvox || '',
    interval_unit_jabvox: a.intervalUnitJabvox || 'day',
    interval_count_jabvox: a.intervalCountJabvox || 1,
    schedule_mode_jabvox: a.scheduleModeJabvox || 'recurring',
    max_runs_jabvox: a.maxRunsJabvox || null,
    email_template_id: a.emailTemplateId ? String(a.emailTemplateId) : '',
    inbox_id: a.inboxId ? String(a.inboxId) : '',
    sms_provider_id: a.smsProviderId ? String(a.smsProviderId) : '',
    subject_jabvox: a.subjectJabvox || '',
    body_jabvox: a.bodyJabvox || '',
    template_name_jabvox: a.templateNameJabvox || '',
    template_language_jabvox: a.templateLanguageJabvox || '',
    template_params_jabvox: a.templateParamsJabvox || {},
    active_jabvox: a.activeJabvox,
  };
  showForm.value = true;
};

const buildPayload = () => ({
  name_jabvox: form.value.name_jabvox,
  channel_jabvox: form.value.channel_jabvox,
  recipients_jabvox: form.value.recipients.join(','),
  manual_email_jabvox: form.value.manual_email_jabvox,
  manual_phone_jabvox: form.value.manual_phone_jabvox,
  interval_unit_jabvox: form.value.interval_unit_jabvox,
  interval_count_jabvox: Number(form.value.interval_count_jabvox) || 1,
  schedule_mode_jabvox: form.value.schedule_mode_jabvox,
  max_runs_jabvox: Number(form.value.max_runs_jabvox) || null,
  email_template_id: form.value.email_template_id
    ? Number(form.value.email_template_id)
    : null,
  inbox_id: form.value.inbox_id ? Number(form.value.inbox_id) : null,
  sms_provider_id: form.value.sms_provider_id
    ? Number(form.value.sms_provider_id)
    : null,
  subject_jabvox: form.value.subject_jabvox,
  body_jabvox: form.value.body_jabvox,
  template_name_jabvox: form.value.template_name_jabvox,
  template_language_jabvox: form.value.template_language_jabvox,
  template_params_jabvox: form.value.template_params_jabvox,
  active_jabvox: form.value.active_jabvox,
});

const onSubmit = async () => {
  if (!form.value.recipients.length) {
    useAlert(t('JABVOX_TASKS.AUTOMATION.NEED_RECIPIENT'));
    return;
  }
  saving.value = true;
  try {
    if (editing.value) {
      await store.updateTaskAutomation(
        props.taskId,
        editing.value.id,
        buildPayload()
      );
    } else {
      await store.createTaskAutomation(props.taskId, buildPayload());
    }
    showForm.value = false;
    editing.value = null;
    await load();
  } catch {
    useAlert(t('JABVOX_TASKS.AUTOMATION.ERROR'));
  } finally {
    saving.value = false;
  }
};

const toggleActive = async a => {
  try {
    await store.updateTaskAutomation(props.taskId, a.id, {
      active_jabvox: !a.activeJabvox,
    });
    await load();
  } catch {
    useAlert(t('JABVOX_TASKS.AUTOMATION.ERROR'));
  }
};

const onDelete = a => {
  confirmDialog.value?.open({
    title: t('JABVOX_TASKS.AUTOMATION.DELETE'),
    description: t('JABVOX_TASKS.AUTOMATION.DELETE_CONFIRM'),
    confirmLabel: t('JABVOX_TASKS.AUTOMATION.DELETE'),
    cancelLabel: t('JABVOX_TASKS.AUTOMATION.CANCEL'),
    data: a.id,
  });
};

const doDelete = async automationId => {
  try {
    await store.deleteTaskAutomation(props.taskId, automationId);
    await load();
  } catch {
    useAlert(t('JABVOX_TASKS.AUTOMATION.ERROR'));
  }
};

const runNow = async a => {
  runningId.value = a.id;
  try {
    await store.runTaskAutomationNow(props.taskId, a.id);
    useAlert(t('JABVOX_TASKS.AUTOMATION.RUN_DONE'));
    await load();
  } catch {
    useAlert(t('JABVOX_TASKS.AUTOMATION.ERROR'));
  } finally {
    runningId.value = null;
  }
};

const toggleRecipient = key => {
  const set = new Set(form.value.recipients);
  if (set.has(key)) set.delete(key);
  else set.add(key);
  form.value.recipients = [...set];
};

const runStatusClass = status =>
  ({
    sent: 'bg-n-teal-3 text-n-teal-11',
    partial: 'bg-n-amber-3 text-n-amber-11',
    failed: 'bg-n-ruby-3 text-n-ruby-11',
    skipped: 'bg-n-alpha-2 text-n-slate-10',
  })[status] || 'bg-n-alpha-2 text-n-slate-10';

onMounted(() => {
  rootStore.dispatch('inboxes/get');
  rootStore.dispatch('jabvoxEmail/fetchTemplates');
  rootStore.dispatch('jabvoxSms/fetchProviders');
  rootStore.dispatch('attributes/get');
  load();
});
</script>

<template>
  <section class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-sm">
    <!-- El título cede espacio y el botón no se encoge: en la columna lateral (320px)
         el texto largo del botón desbordaba la tarjeta. -->
    <div class="flex items-center justify-between gap-2 mb-4">
      <h3
        class="flex items-center gap-2 min-w-0 text-sm font-semibold text-n-slate-12"
      >
        <span
          class="i-lucide-zap size-4 text-n-slate-10 shrink-0"
          aria-hidden="true"
        />
        <span class="truncate">{{ t('JABVOX_TASKS.AUTOMATION.TITLE') }}</span>
      </h3>
      <button
        type="button"
        class="inline-flex items-center gap-1 shrink-0 px-2 py-1.5 text-xs font-medium rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors"
        :title="t('JABVOX_TASKS.AUTOMATION.ADD')"
        @click="openCreate"
      >
        <span class="i-lucide-plus size-3.5 shrink-0" aria-hidden="true" />
        <span class="truncate max-w-[9rem]">
          {{ t('JABVOX_TASKS.AUTOMATION.ADD') }}
        </span>
      </button>
    </div>

    <p v-if="isLoading" class="text-sm text-n-slate-10">
      {{ t('JABVOX_TASKS.BOARD.LOADING') }}
    </p>

    <template v-else>
      <!-- Empty -->
      <p v-if="!automations.length" class="text-sm text-n-slate-10 py-2">
        {{ t('JABVOX_TASKS.AUTOMATION.EMPTY') }}
      </p>

      <!-- List -->
      <ul v-else class="space-y-2">
        <li
          v-for="a in automations"
          :key="a.id"
          class="rounded-xl border border-n-weak p-3 flex flex-col gap-2"
          :class="a.activeJabvox ? '' : 'opacity-60'"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="flex items-start gap-2.5 min-w-0">
              <span
                class="flex items-center justify-center size-8 rounded-lg bg-n-alpha-1 text-n-slate-11 shrink-0"
              >
                <span
                  :class="channelIcon(a.channelJabvox)"
                  class="size-4"
                  aria-hidden="true"
                />
              </span>
              <div class="min-w-0">
                <p class="text-sm font-medium text-n-slate-12 truncate">
                  {{
                    a.nameJabvox ||
                    t(
                      `JABVOX_TASKS.AUTOMATION.CHANNEL.${a.channelJabvox.toUpperCase()}`
                    )
                  }}
                </p>
                <p class="text-[11px] text-n-slate-10">
                  {{ intervalSummary(a) }} ·
                  {{
                    recipientsOf(a)
                      .map(r => recipientLabel(r))
                      .join(', ')
                  }}
                </p>
              </div>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <button
                type="button"
                class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 disabled:opacity-40"
                :title="t('JABVOX_TASKS.AUTOMATION.RUN_NOW')"
                :disabled="runningId === a.id"
                @click="runNow(a)"
              >
                <span
                  :class="
                    runningId === a.id
                      ? 'i-lucide-loader-2 animate-spin'
                      : 'i-lucide-send'
                  "
                  class="size-3.5"
                  aria-hidden="true"
                />
              </button>
              <button
                type="button"
                class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                :title="t('JABVOX_TASKS.AUTOMATION.TOGGLE')"
                @click="toggleActive(a)"
              >
                <span
                  :class="a.activeJabvox ? 'i-lucide-pause' : 'i-lucide-play'"
                  class="size-3.5"
                  aria-hidden="true"
                />
              </button>
              <button
                type="button"
                class="p-1 rounded text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2"
                :title="t('JABVOX_TASKS.AUTOMATION.EDIT')"
                @click="openEdit(a)"
              >
                <span class="i-lucide-pencil size-3.5" aria-hidden="true" />
              </button>
              <button
                type="button"
                class="p-1 rounded text-n-ruby-11 hover:bg-n-alpha-2"
                :title="t('JABVOX_TASKS.AUTOMATION.DELETE')"
                @click="onDelete(a)"
              >
                <span class="i-lucide-trash-2 size-3.5" aria-hidden="true" />
              </button>
            </div>
          </div>
          <div
            class="flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-n-slate-10 pl-10"
          >
            <span class="inline-flex items-center gap-1">
              <span class="i-lucide-calendar-clock size-3" aria-hidden="true" />
              {{ t('JABVOX_TASKS.AUTOMATION.NEXT_RUN') }}:
              {{ formatDate(a.nextRunAtJabvox) }}
            </span>
            <span
              v-if="a.runsCountJabvox"
              class="inline-flex items-center gap-1"
            >
              <span class="i-lucide-history size-3" aria-hidden="true" />
              {{ t('JABVOX_TASKS.AUTOMATION.RUNS_COUNT', a.runsCountJabvox) }}
            </span>
          </div>
        </li>
      </ul>

      <!-- Recent dispatch log -->
      <div v-if="runs.length" class="mt-4 pt-4 border-t border-n-weak">
        <p
          class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10 mb-2"
        >
          {{ t('JABVOX_TASKS.AUTOMATION.LOG_TITLE') }}
        </p>
        <ul class="space-y-1.5">
          <li
            v-for="r in runs.slice(0, 6)"
            :key="r.id"
            class="flex items-center gap-2 text-[11px]"
          >
            <span
              class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 font-medium shrink-0"
              :class="runStatusClass(r.statusJabvox)"
            >
              <span
                :class="channelIcon(r.channelJabvox)"
                class="size-3"
                aria-hidden="true"
              />
              {{
                t(
                  `JABVOX_TASKS.AUTOMATION.STATUS.${r.statusJabvox.toUpperCase()}`
                )
              }}
            </span>
            <span class="text-n-slate-11 truncate">
              {{
                t('JABVOX_TASKS.AUTOMATION.SENT_TO', r.recipientsCountJabvox)
              }}
            </span>
            <span class="text-n-slate-9 ml-auto shrink-0">{{
              formatDate(r.runAtJabvox)
            }}</span>
          </li>
        </ul>
      </div>
    </template>

    <!-- Create / edit form -->
    <div v-if="showForm" class="fixed inset-0 z-50 flex justify-end">
      <div class="absolute inset-0 bg-black/40" @click="showForm = false" />
      <div
        class="relative ml-auto w-full sm:max-w-md h-full bg-n-solid-1 shadow-xl flex flex-col overflow-hidden"
      >
        <div
          class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak shrink-0"
        >
          <h4 class="font-semibold text-n-slate-12">
            {{
              editing
                ? t('JABVOX_TASKS.AUTOMATION.EDIT_TITLE')
                : t('JABVOX_TASKS.AUTOMATION.NEW_TITLE')
            }}
          </h4>
          <button
            type="button"
            class="text-n-slate-11 hover:text-n-slate-12"
            @click="showForm = false"
          >
            <span class="i-lucide-x size-5" aria-hidden="true" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto p-5 space-y-4">
          <!-- Name -->
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_TASKS.AUTOMATION.NAME')
            }}</label>
            <input
              v-model="form.name_jabvox"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="t('JABVOX_TASKS.AUTOMATION.NAME_PLACEHOLDER')"
            />
          </div>

          <!-- Channel -->
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_TASKS.AUTOMATION.CHANNEL_LABEL')
            }}</label>
            <div class="grid grid-cols-3 gap-2">
              <button
                v-for="ch in CHANNELS"
                :key="ch"
                type="button"
                class="flex flex-col items-center gap-1 py-2 rounded-lg border text-xs"
                :class="
                  form.channel_jabvox === ch
                    ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                    : 'border-n-weak text-n-slate-10'
                "
                @click="form.channel_jabvox = ch"
              >
                <span
                  :class="channelIcon(ch)"
                  class="size-4"
                  aria-hidden="true"
                />
                {{ t(`JABVOX_TASKS.AUTOMATION.CHANNEL.${ch.toUpperCase()}`) }}
              </button>
            </div>
          </div>

          <!-- Recurrence -->
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_TASKS.AUTOMATION.RECURRENCE')
            }}</label>
            <select
              v-model="form.schedule_mode_jabvox"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
            >
              <option value="before_due">
                {{ t('JABVOX_TASKS.AUTOMATION.MODE.BEFORE_DUE') }}
              </option>
              <option value="recurring">
                {{ t('JABVOX_TASKS.AUTOMATION.MODE.RECURRING') }}
              </option>
            </select>
            <div class="flex items-center gap-2">
              <input
                v-model.number="form.max_runs_jabvox"
                type="number"
                min="1"
                class="reset-base w-16 text-sm text-center rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-2"
              />
              <span class="text-sm text-n-slate-10">
                {{ t('JABVOX_TASKS.AUTOMATION.TIMES_WORD') }}
              </span>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-sm text-n-slate-10">{{
                t('JABVOX_TASKS.AUTOMATION.EVERY_WORD')
              }}</span>
              <input
                v-model.number="form.interval_count_jabvox"
                type="number"
                min="1"
                max="365"
                class="reset-base w-16 text-sm text-center rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-2"
              />
              <select
                v-model="form.interval_unit_jabvox"
                class="reset-base flex-1 text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              >
                <option v-for="u in UNITS" :key="u" :value="u">
                  {{
                    t(
                      `JABVOX_TASKS.AUTOMATION.UNIT.${u.toUpperCase()}`,
                      form.interval_count_jabvox
                    )
                  }}
                </option>
              </select>
            </div>
            <p class="text-xs text-n-slate-10">{{ scheduleSummary }}</p>
          </div>

          <!-- Recipients -->
          <div class="flex flex-col gap-1.5">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_TASKS.AUTOMATION.RECIPIENTS')
            }}</label>
            <div class="flex flex-wrap gap-2">
              <button
                v-for="r in RECIPIENTS"
                :key="r"
                type="button"
                class="px-3 py-1.5 rounded-full text-xs border transition-colors"
                :class="
                  form.recipients.includes(r)
                    ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
                    : 'border-n-weak text-n-slate-10'
                "
                @click="toggleRecipient(r)"
              >
                {{ recipientLabel(r) }}
              </button>
            </div>
          </div>

          <!-- Manual target -->
          <div v-if="hasManual" class="grid grid-cols-1 gap-2">
            <input
              v-if="form.channel_jabvox === 'email'"
              v-model="form.manual_email_jabvox"
              type="email"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="t('JABVOX_TASKS.AUTOMATION.MANUAL_EMAIL')"
            />
            <input
              v-else
              v-model="form.manual_phone_jabvox"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              :placeholder="t('JABVOX_TASKS.AUTOMATION.MANUAL_PHONE')"
            />
          </div>

          <!-- Email: template or subject -->
          <template v-if="form.channel_jabvox === 'email'">
            <div class="flex flex-col gap-1">
              <label class="text-xs text-n-slate-11">{{
                t('JABVOX_TASKS.AUTOMATION.EMAIL_TEMPLATE')
              }}</label>
              <select
                v-model="form.email_template_id"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              >
                <option value="">
                  {{ t('JABVOX_TASKS.AUTOMATION.EMAIL_TEMPLATE_NONE') }}
                </option>
                <option
                  v-for="tpl in emailTemplates"
                  :key="tpl.id"
                  :value="String(tpl.id)"
                >
                  {{ tpl.name }}
                </option>
              </select>
            </div>
            <div v-if="!form.email_template_id" class="flex flex-col gap-1">
              <label class="text-xs text-n-slate-11">{{
                t('JABVOX_TASKS.AUTOMATION.SUBJECT')
              }}</label>
              <input
                v-model="form.subject_jabvox"
                class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              />
            </div>
          </template>

          <!-- Bandeja de WhatsApp -->
          <div
            v-else-if="form.channel_jabvox === 'whatsapp_template'"
            class="flex flex-col gap-1"
          >
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_TASKS.AUTOMATION.INBOX')
            }}</label>
            <select
              v-model="form.inbox_id"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
            >
              <option value="">—</option>
              <option v-for="ib in inboxes" :key="ib.id" :value="String(ib.id)">
                {{ ib.name }}
              </option>
            </select>
            <TemplateParamsPicker
              v-model:template-name="form.template_name_jabvox"
              v-model:template-language="form.template_language_jabvox"
              v-model:params="form.template_params_jabvox"
              :inbox-id="form.inbox_id"
              allow-task
              :custom-attribute-keys="customAttributeKeys"
            />
          </div>

          <!-- SMS provider -->
          <div v-else class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_TASKS.AUTOMATION.SMS_PROVIDER')
            }}</label>
            <select
              v-model="form.sms_provider_id"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
            >
              <option value="">—</option>
              <option
                v-for="p in smsProviders"
                :key="p.id"
                :value="String(p.id)"
              >
                {{ p.name }}
              </option>
            </select>
          </div>

          <!-- Cuerpo libre: solo SMS, o email sin plantilla. Por WhatsApp va la plantilla. -->
          <div
            v-if="
              form.channel_jabvox === 'sms' ||
              (form.channel_jabvox === 'email' && !form.email_template_id)
            "
            class="flex flex-col gap-1"
          >
            <label class="text-xs text-n-slate-11">{{
              t('JABVOX_TASKS.AUTOMATION.BODY')
            }}</label>
            <textarea
              v-model="form.body_jabvox"
              rows="4"
              class="reset-base text-sm rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 resize-y"
              :placeholder="t('JABVOX_TASKS.AUTOMATION.BODY_PLACEHOLDER')"
            />
            <span class="text-[11px] text-n-slate-9">
              {{ t('JABVOX_TASKS.AUTOMATION.VARS_HINT') }}
            </span>
          </div>
        </div>

        <div
          class="flex items-center justify-end gap-2 px-5 py-3.5 border-t border-n-weak shrink-0"
        >
          <button
            type="button"
            class="px-3 py-2 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
            @click="showForm = false"
          >
            {{ t('JABVOX_TASKS.AUTOMATION.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 disabled:opacity-50"
            :disabled="saving"
            @click="onSubmit"
          >
            <span
              v-if="saving"
              class="i-lucide-loader-2 size-4 animate-spin"
              aria-hidden="true"
            />
            {{ t('JABVOX_TASKS.AUTOMATION.SAVE') }}
          </button>
        </div>
      </div>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="doDelete" />
  </section>
</template>
