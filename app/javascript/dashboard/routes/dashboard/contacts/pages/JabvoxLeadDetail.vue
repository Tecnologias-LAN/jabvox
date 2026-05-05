<script setup>
import { ref, computed, onMounted, watch } from 'vue';
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

const store = useStore();
const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const lead = useMapGetter('jabvoxLeads/getCurrentLead');
const leads = useMapGetter('jabvoxLeads/getLeads');
const uiFlags = useMapGetter('jabvoxLeads/getUIFlags');
const managementStates = useMapGetter('jabvoxManagementStates/getActiveStates');
const inboxes = useMapGetter('inboxes/getInboxes');

const activeTab = ref(route.query.tab || 'chat');
const messages = ref([]);
const isLoadingMessages = ref(false);
const newMessage = ref('');
const isSending = ref(false);
const isNoteMode = ref(false);
const managementStateId = ref(null);
const chatContainer = ref(null);
const notesContainer = ref(null);

const selectedInboxId = ref(null);
const initialMessage = ref('');
const isStarting = ref(false);

const accountId = computed(() => route.params.accountId);
const leadId = computed(() => route.params.leadId);

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
    return 'bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-700 text-slate-700 dark:text-slate-200';
  if (isIncoming(m))
    return 'bg-slate-100 dark:bg-slate-700 text-slate-800 dark:text-slate-100';
  return 'bg-woot-500 text-white ml-auto';
};

const msgAlignClass = m =>
  isPrivateNote(m) || isIncoming(m) ? 'items-start' : 'items-end';

const formatTime = dateStr =>
  new Date(dateStr).toLocaleString('es-CO', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

const scrollToBottom = container => {
  setTimeout(() => {
    if (container?.value) {
      container.value.scrollTop = container.value.scrollHeight;
    }
  }, 50);
};

const loadMessages = async () => {
  if (!lead.value?.conversation_id) return;
  isLoadingMessages.value = true;
  try {
    const response = await messageAPI.getPreviousMessages({
      conversationId: lead.value.conversation_id,
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

const sendMessage = async (privateFlag = false) => {
  const content = newMessage.value.trim();
  if (!content || isSending.value || !lead.value?.conversation_id) return;
  if (
    privateFlag &&
    managementStates.value.length > 0 &&
    !managementStateId.value
  )
    return;
  isSending.value = true;
  try {
    const payload = {
      conversationId: lead.value.conversation_id,
      message: content,
      private: privateFlag,
      echo_id: `jabvox_${Date.now()}`,
    };
    if (privateFlag && managementStateId.value) {
      const stateObj = managementStates.value.find(
        s => s.id === managementStateId.value
      );
      payload.contentAttributes = {
        jabvox_management_state_id: managementStateId.value,
        jabvox_management_state_name: stateObj?.name_jabvox || '',
        jabvox_management_state_color: stateObj?.color_jabvox || '',
      };
    }
    const response = await messageAPI.create(payload);
    messages.value.push(response.data);
    newMessage.value = '';
    managementStateId.value = null;
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
  loadMessages();
};

watch(leadId, loadLead);
onMounted(() => {
  store.dispatch('jabvoxManagementStates/fetchStates');
  loadLead();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <!-- Header -->
    <div
      class="shrink-0 border-b border-n-weak bg-n-surface-1 px-6 py-4 flex items-center gap-4"
    >
      <button
        class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-slate-800 dark:hover:text-slate-200 transition-colors"
        @click="goBack"
      >
        <span class="i-lucide-arrow-left size-4" />
        {{ t('JABVOX_LEADS.DETAIL.BACK') }}
      </button>

      <div class="flex-1" />

      <div v-if="leads.length > 1" class="flex items-center gap-2">
        <button
          :disabled="!prevLead"
          class="group flex items-center gap-2 h-9 pl-2.5 pr-3.5 rounded-xl border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:border-indigo-300 hover:bg-indigo-50 hover:text-indigo-700 dark:hover:bg-indigo-900/20 dark:hover:text-indigo-300 disabled:opacity-30 disabled:cursor-not-allowed transition-all"
          @click="prevLead && goToLead(prevLead.id)"
        >
          <span
            class="i-lucide-arrow-left size-3.5 group-hover:-translate-x-0.5 transition-transform"
          />
          <span class="text-left">
            <span class="block text-[10px] text-slate-400 leading-none">
              {{ t('JABVOX_LEADS.DETAIL.PREV') }}
            </span>
            <span
              class="block text-xs font-medium truncate max-w-[110px] leading-tight mt-0.5"
            >
              {{ prevLead?.contact?.name || '···' }}
            </span>
          </span>
        </button>
        <span
          class="text-xs font-medium text-slate-400 tabular-nums whitespace-nowrap"
        >
          {{ currentIndex + 1 }}&thinsp;/&thinsp;{{ leads.length }}
        </span>
        <button
          :disabled="!nextLead"
          class="group flex items-center gap-2 h-9 pl-3.5 pr-2.5 rounded-xl border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:border-indigo-300 hover:bg-indigo-50 hover:text-indigo-700 dark:hover:bg-indigo-900/20 dark:hover:text-indigo-300 disabled:opacity-30 disabled:cursor-not-allowed transition-all"
          @click="nextLead && goToLead(nextLead.id)"
        >
          <span class="text-right">
            <span class="block text-[10px] text-slate-400 leading-none">
              {{ t('JABVOX_LEADS.DETAIL.NEXT') }}
            </span>
            <span
              class="block text-xs font-medium truncate max-w-[110px] leading-tight mt-0.5"
            >
              {{ nextLead?.contact?.name || '···' }}
            </span>
          </span>
          <span
            class="i-lucide-arrow-right size-3.5 group-hover:translate-x-0.5 transition-transform"
          />
        </button>
      </div>
    </div>

    <!-- Loading lead -->
    <div
      v-if="uiFlags.isFetchingOne"
      class="flex-1 flex items-center justify-center text-sm text-slate-400 animate-pulse"
    >
      {{ t('JABVOX_LEADS.DETAIL.LOADING') }}
    </div>

    <!-- Not found -->
    <div
      v-else-if="!lead"
      class="flex-1 flex items-center justify-center text-sm text-slate-400"
    >
      {{ t('JABVOX_LEADS.DETAIL.NOT_FOUND') }}
    </div>

    <!-- Content -->
    <div v-else class="flex-1 min-h-0 flex flex-col lg:flex-row">
      <!-- Left panel: lead info -->
      <div
        class="lg:w-72 shrink-0 border-b lg:border-b-0 lg:border-r border-n-weak p-5 space-y-5 overflow-y-auto"
      >
        <!-- Contact avatar + name -->
        <div class="flex items-center gap-3">
          <img
            v-if="lead.contact.avatar_url"
            :src="lead.contact.avatar_url"
            :alt="lead.contact.name"
            class="w-12 h-12 rounded-full object-cover shrink-0"
          />
          <div
            v-else
            class="w-12 h-12 rounded-full bg-indigo-100 dark:bg-indigo-900/30 flex items-center justify-center shrink-0 text-lg font-semibold text-indigo-600 dark:text-indigo-400"
          >
            {{ lead.contact.name?.charAt(0)?.toUpperCase() || '?' }}
          </div>
          <div class="min-w-0">
            <p
              class="text-sm font-semibold text-slate-800 dark:text-slate-100 truncate"
            >
              {{ lead.contact.name || '—' }}
            </p>
            <p class="text-xs text-slate-400 font-mono">
              #{{ lead.lead_number }}
            </p>
          </div>
        </div>

        <!-- Info rows -->
        <dl class="space-y-2.5">
          <div v-if="lead.contact.phone_number" class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.PHONE') }}
            </dt>
            <dd
              class="text-sm text-slate-700 dark:text-slate-200 font-mono truncate"
            >
              {{ lead.contact.phone_number || '—' }}
            </dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.EMAIL') }}
            </dt>
            <dd class="text-sm text-slate-700 dark:text-slate-200 truncate">
              {{ lead.contact.email || '—' }}
            </dd>
          </div>
          <div v-if="lead.contact.country" class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.COUNTRY') }}
            </dt>
            <dd class="text-sm text-slate-700 dark:text-slate-200">
              {{ lead.contact.country }}
            </dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.CAMPAIGN') }}
            </dt>
            <dd class="text-sm text-slate-700 dark:text-slate-200">
              {{ lead.campaign?.name || '—' }}
            </dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.AFFILIATE') }}
            </dt>
            <dd class="text-sm text-slate-700 dark:text-slate-200">
              {{ lead.affiliate_name || t('JABVOX_LEADS.TABLE.AFFILIATE_OWN') }}
            </dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.INBOX') }}
            </dt>
            <dd class="text-sm text-slate-700 dark:text-slate-200">
              {{ lead.inbox_name || '—' }}
            </dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.ASSIGNEE') }}
            </dt>
            <dd class="text-sm text-slate-700 dark:text-slate-200">
              {{ lead.assignee_name || '—' }}
            </dd>
          </div>
          <div v-if="lead.last_management_state" class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.MANAGEMENT_STATE') }}
            </dt>
            <dd>
              <span
                class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300"
              >
                {{ lead.last_management_state }}
              </span>
            </dd>
          </div>
          <div class="flex gap-2">
            <dt class="text-xs text-slate-400 w-24 shrink-0">
              {{ t('JABVOX_LEADS.DETAIL.INFO.CREATED_AT') }}
            </dt>
            <dd class="text-sm text-slate-700 dark:text-slate-200">
              {{ formatDate(lead.created_at) }}
            </dd>
          </div>
        </dl>
      </div>

      <!-- Right panel: tabs -->
      <div class="flex-1 flex flex-col min-w-0 min-h-0">
        <!-- Tab bar -->
        <div
          class="shrink-0 border-b border-n-weak flex items-center gap-0 px-4"
        >
          <button
            v-for="tab in ['chat', 'notes', 'products', 'history']"
            :key="tab"
            class="px-4 py-3 text-sm font-medium border-b-2 -mb-px transition-colors"
            :class="
              activeTab === tab
                ? 'border-woot-600 text-woot-600'
                : 'border-transparent text-slate-500 hover:text-slate-700 dark:hover:text-slate-200'
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
            :contact-name="lead.contact.name"
            show-label
          />
        </div>

        <!-- ── CHAT TAB ── -->
        <template v-if="activeTab === 'chat'">
          <div
            v-if="!lead.conversation_id"
            class="flex-1 flex flex-col items-center justify-center px-6 py-10 gap-5"
          >
            <div
              class="w-14 h-14 rounded-2xl bg-woot-500/10 flex items-center justify-center"
            >
              <span
                class="i-lucide-message-circle-plus w-7 h-7 text-woot-500"
              />
            </div>
            <div class="text-center max-w-xs">
              <p class="text-sm font-semibold text-n-slate-11 mb-1">
                {{ t('JABVOX_LEADS.DETAIL.CONTACT_VIA') }}
              </p>
              <p class="text-xs text-n-slate-9">
                {{ t('JABVOX_LEADS.DETAIL.CONTACT_VIA_HINT') }}
              </p>
            </div>
            <div class="w-full max-w-sm space-y-3">
              <select
                v-model="selectedInboxId"
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 text-sm px-3 py-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
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
                class="w-full rounded-lg border border-n-weak bg-n-surface-1 text-sm px-3 py-2 text-n-slate-12 placeholder-n-slate-9 focus:outline-none focus:ring-2 focus:ring-woot-500 resize-none"
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
              class="flex-1 overflow-y-auto px-4 py-3 space-y-3 min-h-0"
            >
              <div
                v-if="isLoadingMessages"
                class="flex items-center justify-center py-8 text-sm text-slate-400 animate-pulse"
              >
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
                    class="max-w-[85%] rounded-xl px-3 py-2 text-sm whitespace-pre-wrap break-words"
                    :class="msgBubbleClass(msg)"
                  >
                    <div
                      v-if="isPrivateNote(msg)"
                      class="flex items-center gap-1 mb-1 text-xs text-yellow-700 dark:text-yellow-400 font-medium"
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
                  <span class="text-xs text-slate-400 px-1">
                    {{ formatTime(msg.created_at) }}
                  </span>
                </div>
                <div
                  v-if="sortedMessages.length === 0"
                  class="flex items-center justify-center py-8 text-sm text-slate-400"
                >
                  {{ t('JABVOX_LEADS.DETAIL.NO_MESSAGES') }}
                </div>
              </template>
            </div>

            <div class="shrink-0 border-t border-n-weak p-3 space-y-2">
              <div class="flex gap-2">
                <button
                  class="text-xs px-2.5 py-1 rounded-md font-medium transition-colors"
                  :class="
                    !isNoteMode
                      ? 'bg-woot-500 text-white'
                      : 'bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300'
                  "
                  @click="isNoteMode = false"
                >
                  {{ t('JABVOX_LEADS.DETAIL.REPLY') }}
                </button>
                <button
                  class="text-xs px-2.5 py-1 rounded-md font-medium transition-colors"
                  :class="
                    isNoteMode
                      ? 'bg-yellow-500 text-white'
                      : 'bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300'
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
                  class="text-xs font-medium text-slate-500 dark:text-slate-400 whitespace-nowrap shrink-0"
                >
                  {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.LABEL') }}
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
              <div class="flex gap-2 items-end">
                <textarea
                  v-model="newMessage"
                  rows="2"
                  :placeholder="
                    isNoteMode
                      ? t('JABVOX_LEADS.DETAIL.NOTE_PLACEHOLDER')
                      : t('JABVOX_LEADS.DETAIL.MESSAGE_PLACEHOLDER')
                  "
                  class="flex-1 resize-none rounded-lg border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 text-sm text-slate-700 dark:text-slate-200 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-woot-500 placeholder-slate-400"
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
          <div
            v-if="!lead.conversation_id"
            class="flex-1 flex items-center justify-center text-sm text-slate-400"
          >
            {{ t('JABVOX_LEADS.DETAIL.NO_CONVERSATION') }}
          </div>
          <template v-else>
            <div
              ref="notesContainer"
              class="flex-1 overflow-y-auto px-4 py-3 space-y-3 min-h-0"
            >
              <div
                v-if="isLoadingMessages"
                class="flex items-center justify-center py-8 text-sm text-slate-400 animate-pulse"
              >
                {{ t('JABVOX_LEADS.DETAIL.LOADING_MESSAGES') }}
              </div>
              <template v-else>
                <div
                  v-for="note in privateNotes"
                  :key="note.id"
                  class="flex flex-col gap-1 items-start"
                >
                  <div
                    v-if="note.content"
                    class="max-w-[85%] rounded-xl px-3 py-2 text-sm whitespace-pre-wrap break-words bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-700 text-slate-700 dark:text-slate-200"
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
                      {{ note.content_attributes.jabvox_management_state_name }}
                    </div>
                    {{ note.content }}
                  </div>
                  <span class="text-xs text-slate-400 px-1">
                    {{ formatTime(note.created_at) }}
                  </span>
                </div>
                <div
                  v-if="privateNotes.length === 0"
                  class="flex items-center justify-center py-8 text-sm text-slate-400"
                >
                  {{ t('JABVOX_LEADS.DETAIL.NO_NOTES') }}
                </div>
              </template>
            </div>

            <div class="shrink-0 border-t border-n-weak p-3 space-y-2">
              <div
                v-if="managementStates.length > 0"
                class="flex items-center gap-2"
              >
                <label
                  class="text-xs font-medium text-slate-500 dark:text-slate-400 whitespace-nowrap shrink-0"
                >
                  {{ t('JABVOX_MANAGEMENT_STATES.REPLY_BOX.LABEL') }}
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
              <div class="flex gap-2 items-end">
                <textarea
                  v-model="newMessage"
                  rows="2"
                  :placeholder="t('JABVOX_LEADS.DETAIL.NOTE_PLACEHOLDER')"
                  class="flex-1 resize-none rounded-lg border border-yellow-200 dark:border-yellow-700 bg-yellow-50 dark:bg-yellow-900/10 text-sm text-slate-700 dark:text-slate-200 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-yellow-400 placeholder-slate-400"
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
          </template>
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
