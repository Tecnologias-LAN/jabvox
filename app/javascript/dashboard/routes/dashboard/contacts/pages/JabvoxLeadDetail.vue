<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import messageAPI from 'dashboard/api/inbox/message';
import Button from 'dashboard/components-next/button/Button.vue';
import JabvoxConversationProducts from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationProducts.vue';
import JabvoxConversationHistory from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationHistory.vue';
import JabvoxCallButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxCallButton.vue';
import JabvoxSmsButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxSmsButton.vue';
import JabvoxEmailButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxEmailButton.vue';
import JabvoxQuickButtons from 'dashboard/components/widgets/conversation/jabvox/JabvoxQuickButtons.vue';
import ManagementQuestionsForm from 'dashboard/components/jabvox/managementStates/ManagementQuestionsForm.vue';
import {
  isManagementValid,
  buildManagementContentAttributes,
} from 'dashboard/composables/jabvox/useManagementState';

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const lead = useMapGetter('jabvoxLeads/getCurrentLead');
const leads = useMapGetter('jabvoxLeads/getLeads');
const uiFlags = useMapGetter('jabvoxLeads/getUIFlags');
const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');
const inboxes = useMapGetter('inboxes/getInboxes');
const contactNotesGetterFn = useMapGetter(
  'contactNotes/getAllNotesByContactId'
);

const activeTab = ref(route.query.tab || 'chat');
const messages = ref([]);
const isLoadingMessages = ref(false);
const newMessage = ref('');
const isSending = ref(false);
const isNoteMode = ref(false);
const managementStateId = ref(null);
const managementAnswers = ref({});
const chatContainer = ref(null);
const notesContainer = ref(null);

const contactNotesList = computed(() =>
  lead.value?.contact?.id
    ? contactNotesGetterFn.value(lead.value.contact.id)
    : []
);

const selectedManagementState = computed(() =>
  managementStates.value.find(s => s.id === managementStateId.value)
);

const selectedInboxId = ref(null);
const initialMessage = ref('');
const isStarting = ref(false);

const accountId = computed(() => route.params.accountId);
const leadId = computed(() => route.params.leadId);

const isCustomizationEnabled = computed(() =>
  store.getters['accounts/isFeatureEnabledonAccount'](
    accountId.value,
    FEATURE_FLAGS.JABVOX_CUSTOMIZATION
  )
);

const availableTabs = computed(() => ['chat', 'notes', 'products', 'history']);

const leadsTable = computed(() => {
  try {
    return store.getters['jabvoxCustomization/getLeadsTable'];
  } catch {
    return null;
  }
});

const leadsTableColumns = computed(() => leadsTable.value?.columns || []);

// ── Inline edit (contact fields + campaign + assignee + custom fields) ──
// The whole left panel is read-only until "Editar" is pressed. Then the
// editable fields turn into inputs and "Guardar"/"Cancelar" appear.
const isEditing = ref(false);
const isSavingFields = ref(false);
const assignees = useMapGetter('agents/getAgents');
const editForm = ref({
  phone_number: '',
  email: '',
  country: '',
  campaign_name: '',
  assignee_id: null,
  custom: {},
});

const initEditForm = () => {
  if (!lead.value) return;
  const existing = lead.value.custom_fields_jabvox || {};
  const custom = {};
  leadsTableColumns.value.forEach(col => {
    custom[col.name_jabvox] = existing[col.name_jabvox] ?? '';
  });
  editForm.value = {
    phone_number: lead.value.contact?.phone_number || '',
    email: lead.value.contact?.email || '',
    country: lead.value.contact?.country || '',
    campaign_name: lead.value.campaign?.name || '',
    assignee_id: lead.value.assignee_id ?? null,
    custom,
  };
};

const startEdit = () => {
  initEditForm();
  isEditing.value = true;
};
const cancelEdit = () => {
  isEditing.value = false;
};

const saveAll = async () => {
  if (!lead.value || isSavingFields.value) return;
  isSavingFields.value = true;
  try {
    await store.dispatch('jabvoxLeads/updateLeadDetails', {
      id: lead.value.id,
      contact: {
        phone_number: editForm.value.phone_number,
        email: editForm.value.email,
        country: editForm.value.country,
      },
      campaign_name: editForm.value.campaign_name,
      assignee_id: editForm.value.assignee_id,
      custom_fields: editForm.value.custom,
    });
    await store.dispatch('jabvoxLeads/fetchLead', leadId.value);
    isEditing.value = false;
    useAlert(t('JABVOX_LEADS.DETAIL.CUSTOM_FIELDS_SAVED'));
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.CUSTOM_FIELDS_ERROR'));
  } finally {
    isSavingFields.value = false;
  }
};

const currentIndex = computed(() =>
  leads.value.findIndex(l => String(l.id) === String(leadId.value))
);
const prevLead = computed(() =>
  currentIndex.value > 0 ? leads.value[currentIndex.value - 1] : null
);
const nextLead = computed(() =>
  currentIndex.value >= 0 && currentIndex.value < leads.value.length - 1
    ? leads.value[currentIndex.value + 1]
    : null
);

const sortedMessages = computed(() =>
  [...messages.value].sort(
    (a, b) => new Date(a.created_at) - new Date(b.created_at)
  )
);

const privateNotes = computed(() =>
  sortedMessages.value.filter(m => m.message_type === 2 || m.private)
);

const isPrivateNote = m => m.message_type === 2 || m.private;
const isIncoming = m => m.message_type === 0;

const msgBubbleClass = m => {
  if (isPrivateNote(m))
    return 'bg-n-amber-3 border border-n-amber-6 text-n-amber-11';
  if (isIncoming(m)) return 'bg-n-alpha-2 text-n-slate-12';
  return 'bg-n-brand text-white ml-auto';
};

const msgAlignClass = m =>
  isPrivateNote(m) || isIncoming(m) ? 'items-start' : 'items-end';

const formatTime = dateVal => {
  const ms = typeof dateVal === 'number' ? dateVal * 1000 : dateVal;
  return new Date(ms).toLocaleString('es-CO', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const scrollToBottom = container => {
  setTimeout(() => {
    if (container?.value) {
      container.value.scrollTop = container.value.scrollHeight;
    }
  }, 50);
};

const loadMessages = async () => {
  if (!lead.value?.conversation_display_id) return;
  isLoadingMessages.value = true;
  try {
    const response = await messageAPI.getPreviousMessages({
      conversationId: lead.value.conversation_display_id,
      before: undefined,
      after: undefined,
    });
    messages.value = response.data?.payload || [];
    scrollToBottom(chatContainer);
    scrollToBottom(notesContainer);
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.LOAD_MESSAGES_ERROR'));
  } finally {
    isLoadingMessages.value = false;
  }
};

const loadContactNotes = () => {
  if (!lead.value?.contact?.id) return;
  store.dispatch('contactNotes/get', { contactId: lead.value.contact.id });
};

const sendMessage = async (privateFlag = false) => {
  const content = newMessage.value.trim();
  if (!content || isSending.value) return;

  if (
    privateFlag &&
    selectedManagementState.value &&
    !isManagementValid(
      selectedManagementState.value,
      managementAnswers.value,
      content
    )
  ) {
    useAlert(t('JABVOX_MANAGEMENT_STATES.QUESTIONS.INCOMPLETE'));
    return;
  }

  if (privateFlag && !lead.value?.conversation_display_id) {
    if (managementStates.value.length > 0 && !managementStateId.value) return;
    isSending.value = true;
    try {
      const contentAttributes = managementStateId.value
        ? buildManagementContentAttributes(
            selectedManagementState.value,
            managementAnswers.value
          )
        : {};
      await store.dispatch('contactNotes/create', {
        contactId: lead.value.contact.id,
        content,
        contentAttributes,
      });
      newMessage.value = '';
      managementStateId.value = null;
      managementAnswers.value = {};
      scrollToBottom(notesContainer);
    } catch {
      useAlert(t('JABVOX_LEADS.DETAIL.SEND_ERROR'));
    } finally {
      isSending.value = false;
    }
    return;
  }

  if (!lead.value?.conversation_display_id) return;
  if (
    privateFlag &&
    managementStates.value.length > 0 &&
    !managementStateId.value
  )
    return;
  isSending.value = true;
  try {
    const payload = {
      conversationId: lead.value.conversation_display_id,
      message: content,
      private: privateFlag,
      echo_id: `jabvox_${Date.now()}`,
    };
    if (privateFlag && managementStateId.value) {
      payload.contentAttributes = buildManagementContentAttributes(
        selectedManagementState.value,
        managementAnswers.value
      );
    }
    const response = await messageAPI.create(payload);
    messages.value.push(response.data);
    newMessage.value = '';
    managementStateId.value = null;
    managementAnswers.value = {};
    scrollToBottom(privateFlag ? notesContainer : chatContainer);
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.SEND_ERROR'));
  } finally {
    isSending.value = false;
  }
};

const onChatKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage(isNoteMode.value);
  }
};

const onNoteKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage(true);
  }
};

const goToLead = id => {
  router.push({
    name: 'jabvox_lead_detail',
    params: { accountId: accountId.value, leadId: id },
  });
};

const goBack = () => {
  router.push({
    name: 'jabvox_leads_index',
    params: { accountId: accountId.value },
  });
};

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleDateString('es', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  });
};

const startConversation = async () => {
  if (!selectedInboxId.value || isStarting.value) return;
  isStarting.value = true;
  try {
    const selectedInbox = inboxes.value.find(
      i => i.id === selectedInboxId.value
    );
    const isWhatsApp = selectedInbox?.channel_type === 'Channel::Whatsapp';
    const params = {
      contactId: lead.value.contact.id,
      inboxId: selectedInboxId.value,
    };
    if (initialMessage.value.trim()) {
      params.message = { content: initialMessage.value.trim() };
    }
    await store.dispatch('contactConversations/create', {
      params,
      isFromWhatsApp: isWhatsApp,
    });
    initialMessage.value = '';
    selectedInboxId.value = null;
    await store.dispatch('jabvoxLeads/fetchLead', leadId.value);
    loadMessages();
  } catch {
    useAlert(t('JABVOX_LEADS.DETAIL.START_CONV_ERROR'));
  } finally {
    isStarting.value = false;
  }
};

const loadLead = async () => {
  await store.dispatch('jabvoxLeads/fetchLead', leadId.value);
  messages.value = [];
  newMessage.value = '';
  managementStateId.value = null;
  managementAnswers.value = {};
  isEditing.value = false;
  initEditForm();
  loadMessages();
  loadContactNotes();
};

watch(leadId, loadLead);
watch(leadsTableColumns, initEditForm, { deep: true });
onMounted(async () => {
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('agents/get');
  if (isCustomizationEnabled.value) {
    await store.dispatch('jabvoxCustomization/fetchTables');
  }
  loadLead();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-background">
    <!-- Header -->
    <div
      class="shrink-0 border-b border-n-weak bg-n-solid-1 px-6 py-3.5 flex items-center gap-4"
    >
      <button
        class="flex items-center gap-1.5 h-8 px-2.5 rounded-lg text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
        @click="goBack"
      >
        <span class="i-lucide-arrow-left size-4" />
        {{ t('JABVOX_LEADS.DETAIL.BACK') }}
      </button>

      <div class="flex-1" />

      <div v-if="leads.length > 1" class="flex items-center gap-2">
        <button
          :disabled="!prevLead"
          class="group flex items-center gap-2 h-9 pl-2.5 pr-3.5 rounded-xl border border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-brand hover:text-n-brand disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          @click="prevLead && goToLead(prevLead.id)"
        >
          <span
            class="i-lucide-chevron-left size-4 group-hover:-translate-x-0.5 transition-transform"
          />
          <span class="text-left">
            <span
              class="block text-[10px] text-n-slate-10 leading-none uppercase tracking-wide"
            >
              {{ t('JABVOX_LEADS.DETAIL.PREV') }}
            </span>
            <span
              class="block text-xs font-medium truncate max-w-[110px] leading-tight mt-0.5 text-n-slate-12"
            >
              {{ prevLead?.contact?.name || '···' }}
            </span>
          </span>
        </button>
        <span
          class="text-xs font-medium text-n-slate-10 tabular-nums whitespace-nowrap px-1"
        >
          {{ currentIndex + 1 }}&thinsp;/&thinsp;{{ leads.length }}
        </span>
        <button
          :disabled="!nextLead"
          class="group flex items-center gap-2 h-9 pl-3.5 pr-2.5 rounded-xl border border-n-weak bg-n-solid-1 text-n-slate-11 hover:border-n-brand hover:text-n-brand disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
          @click="nextLead && goToLead(nextLead.id)"
        >
          <span class="text-right">
            <span
              class="block text-[10px] text-n-slate-10 leading-none uppercase tracking-wide"
            >
              {{ t('JABVOX_LEADS.DETAIL.NEXT') }}
            </span>
            <span
              class="block text-xs font-medium truncate max-w-[110px] leading-tight mt-0.5 text-n-slate-12"
            >
              {{ nextLead?.contact?.name || '···' }}
            </span>
          </span>
          <span
            class="i-lucide-chevron-right size-4 group-hover:translate-x-0.5 transition-transform"
          />
        </button>
      </div>
    </div>

    <!-- Loading lead -->
    <div
      v-if="uiFlags.isFetchingOne"
      class="flex-1 flex items-center justify-center gap-2 text-sm text-n-slate-10 animate-pulse"
    >
      <span class="i-lucide-loader-circle size-4 animate-spin" />
      {{ t('JABVOX_LEADS.DETAIL.LOADING') }}
    </div>

    <!-- Not found -->
    <div
      v-else-if="!lead"
      class="flex-1 flex flex-col items-center justify-center gap-2 text-sm text-n-slate-10"
    >
      <span class="i-lucide-search-x size-8 text-n-slate-9" />
      {{ t('JABVOX_LEADS.DETAIL.NOT_FOUND') }}
    </div>

    <!-- Content -->
    <div v-else class="flex-1 min-h-0 flex flex-col lg:flex-row">
      <!-- Left panel: lead info -->
      <div
        class="lg:w-80 shrink-0 border-b lg:border-b-0 lg:border-r border-n-weak bg-n-solid-1 p-5 space-y-4 overflow-y-auto"
      >
        <!-- Contact avatar + name -->
        <div class="flex flex-col items-center text-center gap-3 pb-1">
          <img
            v-if="lead.contact.avatar_url"
            :src="lead.contact.avatar_url"
            :alt="lead.contact.name"
            class="size-16 rounded-full object-cover shrink-0 ring-2 ring-n-weak"
          />
          <div
            v-else
            class="size-16 rounded-full bg-n-brand/10 flex items-center justify-center shrink-0 text-2xl font-semibold text-n-brand ring-2 ring-n-brand/20"
          >
            {{ lead.contact.name?.charAt(0)?.toUpperCase() || '?' }}
          </div>
          <div class="min-w-0 w-full">
            <button
              class="text-base font-semibold text-n-slate-12 hover:text-n-brand transition-colors truncate max-w-full"
              @click="
                router.push({
                  name: 'contacts_edit',
                  params: { accountId: accountId, contactId: lead.contact.id },
                })
              "
            >
              {{ lead.contact.name || '—' }}
            </button>
            <p class="text-xs text-n-slate-10 font-mono mt-0.5">
              #{{ lead.lead_number }}
            </p>
          </div>
        </div>

        <!-- Edit / Save / Cancel -->
        <div class="flex justify-end gap-2">
          <template v-if="!isEditing">
            <Button
              size="small"
              variant="ghost"
              icon="i-lucide-pencil"
              :label="t('JABVOX_LEADS.DETAIL.EDIT')"
              @click="startEdit"
            />
          </template>
          <template v-else>
            <Button
              size="small"
              variant="ghost"
              :label="t('JABVOX_LEADS.DETAIL.CANCEL')"
              @click="cancelEdit"
            />
            <Button
              size="small"
              icon="i-lucide-check"
              :is-loading="isSavingFields"
              :label="t('JABVOX_LEADS.DETAIL.SAVE')"
              @click="saveAll"
            />
          </template>
        </div>

        <!-- Info rows -->
        <dl
          class="rounded-xl border border-n-weak bg-n-background divide-y divide-n-weak overflow-hidden"
        >
          <!-- Phone (editable) -->
          <div
            v-if="isEditing || lead.contact.phone_number"
            class="flex items-center gap-2 px-3 py-2.5"
          >
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.PHONE') }}
            </dt>
            <input
              v-if="isEditing"
              v-model="editForm.phone_number"
              class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
            />
            <dd
              v-else
              class="text-sm text-n-slate-12 font-mono truncate flex-1 text-right"
            >
              {{ lead.contact.phone_number || '—' }}
            </dd>
          </div>
          <!-- Email (editable) -->
          <div class="flex items-center gap-2 px-3 py-2.5">
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.EMAIL') }}
            </dt>
            <input
              v-if="isEditing"
              v-model="editForm.email"
              type="email"
              class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
            />
            <dd
              v-else
              class="text-sm text-n-slate-12 truncate flex-1 text-right"
            >
              {{ lead.contact.email || '—' }}
            </dd>
          </div>
          <!-- Country (editable) -->
          <div
            v-if="isEditing || lead.contact.country"
            class="flex items-center gap-2 px-3 py-2.5"
          >
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.COUNTRY') }}
            </dt>
            <input
              v-if="isEditing"
              v-model="editForm.country"
              class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
            />
            <dd v-else class="text-sm text-n-slate-12 flex-1 text-right">
              {{ lead.contact.country }}
            </dd>
          </div>
          <!-- Campaign (editable) -->
          <div class="flex items-center gap-2 px-3 py-2.5">
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.CAMPAIGN') }}
            </dt>
            <input
              v-if="isEditing"
              v-model="editForm.campaign_name"
              class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
            />
            <dd v-else class="text-sm text-n-slate-12 flex-1 text-right">
              {{ lead.campaign?.name || '—' }}
            </dd>
          </div>
          <!-- Affiliate (read-only) -->
          <div class="flex items-center gap-2 px-3 py-2.5">
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.AFFILIATE') }}
            </dt>
            <dd class="text-sm text-n-slate-12 flex-1 text-right">
              {{ lead.affiliate_name || t('JABVOX_LEADS.TABLE.AFFILIATE_OWN') }}
            </dd>
          </div>
          <!-- Inbox (read-only) -->
          <div class="flex items-center gap-2 px-3 py-2.5">
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.INBOX') }}
            </dt>
            <dd class="text-sm text-n-slate-12 flex-1 text-right">
              {{ lead.inbox_name || '—' }}
            </dd>
          </div>
          <!-- Assignee (editable) -->
          <div class="flex items-center gap-2 px-3 py-2.5">
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.ASSIGNEE') }}
            </dt>
            <select
              v-if="isEditing"
              v-model="editForm.assignee_id"
              class="reset-base flex-1 rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
            >
              <option :value="null">—</option>
              <option v-for="a in assignees" :key="a.id" :value="a.id">
                {{ a.name }}
              </option>
            </select>
            <dd v-else class="text-sm text-n-slate-12 flex-1 text-right">
              {{ lead.assignee_name || '—' }}
            </dd>
          </div>
          <!-- Last management (read-only, comes from notes) -->
          <div
            v-if="lead.last_management_state"
            class="flex items-center gap-2 px-3 py-2.5"
          >
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.MANAGEMENT_STATE') }}
            </dt>
            <dd class="flex-1 text-right">
              <span
                class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-n-brand/10 text-n-brand"
              >
                {{ lead.last_management_state }}
              </span>
            </dd>
          </div>
          <!-- Created at (read-only) -->
          <div class="flex items-center gap-2 px-3 py-2.5">
            <dt class="text-xs text-n-slate-10 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.CREATED_AT') }}
            </dt>
            <dd class="text-sm text-n-slate-12 flex-1 text-right">
              {{ formatDate(lead.created_at) }}
            </dd>
          </div>
        </dl>
        <!-- Custom fields inline (tabla vinculada a leads) -->
        <div
          v-if="isCustomizationEnabled && leadsTableColumns.length"
          class="rounded-xl border border-n-weak bg-n-background p-3 space-y-2.5"
        >
          <p
            class="text-xs font-semibold text-n-slate-11 uppercase tracking-wide"
          >
            {{ leadsTable.name_jabvox }}
          </p>
          <dl class="space-y-2.5">
            <div v-for="col in leadsTableColumns" :key="col.id">
              <dt class="text-xs text-n-slate-10 mb-1">
                {{ col.label_jabvox }}
              </dt>
              <dd>
                <!-- Read-only view -->
                <span v-if="!isEditing" class="text-sm text-n-slate-12">
                  <template v-if="col.column_type_jabvox === 'boolean'">
                    {{
                      lead.custom_fields_jabvox?.[col.name_jabvox]
                        ? t('JABVOX_LEADS.DETAIL.YES')
                        : t('JABVOX_LEADS.DETAIL.NO')
                    }}
                  </template>
                  <template v-else>
                    {{ lead.custom_fields_jabvox?.[col.name_jabvox] || '—' }}
                  </template>
                </span>
                <!-- boolean -->
                <input
                  v-else-if="col.column_type_jabvox === 'boolean'"
                  v-model="editForm.custom[col.name_jabvox]"
                  type="checkbox"
                  class="reset-base size-4 rounded border-n-weak text-n-brand focus:outline-none focus:border-n-slate-7"
                />
                <!-- select -->
                <select
                  v-else-if="col.column_type_jabvox === 'select'"
                  v-model="editForm.custom[col.name_jabvox]"
                  class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
                >
                  <option value="">—</option>
                  <option
                    v-for="opt in col.options_jabvox || []"
                    :key="opt"
                    :value="opt"
                  >
                    {{ opt }}
                  </option>
                </select>
                <!-- date -->
                <input
                  v-else-if="col.column_type_jabvox === 'date'"
                  v-model="editForm.custom[col.name_jabvox]"
                  type="date"
                  class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
                />
                <!-- text / integer / float -->
                <input
                  v-else
                  v-model="editForm.custom[col.name_jabvox]"
                  :type="
                    col.column_type_jabvox === 'integer' ||
                    col.column_type_jabvox === 'float'
                      ? 'number'
                      : 'text'
                  "
                  :step="col.column_type_jabvox === 'float' ? '0.01' : '1'"
                  class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-2.5 py-1.5 focus:outline-none focus:border-n-slate-7 transition-colors"
                />
              </dd>
            </div>
          </dl>
        </div>

        <div v-if="lead.contact" class="pt-1">
          <JabvoxQuickButtons :lead="lead" :contact="lead.contact" />
        </div>
      </div>

      <!-- Right panel: tabs -->
      <div class="flex-1 flex flex-col min-w-0 min-h-0 bg-n-background">
        <!-- Tab bar -->
        <div
          class="shrink-0 border-b border-n-weak bg-n-solid-1 flex items-center gap-1 px-4"
        >
          <button
            v-for="tab in availableTabs"
            :key="tab"
            class="px-3.5 py-3 text-sm font-medium border-b-2 -mb-px transition-colors"
            :class="
              activeTab === tab
                ? 'border-n-brand text-n-brand'
                : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
            "
            @click="activeTab = tab"
          >
            {{ t(`JABVOX_LEADS.DETAIL.TABS.${tab.toUpperCase()}`) }}
          </button>
          <div class="flex-1" />
          <JabvoxCallButton
            v-if="lead.contact.phone_number || lead.contact.id"
            :phone="lead.contact.phone_number || ''"
            :contact-id="lead.contact.id"
            :lead-id="Number(leadId) || null"
            :contact-name="lead.contact.name"
            show-label
          />
          <JabvoxSmsButton
            v-if="lead.contact.phone_number && lead.contact.id"
            :phone="lead.contact.phone_number"
            :contact-id="lead.contact.id"
            show-label
          />
          <JabvoxEmailButton
            v-if="lead.contact.email && lead.contact.id"
            :email="lead.contact.email"
            :contact-id="lead.contact.id"
            show-label
          />
        </div>

        <!-- ── CHAT TAB ── -->
        <template v-if="activeTab === 'chat'">
          <div
            v-if="!lead.conversation_display_id"
            class="flex-1 flex flex-col items-center justify-center px-6 py-10 gap-5"
          >
            <div
              class="size-14 rounded-2xl bg-n-brand/10 flex items-center justify-center"
            >
              <span class="i-lucide-message-circle-plus size-7 text-n-brand" />
            </div>
            <div class="text-center max-w-xs">
              <p class="text-sm font-semibold text-n-slate-12 mb-1">
                {{ t('JABVOX_LEADS.DETAIL.CONTACT_VIA') }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{ t('JABVOX_LEADS.DETAIL.CONTACT_VIA_HINT') }}
              </p>
            </div>
            <div class="w-full max-w-sm space-y-3">
              <select
                v-model="selectedInboxId"
                class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
              >
                <option :value="null" disabled>
                  {{ t('JABVOX_LEADS.DETAIL.SELECT_INBOX') }}
                </option>
                <option
                  v-for="inbox in inboxes"
                  :key="inbox.id"
                  :value="inbox.id"
                >
                  {{ inbox.name }}
                </option>
              </select>
              <textarea
                v-model="initialMessage"
                rows="2"
                :placeholder="
                  t('JABVOX_LEADS.DETAIL.INITIAL_MESSAGE_PLACEHOLDER')
                "
                class="reset-base w-full rounded-lg border border-n-weak bg-n-solid-1 text-sm px-3 py-2 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:border-n-slate-7 transition-colors resize-none"
              />
              <Button
                :label="
                  isStarting
                    ? t('JABVOX_LEADS.DETAIL.STARTING')
                    : t('JABVOX_LEADS.DETAIL.START_CONVERSATION')
                "
                icon="i-lucide-send"
                :disabled="!selectedInboxId || isStarting"
                class="w-full justify-center"
                @click="startConversation"
              />
            </div>
          </div>
          <template v-else>
            <div
              ref="chatContainer"
              class="flex-1 overflow-y-auto px-4 py-4 space-y-3 min-h-0"
            >
              <div
                v-if="isLoadingMessages"
                class="flex items-center justify-center gap-2 py-8 text-sm text-n-slate-10 animate-pulse"
              >
                <span class="i-lucide-loader-circle size-4 animate-spin" />
                {{ t('JABVOX_LEADS.DETAIL.LOADING_MESSAGES') }}
              </div>
              <template v-else>
                <div
                  v-for="msg in sortedMessages"
                  :key="msg.id"
                  class="flex flex-col gap-1"
                  :class="msgAlignClass(msg)"
                >
                  <div
                    v-if="msg.content"
                    class="max-w-[85%] rounded-2xl px-3.5 py-2 text-sm whitespace-pre-wrap break-words shadow-sm"
                    :class="msgBubbleClass(msg)"
                  >
                    <div
                      v-if="isPrivateNote(msg)"
                      class="flex items-center gap-1 mb-1 text-xs text-n-amber-11 font-medium"
                    >
                      <span class="i-lucide-sticky-note size-3.5" />
                      {{ t('JABVOX_LEADS.DETAIL.NOTE_LABEL') }}
                    </div>
                    <div
                      v-if="
                        isPrivateNote(msg) &&
                        msg.content_attributes?.jabvox_management_state_name
                      "
                      class="inline-flex items-center gap-1 mb-1 px-2 py-0.5 rounded-full text-[11px] font-semibold text-white"
                      :style="{
                        backgroundColor:
                          msg.content_attributes
                            .jabvox_management_state_color || '#6b7280',
                      }"
                    >
                      {{ msg.content_attributes.jabvox_management_state_name }}
                    </div>
                    {{ msg.content }}
                  </div>
                  <span class="text-[11px] text-n-slate-10 px-1">
                    {{ formatTime(msg.created_at) }}
                  </span>
                </div>
                <div
                  v-if="sortedMessages.length === 0"
                  class="flex flex-col items-center justify-center gap-2 py-10 text-sm text-n-slate-10"
                >
                  <span
                    class="i-lucide-messages-square size-7 text-n-slate-9"
                  />
                  {{ t('JABVOX_LEADS.DETAIL.NO_MESSAGES') }}
                </div>
              </template>
            </div>

            <div
              class="shrink-0 border-t border-n-weak bg-n-solid-1 p-3 space-y-2"
            >
              <div class="flex gap-2">
                <button
                  class="text-xs px-2.5 py-1 rounded-md font-medium transition-colors"
                  :class="
                    !isNoteMode
                      ? 'bg-n-brand text-white'
                      : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="isNoteMode = false"
                >
                  {{ t('JABVOX_LEADS.DETAIL.REPLY') }}
                </button>
                <button
                  class="text-xs px-2.5 py-1 rounded-md font-medium transition-colors"
                  :class="
                    isNoteMode
                      ? 'bg-n-amber-9 text-white'
                      : 'bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12'
                  "
                  @click="isNoteMode = true"
                >
                  {{ t('JABVOX_LEADS.DETAIL.ADD_NOTE') }}
                </button>
              </div>
              <div
                v-if="isNoteMode && managementStates.length > 0"
                class="flex items-center gap-2"
              >
                <label
                  class="text-xs font-medium text-n-slate-11 whitespace-nowrap shrink-0"
                >
                  {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.LABEL') }}
                </label>
                <select
                  v-model="managementStateId"
                  class="reset-base flex-1 rounded-lg border text-xs px-2.5 py-1.5 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
                  :class="
                    managementStateId ? 'border-n-weak' : 'border-n-amber-6'
                  "
                >
                  <option :value="null" disabled>
                    {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.PLACEHOLDER') }}
                  </option>
                  <option
                    v-for="s in managementStates"
                    :key="s.id"
                    :value="s.id"
                  >
                    {{ s.name_jabvox }}
                  </option>
                </select>
              </div>
              <ManagementQuestionsForm
                v-if="isNoteMode && selectedManagementState"
                v-model="managementAnswers"
                :state="selectedManagementState"
                class="mt-2"
              />
              <div class="flex gap-2 items-end">
                <textarea
                  v-model="newMessage"
                  rows="2"
                  :placeholder="
                    isNoteMode
                      ? t('JABVOX_LEADS.DETAIL.NOTE_PLACEHOLDER')
                      : t('JABVOX_LEADS.DETAIL.MESSAGE_PLACEHOLDER')
                  "
                  class="reset-base flex-1 resize-none rounded-lg border border-n-weak bg-n-solid-1 text-sm text-n-slate-12 px-3 py-2 focus:outline-none focus:border-n-slate-7 transition-colors placeholder-n-slate-9"
                  @keydown="onChatKeydown"
                />
                <Button
                  size="small"
                  :is-loading="isSending"
                  :disabled="!newMessage.trim()"
                  icon="i-lucide-send"
                  @click="sendMessage(isNoteMode)"
                />
              </div>
            </div>
          </template>
        </template>

        <!-- ── NOTES TAB (private notes only) ── -->
        <template v-else-if="activeTab === 'notes'">
          <div class="flex flex-col flex-1 min-h-0 overflow-hidden">
            <div
              ref="notesContainer"
              class="flex-1 overflow-y-auto px-4 py-4 space-y-3 min-h-0"
            >
              <div
                v-if="isLoadingMessages"
                class="flex items-center justify-center gap-2 py-8 text-sm text-n-slate-10 animate-pulse"
              >
                <span class="i-lucide-loader-circle size-4 animate-spin" />
                {{ t('JABVOX_LEADS.DETAIL.LOADING_MESSAGES') }}
              </div>
              <template v-else>
                <template v-if="lead.conversation_display_id">
                  <div
                    v-for="note in privateNotes"
                    :key="note.id"
                    class="flex flex-col gap-1 items-start"
                  >
                    <div
                      v-if="note.content"
                      class="max-w-[85%] rounded-2xl px-3.5 py-2 text-sm whitespace-pre-wrap break-words bg-n-amber-3 border border-n-amber-6 text-n-amber-11 shadow-sm"
                    >
                      <div
                        v-if="
                          note.content_attributes?.jabvox_management_state_name
                        "
                        class="inline-flex items-center gap-1 mb-1 px-2 py-0.5 rounded-full text-[11px] font-semibold text-white"
                        :style="{
                          backgroundColor:
                            note.content_attributes
                              .jabvox_management_state_color || '#6b7280',
                        }"
                      >
                        {{
                          note.content_attributes.jabvox_management_state_name
                        }}
                      </div>
                      {{ note.content }}
                    </div>
                    <span class="text-[11px] text-n-slate-10 px-1">
                      {{ formatTime(note.created_at) }}
                    </span>
                  </div>
                  <div
                    v-if="privateNotes.length === 0"
                    class="flex flex-col items-center justify-center gap-2 py-10 text-sm text-n-slate-10"
                  >
                    <span class="i-lucide-sticky-note size-7 text-n-slate-9" />
                    {{ t('JABVOX_LEADS.DETAIL.NO_NOTES') }}
                  </div>
                </template>
                <template v-else>
                  <div
                    v-for="note in contactNotesList"
                    :key="note.id"
                    class="flex flex-col gap-1 items-start"
                  >
                    <div
                      v-if="note.content"
                      class="max-w-[85%] rounded-2xl px-3.5 py-2 text-sm whitespace-pre-wrap break-words bg-n-amber-3 border border-n-amber-6 text-n-amber-11 shadow-sm"
                    >
                      <div
                        v-if="note.contentAttributes?.jabvoxManagementStateName"
                        class="inline-flex items-center gap-1 mb-1 px-2 py-0.5 rounded-full text-[11px] font-semibold text-white"
                        :style="{
                          backgroundColor:
                            note.contentAttributes.jabvoxManagementStateColor ||
                            '#6b7280',
                        }"
                      >
                        {{ note.contentAttributes.jabvoxManagementStateName }}
                      </div>
                      {{ note.content }}
                    </div>
                    <span class="text-[11px] text-n-slate-10 px-1">
                      {{ formatTime(note.createdAt) }}
                    </span>
                  </div>
                  <div
                    v-if="contactNotesList.length === 0"
                    class="flex flex-col items-center justify-center gap-2 py-10 text-sm text-n-slate-10"
                  >
                    <span class="i-lucide-sticky-note size-7 text-n-slate-9" />
                    {{ t('JABVOX_LEADS.DETAIL.NO_NOTES') }}
                  </div>
                </template>
              </template>
            </div>

            <div
              class="shrink-0 border-t border-n-weak bg-n-solid-1 p-3 space-y-2"
            >
              <div
                v-if="managementStates.length > 0"
                class="flex items-center gap-2"
              >
                <label
                  class="text-xs font-medium text-n-slate-11 whitespace-nowrap shrink-0"
                >
                  {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.LABEL') }}
                </label>
                <select
                  v-model="managementStateId"
                  class="reset-base flex-1 rounded-lg border text-xs px-2.5 py-1.5 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-slate-7 transition-colors"
                  :class="
                    managementStateId ? 'border-n-weak' : 'border-n-amber-6'
                  "
                >
                  <option :value="null" disabled>
                    {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.PLACEHOLDER') }}
                  </option>
                  <option
                    v-for="s in managementStates"
                    :key="s.id"
                    :value="s.id"
                  >
                    {{ s.name_jabvox }}
                  </option>
                </select>
              </div>
              <ManagementQuestionsForm
                v-if="selectedManagementState"
                v-model="managementAnswers"
                :state="selectedManagementState"
                class="mt-2"
              />
              <div class="flex gap-2 items-end">
                <textarea
                  v-model="newMessage"
                  rows="2"
                  :placeholder="t('JABVOX_LEADS.DETAIL.NOTE_PLACEHOLDER')"
                  class="reset-base flex-1 resize-none rounded-lg border border-n-amber-6 bg-n-amber-3 text-sm text-n-amber-11 px-3 py-2 focus:outline-none focus:border-n-amber-8 transition-colors placeholder-n-amber-11/60"
                  @keydown="onNoteKeydown"
                />
                <Button
                  size="small"
                  :is-loading="isSending"
                  :disabled="!newMessage.trim()"
                  icon="i-lucide-sticky-note"
                  @click="sendMessage(true)"
                />
              </div>
            </div>
          </div>
        </template>

        <!-- ── PRODUCTS TAB ── -->
        <div
          v-else-if="activeTab === 'products'"
          class="flex-1 overflow-y-auto"
        >
          <JabvoxConversationProducts
            :contact-id="lead.contact.id"
            :conversation-id="lead.conversation_id"
          />
        </div>

        <!-- ── HISTORY TAB ── -->
        <div v-else-if="activeTab === 'history'" class="flex-1 overflow-y-auto">
          <JabvoxConversationHistory
            :contact-id="lead.contact.id"
            :conversation-id="lead.conversation_id"
          />
        </div>
      </div>
    </div>
  </div>
</template>
