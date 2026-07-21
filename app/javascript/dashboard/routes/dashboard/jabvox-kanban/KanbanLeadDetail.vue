<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import messageAPI from 'dashboard/api/inbox/message';
import Button from 'dashboard/components-next/button/Button.vue';
import JabvoxCallButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxCallButton.vue';
import JabvoxEmailButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxEmailButton.vue';
import JabvoxSmsButton from 'dashboard/components/widgets/conversation/jabvox/JabvoxSmsButton.vue';
import JabvoxConversationProducts from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationProducts.vue';
import JabvoxConversationHistory from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationHistory.vue';
import JabvoxLeadRecordsByContact from 'dashboard/components/widgets/conversation/jabvox/JabvoxLeadRecordsByContact.vue';
import JabvoxConversationNotes from 'dashboard/components/widgets/conversation/jabvox/JabvoxConversationNotes.vue';
import ManagementQuestionsForm from 'dashboard/components/jabvox/managementStates/ManagementQuestionsForm.vue';
import {
  buildManagementContentAttributes,
  stateGroups,
  statesInGroup,
  hasGroups,
  CALL_SOURCES,
} from 'dashboard/composables/jabvox/useManagementState';

const props = defineProps({
  conversation: { type: Object, required: true },
});

const emit = defineEmits(['close']);
const store = useStore();
const { t } = useI18n();
const myVisibilities = useMapGetter(
  'jabvoxFieldVisibilities/getMyVisibilities'
);
const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');

const mask = (field, value) =>
  myVisibilities.value[field] !== false ? value : '***';

const activeTab = ref('chat');
const messages = ref([]);
const isLoadingMessages = ref(false);
const newMessage = ref('');
const isNote = ref(false);
const isSending = ref(false);
const managementStateId = ref(null);
const managementGroup = ref(null);
const managementAnswers = ref({});
const messagesContainer = ref(null);

const selectedManagementState = computed(() =>
  managementStates.value.find(s => s.id === managementStateId.value)
);

// Two-level picker (Estado → Subestado) when any active state has a group.
const managementHasGroups = computed(() => hasGroups(managementStates.value));
const managementGroups = computed(() => stateGroups(managementStates.value));
const managementGroupStates = computed(() =>
  managementGroup.value === null
    ? []
    : statesInGroup(managementStates.value, managementGroup.value)
);

// Changing the group invalidates a substate that belongs to another group.
watch(managementGroup, () => {
  const state = selectedManagementState.value;
  if (
    state &&
    (state.state_group_jabvox || '') !== (managementGroup.value || '')
  )
    managementStateId.value = null;
});

const contactName = computed(
  () => props.conversation.contact?.name || t('JABVOX_KANBAN.UNKNOWN_CONTACT')
);
const contactEmail = computed(() =>
  mask('email', props.conversation.contact?.email || '')
);
const contactPhone = computed(() =>
  mask('phone', props.conversation.contact?.phone_number || '')
);
const contactIdentification = computed(() => {
  const id =
    props.conversation.contact?.additional_attributes
      ?.jabvox_identification_number;
  return id ? mask('identification', id) : '';
});
const contactType = computed(
  () =>
    props.conversation.contact?.additional_attributes?.jabvox_contact_type ||
    'persona'
);
const contactTypeLabel = computed(() =>
  contactType.value === 'empresa'
    ? t('JABVOX_KANBAN.CONTACT_TYPE_COMPANY')
    : t('JABVOX_KANBAN.CONTACT_TYPE_PERSON')
);
const avatarUrl = computed(() => props.conversation.contact?.avatar_url || '');
const assigneeName = computed(
  () => props.conversation.assignee?.name || t('JABVOX_KANBAN.UNASSIGNED')
);
const inboxName = computed(() => props.conversation.inbox?.name || '');
const contactId = computed(
  () => props.conversation.contact?.id || props.conversation.meta?.sender?.id
);

const currentAccountId = useMapGetter('getCurrentAccountId');
const isProductsEnabled = computed(() =>
  store.getters['accounts/isFeatureEnabledonAccount'](
    currentAccountId.value,
    FEATURE_FLAGS.JABVOX_PRODUCTS
  )
);

const hasMultiTables = computed(() => {
  try {
    return (
      (store.getters['jabvoxCustomization/getMultiTables'] || []).length > 0
    );
  } catch {
    return false;
  }
});

const TABS = computed(() => {
  const tabs = [
    {
      key: 'chat',
      label: 'JABVOX_PRODUCTS.CONVERSATION.TAB_CHAT',
      icon: 'i-lucide-message-circle',
    },
  ];
  if (isProductsEnabled.value) {
    tabs.push({
      key: 'products',
      label: 'JABVOX_PRODUCTS.CONVERSATION.TAB_PRODUCTS',
      icon: 'i-lucide-shopping-cart',
    });
  }
  // Notes tab (with gestión) — the chat itself no longer carries the picker.
  tabs.push({
    key: 'notes',
    label: 'JABVOX_CUSTOMIZATION.LEAD_ROWS.NOTES_TAB',
    icon: 'i-lucide-sticky-note',
  });
  if (hasMultiTables.value) {
    tabs.push({
      key: 'records',
      label: 'JABVOX_CUSTOMIZATION.LEAD_ROWS.TAB',
      icon: 'i-lucide-list',
    });
  }
  tabs.push({
    key: 'history',
    label: 'JABVOX_PRODUCTS.CONVERSATION.TAB_HISTORY',
    icon: 'i-lucide-clock',
  });
  return tabs;
});

const sortedMessages = computed(() =>
  [...messages.value].sort(
    (a, b) => new Date(a.created_at) - new Date(b.created_at)
  )
);

const scrollToBottom = () => {
  setTimeout(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight;
    }
  }, 50);
};

const loadMessages = async () => {
  isLoadingMessages.value = true;
  try {
    const response = await messageAPI.getPreviousMessages({
      // messages API resolves by display_id, not the PK
      conversationId: props.conversation.display_id,
      before: undefined,
      after: undefined,
    });
    messages.value = response.data?.payload || [];
  } catch {
    useAlert(t('JABVOX_KANBAN.LOAD_MESSAGES_ERROR'));
  } finally {
    isLoadingMessages.value = false;
    scrollToBottom();
  }
};

onMounted(() => {
  store.dispatch('jabvoxManagementStates/fetchStates');
  store.dispatch('jabvoxCustomization/fetchTables').catch(() => {});
  loadMessages();
});
watch(
  () => props.conversation.id,
  () => {
    activeTab.value = 'chat';
    managementStateId.value = null;
    managementGroup.value = null;
    managementAnswers.value = {};
    loadMessages();
  }
);

const formatTime = dateStr =>
  new Date(dateStr).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

const isIncomingMessage = msg => msg.message_type === 0;
const isPrivateNote = msg => msg.message_type === 2 || msg.private;

const messageClass = msg => {
  if (isPrivateNote(msg))
    return 'bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-700 text-slate-700 dark:text-slate-200';
  if (isIncomingMessage(msg))
    return 'bg-slate-100 dark:bg-slate-800 text-slate-800 dark:text-slate-100';
  return 'bg-woot-500 text-white ml-auto';
};

const alignClass = msg =>
  isPrivateNote(msg) || isIncomingMessage(msg) ? 'items-start' : 'items-end';

const sendMessage = async () => {
  const content = newMessage.value.trim();
  if (!content || isSending.value) return;
  // Gestión is captured in the Notes tab, not the chat. A chat private note is
  // just the note text — no gestión required or attached here.
  isSending.value = true;
  try {
    const payload = {
      // messages API resolves by display_id, not the PK
      conversationId: props.conversation.display_id,
      message: content,
      private: isNote.value,
      echo_id: `jabvox_${Date.now()}`,
    };
    if (isNote.value && managementStateId.value) {
      payload.contentAttributes = buildManagementContentAttributes(
        selectedManagementState.value,
        managementAnswers.value,
        CALL_SOURCES.KANBAN
      );
    }
    const response = await messageAPI.create(payload);
    messages.value.push(response.data);
    newMessage.value = '';
    managementStateId.value = null;
    managementGroup.value = null;
    managementAnswers.value = {};
    scrollToBottom();
  } catch {
    useAlert(t('JABVOX_KANBAN.SEND_MESSAGE_ERROR'));
  } finally {
    isSending.value = false;
  }
};

const onKeydown = event => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    sendMessage();
  }
};
</script>

<template>
  <div class="flex flex-col h-full overflow-hidden">
    <!-- Header -->
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <span class="text-sm font-semibold text-slate-800 dark:text-slate-100">
        {{ $t('JABVOX_KANBAN.LEAD_DETAIL') }}
      </span>
      <button
        class="p-1 rounded hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-500"
        @click="emit('close')"
      >
        <i class="i-lucide-x text-lg" />
      </button>
    </div>

    <!-- Contact info -->
    <div
      class="px-4 py-3 border-b border-slate-200 dark:border-slate-700 shrink-0"
    >
      <div class="flex items-center gap-3 mb-2">
        <img
          v-if="avatarUrl"
          :src="avatarUrl"
          class="w-10 h-10 rounded-full object-cover shrink-0"
          :alt="contactName"
        />
        <div
          v-else
          class="w-10 h-10 rounded-full bg-woot-100 dark:bg-woot-800 flex items-center justify-center text-woot-600 dark:text-woot-300 font-semibold text-sm shrink-0"
        >
          {{ contactName.charAt(0).toUpperCase() }}
        </div>
        <div class="min-w-0 flex-1">
          <p
            class="text-sm font-semibold text-slate-800 dark:text-slate-100 truncate"
          >
            {{ contactName }}
          </p>
          <p
            v-if="contactEmail"
            class="text-xs text-slate-500 dark:text-slate-400 truncate"
          >
            {{ contactEmail }}
          </p>
          <div v-if="contactPhone" class="flex items-center gap-1">
            <p class="text-xs text-slate-500 dark:text-slate-400">
              {{ contactPhone }}
            </p>
          </div>
          <p
            v-if="contactIdentification"
            class="text-xs text-slate-500 dark:text-slate-400 font-mono"
          >
            {{ t('JABVOX_KANBAN.DOCUMENT_LABEL') }}: {{ contactIdentification }}
          </p>
          <span
            class="inline-flex items-center mt-0.5 px-1.5 py-0.5 rounded-md text-[10px] font-medium bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-300 w-fit"
          >
            {{ contactTypeLabel }}
          </span>
        </div>
        <div class="flex items-center gap-1">
          <JabvoxCallButton
            v-if="contactPhone || contactId"
            :phone="contactPhone"
            :contact-id="contactId"
            :contact-name="contactName"
          />
          <JabvoxSmsButton
            v-if="contactPhone && contactId"
            :phone="contactPhone"
            :contact-id="contactId"
          />
          <JabvoxEmailButton
            v-if="contactEmail && contactId"
            :email="contactEmail"
            :contact-id="contactId"
          />
        </div>
      </div>
      <div
        class="flex flex-wrap items-center gap-3 text-xs text-slate-500 dark:text-slate-400"
      >
        <span class="flex items-center gap-1">
          <i class="i-lucide-hash text-base" />
          {{ conversation.display_id }}
        </span>
        <span class="flex items-center gap-1">
          <i class="i-lucide-mailbox text-base" />
          {{ inboxName }}
        </span>
        <span class="flex items-center gap-1">
          <i class="i-lucide-user text-base" />
          {{ assigneeName }}
        </span>
      </div>
    </div>

    <!-- Tabs -->
    <div
      class="flex border-b border-slate-200 dark:border-slate-700 shrink-0 overflow-x-auto"
    >
      <button
        v-for="tab in TABS"
        :key="tab.key"
        class="flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium border-b-2 whitespace-nowrap transition-colors"
        :class="[
          activeTab === tab.key
            ? 'border-woot-600 text-woot-600'
            : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-300',
        ]"
        @click="activeTab = tab.key"
      >
        <i :class="tab.icon" />
        {{ $t(tab.label) }}
      </button>
    </div>

    <!-- Chat tab -->
    <template v-if="activeTab === 'chat'">
      <div
        ref="messagesContainer"
        class="flex-1 overflow-y-auto px-4 py-3 space-y-3 min-h-0"
      >
        <div
          v-if="isLoadingMessages"
          class="flex items-center justify-center py-8 text-slate-400 text-sm animate-pulse"
        >
          {{ $t('JABVOX_KANBAN.LOADING_MESSAGES') }}
        </div>

        <template v-else>
          <div
            v-for="msg in sortedMessages"
            :key="msg.id"
            class="flex flex-col gap-1"
            :class="alignClass(msg)"
          >
            <div
              v-if="msg.content"
              class="max-w-[85%] rounded-xl px-3 py-2 text-sm whitespace-pre-wrap break-words"
              :class="messageClass(msg)"
            >
              <div
                v-if="isPrivateNote(msg)"
                class="flex items-center gap-1 mb-1 text-xs text-yellow-700 dark:text-yellow-400 font-medium"
              >
                <i class="i-lucide-sticky-note text-base" />
                {{ $t('JABVOX_KANBAN.PRIVATE_NOTE') }}
              </div>
              <div
                v-if="
                  isPrivateNote(msg) &&
                  msg.content_attributes?.jabvox_management_state_name
                "
                class="inline-flex items-center gap-1 mb-1 px-2 py-0.5 rounded-full text-[11px] font-semibold text-white"
                :style="{
                  backgroundColor:
                    msg.content_attributes.jabvox_management_state_color ||
                    '#6b7280',
                }"
              >
                {{ msg.content_attributes.jabvox_management_state_name }}
              </div>
              {{ msg.content }}
            </div>
            <span class="text-xs text-slate-400 dark:text-slate-500 px-1">
              {{ formatTime(msg.created_at) }}
            </span>
          </div>

          <div
            v-if="sortedMessages.length === 0"
            class="flex items-center justify-center py-8 text-slate-400 dark:text-slate-600 text-sm"
          >
            {{ $t('JABVOX_KANBAN.NO_MESSAGES') }}
          </div>
        </template>
      </div>

      <div class="shrink-0 border-t border-slate-200 dark:border-slate-700 p-3">
        <div class="flex items-center gap-2 mb-2">
          <button
            class="text-xs px-2 py-1 rounded-md font-medium transition-colors"
            :class="[
              !isNote
                ? 'bg-woot-500 text-white'
                : 'bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300',
            ]"
            @click="isNote = false"
          >
            {{ $t('JABVOX_KANBAN.REPLY') }}
          </button>
          <button
            class="text-xs px-2 py-1 rounded-md font-medium transition-colors"
            :class="[
              isNote
                ? 'bg-yellow-500 text-white'
                : 'bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300',
            ]"
            @click="isNote = true"
          >
            {{ $t('JABVOX_KANBAN.ADD_NOTE') }}
          </button>
        </div>
        <!-- Gestión picker removed from chat: notes here are plain text.
             Gestión is done from the Notes tab. -->
        <div v-if="false" class="mb-2">
          <!-- Two-level picker: Estado (grupo) → Subestado -->
          <template v-if="managementHasGroups">
            <div class="flex items-center gap-2">
              <label
                class="text-xs font-medium text-slate-500 dark:text-slate-400 whitespace-nowrap shrink-0"
              >
                {{ $t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.GROUP_LABEL') }}
              </label>
              <select
                v-model="managementGroup"
                class="flex-1 rounded-md border text-xs px-2 py-1 bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200"
                :class="
                  managementGroup !== null
                    ? 'border-slate-200 dark:border-slate-600'
                    : 'border-amber-400 dark:border-amber-500'
                "
              >
                <option :value="null" disabled>
                  {{
                    $t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.GROUP_PLACEHOLDER')
                  }}
                </option>
                <option v-for="g in managementGroups" :key="g" :value="g">
                  {{ g || $t('JABVOX_MANAGEMENT_STATES.UNGROUPED') }}
                </option>
              </select>
            </div>
            <div class="flex items-center gap-2 mt-2">
              <label
                class="text-xs font-medium text-slate-500 dark:text-slate-400 whitespace-nowrap shrink-0"
              >
                {{ $t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_LABEL') }}
              </label>
              <select
                v-model="managementStateId"
                :disabled="managementGroup === null"
                class="flex-1 rounded-md border text-xs px-2 py-1 bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200 disabled:opacity-60"
                :class="
                  managementStateId
                    ? 'border-slate-200 dark:border-slate-600'
                    : 'border-amber-400 dark:border-amber-500'
                "
              >
                <option :value="null" disabled>
                  {{
                    $t(
                      'JABVOX_MANAGEMENT_STATES.REPLY_BOX.SUBSTATE_PLACEHOLDER'
                    )
                  }}
                </option>
                <option
                  v-for="s in managementGroupStates"
                  :key="s.id"
                  :value="s.id"
                >
                  {{ s.name_jabvox }}
                </option>
              </select>
            </div>
          </template>
          <!-- Flat picker (accounts without groups) -->
          <div v-else class="flex items-center gap-2">
            <label
              class="text-xs font-medium text-slate-500 dark:text-slate-400 whitespace-nowrap shrink-0"
            >
              {{ $t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.LABEL') }}
            </label>
            <select
              v-model="managementStateId"
              class="flex-1 rounded-md border text-xs px-2 py-1 bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200"
              :class="
                managementStateId
                  ? 'border-slate-200 dark:border-slate-600'
                  : 'border-amber-400 dark:border-amber-500'
              "
            >
              <option :value="null" disabled>
                {{ $t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.PLACEHOLDER') }}
              </option>
              <option v-for="s in managementStates" :key="s.id" :value="s.id">
                {{ s.name_jabvox }}
              </option>
            </select>
          </div>
          <p
            v-if="selectedManagementState?.usage_info_jabvox"
            class="mt-1 text-xs text-slate-500 dark:text-slate-400"
          >
            {{ selectedManagementState.usage_info_jabvox }}
          </p>
        </div>
        <ManagementQuestionsForm
          v-if="isNote && selectedManagementState"
          v-model="managementAnswers"
          :state="selectedManagementState"
          class="mb-2"
        />
        <div class="flex gap-2 items-end">
          <textarea
            v-model="newMessage"
            rows="2"
            :placeholder="
              isNote
                ? $t('JABVOX_KANBAN.NOTE_PLACEHOLDER')
                : $t('JABVOX_KANBAN.MESSAGE_PLACEHOLDER')
            "
            class="flex-1 resize-none rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 placeholder-slate-400"
            @keydown="onKeydown"
          />
          <Button
            size="small"
            :is-loading="isSending"
            :disabled="!newMessage.trim()"
            icon="i-lucide-send"
            @click="sendMessage"
          />
        </div>
      </div>
    </template>

    <!-- Products tab -->
    <JabvoxConversationProducts
      v-else-if="activeTab === 'products'"
      :contact-id="contactId"
      :conversation-id="conversation.id"
    />

    <!-- History tab -->
    <JabvoxConversationHistory
      v-else-if="activeTab === 'history' && contactId"
      :contact-id="contactId"
      :conversation-id="conversation.id"
    />
    <div
      v-else-if="activeTab === 'history'"
      class="flex-1 flex items-center justify-center text-sm text-slate-400"
    >
      {{ $t('JABVOX_PRODUCTS.CONVERSATION.HISTORY_EMPTY') }}
    </div>

    <!-- Notes tab (with gestión) -->
    <JabvoxConversationNotes
      v-else-if="activeTab === 'notes'"
      :contact-id="contactId"
      :conversation-id="conversation.id"
      :conversation-display-id="conversation.display_id"
    />

    <!-- Records tab: multi-row custom tables (Asesorías, Casos…) -->
    <div v-else-if="activeTab === 'records'" class="flex-1 overflow-y-auto">
      <JabvoxLeadRecordsByContact :contact-id="contactId" />
    </div>
  </div>
</template>
