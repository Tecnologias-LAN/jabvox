<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  stage: { type: Object, required: true },
  funnelId: { type: Number, required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const automations = computed(() => store.getters['jabvoxEmail/getAutomations']);
const templates = computed(() => store.getters['jabvoxEmail/getTemplates']);
const smsProviders = useMapGetter('jabvoxSms/getProviders');
const inboxes = useMapGetter('inboxes/getInboxes');
const funnels = useMapGetter('jabvoxKanban/getFunnels');
const uiFlags = computed(() => store.getters['jabvoxEmail/getUIFlags']);

const otherStages = computed(() => {
  const funnel = funnels.value.find(f => f.id === props.funnelId);
  return (funnel?.stages || [])
    .filter(s => s.id !== props.stage.id)
    .sort((a, b) => a.position_jabvox - b.position_jabvox);
});

const showForm = ref(false);
const editingAutomation = ref(null);

const AUTOMATION_TYPES = computed(() => [
  {
    value: 'send_message',
    label: t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.TYPE_SEND_MESSAGE'),
  },
  {
    value: 'move_after_hours',
    label: t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.TYPE_MOVE_AFTER_HOURS'),
  },
  {
    value: 'move_if_inactive',
    label: t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.TYPE_MOVE_IF_INACTIVE'),
  },
]);

const emptyForm = () => ({
  name: '',
  automation_type: 'send_message',
  channel_type: '',
  inbox_id: null,
  jabvox_email_template_id: null,
  jabvox_sms_provider_id: null,
  message_body: '',
  trigger_hours: null,
  target_stage_id: null,
  active: true,
});

const form = ref(emptyForm());

const isSendMessage = computed(
  () => form.value.automation_type === 'send_message'
);
const isMovement = computed(() =>
  ['move_after_hours', 'move_if_inactive'].includes(form.value.automation_type)
);

const applyChannelKey = key => {
  if (!key) {
    form.value.channel_type = '';
    form.value.inbox_id = null;
    form.value.jabvox_email_template_id = null;
    form.value.jabvox_sms_provider_id = null;
    return;
  }
  const [type, rawId] = key.split(':');
  const id = parseInt(rawId, 10);
  form.value.channel_type = type;
  form.value.inbox_id = type === 'inbox' ? id : null;
  form.value.jabvox_email_template_id = type === 'email' ? id : null;
  form.value.jabvox_sms_provider_id = type === 'sms' ? id : null;
};

const selectedChannelKey = computed({
  get: () => {
    if (form.value.channel_type === 'inbox' && form.value.inbox_id)
      return `inbox:${form.value.inbox_id}`;
    if (
      form.value.channel_type === 'email' &&
      form.value.jabvox_email_template_id
    )
      return `email:${form.value.jabvox_email_template_id}`;
    if (form.value.channel_type === 'sms' && form.value.jabvox_sms_provider_id)
      return `sms:${form.value.jabvox_sms_provider_id}`;
    return '';
  },
  set: applyChannelKey,
});

const showMessageBody = computed(
  () => form.value.channel_type === 'inbox' || form.value.channel_type === 'sms'
);

onMounted(() => {
  store.dispatch('jabvoxEmail/fetchAutomations', {
    funnelId: props.funnelId,
    stageId: props.stage.id,
  });
  store.dispatch('jabvoxEmail/fetchTemplates');
  store.dispatch('jabvoxSms/fetchProviders');
  store.dispatch('inboxes/get');
  store.dispatch('jabvoxKanban/fetchFunnels');
});

const openNew = () => {
  editingAutomation.value = null;
  form.value = emptyForm();
  showForm.value = true;
};

const openEdit = auto => {
  editingAutomation.value = auto;
  form.value = {
    name: auto.name,
    automation_type: auto.automation_type || 'send_message',
    channel_type: auto.channel_type || '',
    inbox_id: auto.inbox_id,
    jabvox_email_template_id: auto.jabvox_email_template_id,
    jabvox_sms_provider_id: auto.jabvox_sms_provider_id,
    message_body: auto.message_body || '',
    trigger_hours: auto.trigger_hours ?? null,
    target_stage_id: auto.target_stage_id ?? null,
    active: auto.active,
  };
  showForm.value = true;
};

const onSave = async () => {
  try {
    const payload = {
      funnelId: props.funnelId,
      stageId: props.stage.id,
      ...form.value,
    };
    if (editingAutomation.value) {
      await store.dispatch('jabvoxEmail/updateAutomation', {
        ...payload,
        id: editingAutomation.value.id,
      });
    } else {
      await store.dispatch('jabvoxEmail/createAutomation', payload);
    }
    useAlert(t('JABVOX_KANBAN.AUTOMATIONS_PANEL.SAVE'));
    showForm.value = false;
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('JABVOX_KANBAN.AUTOMATIONS_PANEL.SAVE')
    );
  }
};

const onDelete = async auto => {
  if (
    !window.confirm(
      `${t('JABVOX_KANBAN.AUTOMATIONS_PANEL.DELETE')} "${auto.name}"?`
    )
  )
    return;
  try {
    await store.dispatch('jabvoxEmail/deleteAutomation', {
      funnelId: props.funnelId,
      stageId: props.stage.id,
      id: auto.id,
    });
    useAlert(t('JABVOX_KANBAN.AUTOMATIONS_PANEL.DELETE'));
  } catch {
    useAlert(t('JABVOX_KANBAN.AUTOMATIONS_PANEL.DELETE'));
  }
};

const automationDisplay = auto => {
  const type = auto.automation_type || 'send_message';
  if (type === 'send_message') {
    if (auto.channel_type === 'inbox') {
      return (
        inboxes.value.find(i => i.id === auto.inbox_id)?.name ||
        t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.INBOX_LABEL')
      );
    }
    if (auto.channel_type === 'email') {
      const tpl = templates.value.find(
        tp => tp.id === auto.jabvox_email_template_id
      );
      return tpl
        ? `${tpl.name} — ${tpl.subject}`
        : t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.EMAIL_TEMPLATE_LABEL');
    }
    if (auto.channel_type === 'sms') {
      return (
        smsProviders.value.find(p => p.id === auto.jabvox_sms_provider_id)
          ?.name || t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.SMS_PROVIDER_LABEL')
      );
    }
    return t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.TYPE_SEND_MESSAGE');
  }
  const targetName =
    otherStages.value.find(s => s.id === auto.target_stage_id)?.name_jabvox ||
    '?';
  if (type === 'move_after_hours') {
    return `→ ${targetName} (${auto.trigger_hours}h)`;
  }
  if (type === 'move_if_inactive') {
    return t('JABVOX_KANBAN.AUTOMATIONS_PANEL.DISPLAY_INACTIVE', {
      target: targetName,
      hours: auto.trigger_hours,
    });
  }
  return type;
};

const badgeClass = auto => {
  const type = auto.automation_type || 'send_message';
  if (type === 'send_message') {
    if (auto.channel_type === 'inbox')
      return 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400';
    if (auto.channel_type === 'email')
      return 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400';
    if (auto.channel_type === 'sms')
      return 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400';
  }
  if (type === 'move_after_hours')
    return 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400';
  if (type === 'move_if_inactive')
    return 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400';
  return 'bg-slate-100 text-slate-600';
};
</script>

<template>
  <teleport to="body">
    <div class="fixed inset-0 z-50 flex" @click.self="emit('close')">
      <div class="absolute inset-0 bg-black/40" @click="emit('close')" />
      <div
        class="relative ml-auto w-full max-w-md h-full bg-white dark:bg-slate-900 shadow-2xl flex flex-col overflow-hidden"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-slate-200 dark:border-slate-700"
        >
          <div>
            <h2
              class="text-base font-semibold text-slate-800 dark:text-slate-100"
            >
              {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.TITLE') }}
            </h2>
            <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
              {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.STAGE_LABEL') }}
              <span class="font-medium">{{ stage.name_jabvox }}</span>
            </p>
          </div>
          <button
            class="w-8 h-8 flex items-center justify-center rounded-lg text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
            @click="emit('close')"
          >
            {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.CLOSE') }}
          </button>
        </div>

        <div class="flex-1 overflow-y-auto p-5 space-y-4">
          <!-- List view -->
          <div v-if="!showForm">
            <div class="flex justify-end mb-4">
              <button
                class="px-3 py-1.5 bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium rounded-lg transition-colors"
                @click="openNew"
              >
                {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.NEW') }}
              </button>
            </div>

            <div
              v-if="uiFlags.isFetchingAutomations"
              class="text-center py-8 text-slate-400 text-sm"
            >
              {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.LOADING') }}
            </div>

            <div
              v-else-if="!automations.length"
              class="text-center py-8 text-slate-400 text-sm"
            >
              {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.EMPTY') }}
            </div>

            <div v-else class="space-y-3">
              <div
                v-for="auto in automations"
                :key="auto.id"
                class="bg-slate-50 dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700 p-4"
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <span
                        class="text-sm font-medium text-slate-800 dark:text-slate-100 truncate"
                      >
                        {{ auto.name }}
                      </span>
                      <span
                        v-if="!auto.active"
                        class="text-xs px-1.5 py-0.5 bg-slate-200 dark:bg-slate-700 text-slate-500 rounded"
                      >
                        {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.INACTIVE') }}
                      </span>
                    </div>
                    <span
                      class="inline-flex items-center gap-1 mt-1 text-xs px-2 py-0.5 rounded-full"
                      :class="badgeClass(auto)"
                    >
                      {{ automationDisplay(auto) }}
                    </span>
                  </div>
                  <div class="flex gap-1 flex-shrink-0">
                    <button
                      class="text-xs px-2 py-1 rounded border border-slate-200 dark:border-slate-600 text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors"
                      @click="openEdit(auto)"
                    >
                      {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.EDIT') }}
                    </button>
                    <button
                      class="text-xs px-2 py-1 rounded border border-red-200 dark:border-red-800 text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                      @click="onDelete(auto)"
                    >
                      {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.DELETE') }}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Form view -->
          <div v-else class="space-y-4">
            <button
              class="text-sm text-slate-500 hover:text-slate-700 dark:text-slate-400 dark:hover:text-slate-200"
              @click="showForm = false"
            >
              {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.BACK') }}
            </button>

            <!-- Name -->
            <div class="space-y-1">
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300"
              >
                {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.NAME_LABEL') }}
              </label>
              <input
                v-model="form.name"
                type="text"
                :placeholder="
                  $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.NAME_PLACEHOLDER')
                "
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              />
            </div>

            <!-- Automation type -->
            <div class="space-y-1">
              <label
                class="block text-xs font-medium text-slate-600 dark:text-slate-300"
              >
                {{
                  $t(
                    'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.AUTOMATION_TYPE_LABEL'
                  )
                }}
              </label>
              <select
                v-model="form.automation_type"
                class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              >
                <option
                  v-for="at in AUTOMATION_TYPES"
                  :key="at.value"
                  :value="at.value"
                >
                  {{ at.label }}
                </option>
              </select>
            </div>

            <!-- Send message: unified channel selector -->
            <template v-if="isSendMessage">
              <div class="space-y-1">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                >
                  {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.CHANNEL_LABEL') }}
                </label>
                <select
                  v-model="selectedChannelKey"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                >
                  <option value="" disabled>
                    {{
                      $t(
                        'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.CHANNEL_PLACEHOLDER'
                      )
                    }}
                  </option>
                  <optgroup
                    :label="
                      $t(
                        'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.CHANNEL_GROUP_INBOXES'
                      )
                    "
                  >
                    <option
                      v-for="inbox in inboxes"
                      :key="inbox.id"
                      :value="`inbox:${inbox.id}`"
                    >
                      {{ inbox.name }}
                    </option>
                    <option v-if="!inboxes.length" disabled value="">
                      {{
                        $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.CHANNEL_EMPTY')
                      }}
                    </option>
                  </optgroup>
                  <optgroup
                    :label="
                      $t(
                        'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.CHANNEL_GROUP_EMAIL'
                      )
                    "
                  >
                    <option
                      v-for="tpl in templates"
                      :key="tpl.id"
                      :value="`email:${tpl.id}`"
                    >
                      {{ tpl.name
                      }}{{
                        $t(
                          'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.EMAIL_TEMPLATE_FORMAT'
                        )
                      }}{{ tpl.subject }}
                    </option>
                    <option v-if="!templates.length" disabled value="">
                      {{
                        $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.CHANNEL_EMPTY')
                      }}
                    </option>
                  </optgroup>
                  <optgroup
                    :label="
                      $t(
                        'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.CHANNEL_GROUP_SMS'
                      )
                    "
                  >
                    <option
                      v-for="p in smsProviders"
                      :key="p.id"
                      :value="`sms:${p.id}`"
                    >
                      {{ p.name }}
                    </option>
                    <option v-if="!smsProviders.length" disabled value="">
                      {{
                        $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.CHANNEL_EMPTY')
                      }}
                    </option>
                  </optgroup>
                </select>
              </div>

              <!-- Message body -->
              <div v-if="showMessageBody" class="space-y-1">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                >
                  {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.MESSAGE_LABEL') }}
                  <span class="text-slate-400 font-normal ml-1">
                    {{
                      $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.VARIABLES_HINT')
                    }}
                    {{
                      $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.VARIABLES_LIST')
                    }}
                  </span>
                </label>
                <textarea
                  v-model="form.message_body"
                  rows="4"
                  :placeholder="
                    $t(
                      'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.MESSAGE_PLACEHOLDER'
                    )
                  "
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500 resize-none"
                />
              </div>
            </template>

            <!-- Movement type fields -->
            <template v-if="isMovement">
              <div class="space-y-1">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                >
                  {{
                    $t(
                      'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.TRIGGER_HOURS_LABEL'
                    )
                  }}
                </label>
                <input
                  v-model.number="form.trigger_hours"
                  type="number"
                  min="1"
                  class="w-32 rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                />
              </div>

              <div class="space-y-1">
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300"
                >
                  {{
                    $t(
                      'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.TARGET_STAGE_LABEL'
                    )
                  }}
                </label>
                <select
                  v-model.number="form.target_stage_id"
                  class="w-full rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-700 text-sm px-3 py-2 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                >
                  <option value="" disabled>
                    {{
                      $t(
                        'JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.TARGET_STAGE_PLACEHOLDER'
                      )
                    }}
                  </option>
                  <option v-for="s in otherStages" :key="s.id" :value="s.id">
                    {{ s.name_jabvox }}
                  </option>
                </select>
              </div>
            </template>

            <label class="flex items-center gap-2 cursor-pointer">
              <input v-model="form.active" type="checkbox" class="rounded" />
              <span class="text-sm text-slate-700 dark:text-slate-300">
                {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.FORM.ACTIVE_LABEL') }}
              </span>
            </label>

            <div class="flex gap-3 pt-2">
              <button
                :disabled="uiFlags.isSaving"
                class="px-4 py-2 bg-woot-500 hover:bg-woot-600 text-white text-sm font-medium rounded-lg transition-colors disabled:opacity-50"
                @click="onSave"
              >
                {{
                  uiFlags.isSaving
                    ? $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.SAVING')
                    : $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.SAVE')
                }}
              </button>
              <button
                class="px-4 py-2 border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-300 text-sm font-medium rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
                @click="showForm = false"
              >
                {{ $t('JABVOX_KANBAN.AUTOMATIONS_PANEL.CANCEL') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </teleport>
</template>
