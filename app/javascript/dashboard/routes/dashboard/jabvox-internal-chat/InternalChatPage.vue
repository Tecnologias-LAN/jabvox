<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const { t } = useI18n();
const store = useStore();

const chats = useMapGetter('jabvoxInternalChat/getChats');
const currentChatId = useMapGetter('jabvoxInternalChat/getCurrentChatId');
const currentChat = useMapGetter('jabvoxInternalChat/getCurrentChat');
const messages = useMapGetter('jabvoxInternalChat/getMessages');
const uiFlags = useMapGetter('jabvoxInternalChat/getUIFlags');
const accountUsers = useMapGetter('jabvoxInternalChat/getAccountUsers');
const authUser = useMapGetter('getCurrentUser');

const newMessage = ref('');
const chatSearch = ref('');
const showNewChatModal = ref(false);
const newChatType = ref('direct');
const selectedUserId = ref(null);
const groupName = ref('');
const selectedGroupMembers = ref([]);
const userSearch = ref('');
const messagesContainer = ref(null);
const pollingTimer = ref(null);
const textareaRef = ref(null);

const AVATAR_COLORS = [
  '#6366f1',
  '#8b5cf6',
  '#ec4899',
  '#f59e0b',
  '#10b981',
  '#3b82f6',
  '#ef4444',
  '#14b8a6',
];

function avatarColor(name = '') {
  const idx = name.charCodeAt(0) % AVATAR_COLORS.length;
  return AVATAR_COLORS[idx];
}

function chatDisplayName(chat) {
  if (chat.chat_type === 'group_chat') return chat.name;
  const other = chat.members?.find(m => m.id !== authUser.value?.id);
  return other?.name || chat.name;
}

function chatAvatar(chat) {
  if (chat.chat_type === 'group_chat') return null;
  const other = chat.members?.find(m => m.id !== authUser.value?.id);
  return other?.avatar_url || chat.avatar_url;
}

function chatMembersPreview(chat) {
  if (chat.chat_type !== 'group_chat') return '';
  return chat.members?.map(m => m.name).join(', ') || '';
}

function lastMessagePreview(chat) {
  if (!chat.last_message) return t('JABVOX_INTERNAL_CHAT.NO_MESSAGES');
  return chat.last_message.content?.slice(0, 55) || '';
}

function lastMessageTime(chat) {
  if (!chat.last_message?.created_at) return '';
  const d = new Date(chat.last_message.created_at);
  const now = new Date();
  const diffDays = Math.floor((now - d) / 86400000);
  if (diffDays === 0)
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  if (diffDays === 1) return t('JABVOX_INTERNAL_CHAT.YESTERDAY');
  return d.toLocaleDateString([], { day: 'numeric', month: 'short' });
}

function scrollToBottom() {
  nextTick(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight;
    }
  });
}

const filteredUsers = computed(() => {
  const q = userSearch.value.toLowerCase();
  return accountUsers.value.filter(
    u => u.id !== authUser.value?.id && u.name.toLowerCase().includes(q)
  );
});

const filteredChats = computed(() => {
  const q = chatSearch.value.toLowerCase();
  return [...chats.value]
    .filter(c => chatDisplayName(c).toLowerCase().includes(q))
    .sort((a, b) => {
      const aTime = a.last_message?.created_at || a.id;
      const bTime = b.last_message?.created_at || b.id;
      return new Date(bTime) - new Date(aTime);
    });
});

const groupedMessages = computed(() =>
  messages.value.reduce((groups, msg) => {
    const dateKey = new Date(msg.created_at).toLocaleDateString([], {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
    });
    const last = groups[groups.length - 1];
    if (
      !last ||
      (last.type === 'msg'
        ? groups.find(g => g.type === 'date' && g.label === dateKey) ===
          undefined
        : last.label !== dateKey)
    ) {
      const hasDate = groups.some(
        g => g.type === 'date' && g.label === dateKey
      );
      if (!hasDate) groups.push({ type: 'date', label: dateKey });
    }
    groups.push({ type: 'msg', msg });
    return groups;
  }, [])
);

const isGroupChat = computed(
  () => currentChat.value?.chat_type === 'group_chat'
);

const totalUnread = computed(() =>
  chats.value.reduce((s, c) => s + (c.unread_count || 0), 0)
);

async function selectChat(chat) {
  store.dispatch('jabvoxInternalChat/setCurrentChat', chat.id);
  await store.dispatch('jabvoxInternalChat/fetchMessages', chat.id);
  await store.dispatch('jabvoxInternalChat/markRead', chat.id);
  scrollToBottom();
  nextTick(() => textareaRef.value?.focus());
}

async function send() {
  const content = newMessage.value.trim();
  if (!content || !currentChatId.value) return;
  newMessage.value = '';
  await store.dispatch('jabvoxInternalChat/sendMessage', {
    chatId: currentChatId.value,
    content,
  });
  scrollToBottom();
}

function onKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    send();
  }
}

function openModal(type = 'direct') {
  newChatType.value = type;
  showNewChatModal.value = true;
  selectedUserId.value = null;
  groupName.value = '';
  selectedGroupMembers.value = [];
  userSearch.value = '';
}

function closeModal() {
  showNewChatModal.value = false;
}

async function createDirectChat() {
  if (!selectedUserId.value) return;
  const chat = await store.dispatch('jabvoxInternalChat/createChat', {
    chat_type: 'direct',
    user_id: selectedUserId.value,
  });
  closeModal();
  selectChat(chat);
}

async function createGroupChat() {
  if (!groupName.value.trim() || selectedGroupMembers.value.length === 0)
    return;
  const chat = await store.dispatch('jabvoxInternalChat/createChat', {
    chat_type: 'group_chat',
    name: groupName.value.trim(),
    member_ids: selectedGroupMembers.value,
  });
  closeModal();
  selectChat(chat);
}

function toggleGroupMember(userId) {
  if (selectedGroupMembers.value.includes(userId)) {
    selectedGroupMembers.value = selectedGroupMembers.value.filter(
      id => id !== userId
    );
  } else {
    selectedGroupMembers.value = [...selectedGroupMembers.value, userId];
  }
}

function isMine(msg) {
  return msg.sender?.id === authUser.value?.id;
}

function formatTime(dateStr) {
  if (!dateStr) return '';
  return new Date(dateStr).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function startPolling() {
  pollingTimer.value = setInterval(async () => {
    await store.dispatch('jabvoxInternalChat/fetchChats');
    if (currentChatId.value) {
      await store.dispatch(
        'jabvoxInternalChat/fetchMessages',
        currentChatId.value
      );
    }
  }, 5000);
}

watch(messages, () => scrollToBottom());

onMounted(async () => {
  await Promise.all([
    store.dispatch('jabvoxInternalChat/fetchChats'),
    store.dispatch('jabvoxInternalChat/fetchAccountUsers'),
  ]);
  startPolling();
});

onUnmounted(() => clearInterval(pollingTimer.value));
</script>

<template>
  <div class="flex flex-1 h-full w-full min-h-0 overflow-hidden">
    <!-- ═══════════════════════════════════════════
         SIDEBAR — lista de conversaciones
    ════════════════════════════════════════════ -->
    <aside
      class="flex flex-col w-80 shrink-0 border-r border-n-weak bg-n-surface-2"
    >
      <!-- Header sidebar -->
      <div class="px-4 pt-5 pb-3 border-b border-n-weak">
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-2">
            <h1 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_INTERNAL_CHAT.TITLE') }}
            </h1>
            <span
              v-if="totalUnread > 0"
              class="inline-flex items-center justify-center min-w-[1.2rem] h-5 rounded-full bg-woot-500 text-white text-[10px] font-bold px-1"
            >
              {{ totalUnread }}
            </span>
          </div>
          <div class="flex items-center gap-1">
            <button
              class="p-1.5 rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
              :title="t('JABVOX_INTERNAL_CHAT.NEW_DIRECT')"
              @click="openModal('direct')"
            >
              <span class="i-lucide-message-square-plus w-4 h-4" />
            </button>
            <button
              class="p-1.5 rounded-lg text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
              :title="t('JABVOX_INTERNAL_CHAT.NEW_GROUP')"
              @click="openModal('group_chat')"
            >
              <span class="i-lucide-users-round w-4 h-4" />
            </button>
          </div>
        </div>

        <!-- Search -->
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-n-weak bg-n-surface-1 focus-within:border-woot-500 focus-within:ring-1 focus-within:ring-woot-500/20 transition-all"
        >
          <span class="i-lucide-search w-3.5 h-3.5 shrink-0 text-n-slate-9" />
          <input
            v-model="chatSearch"
            type="text"
            :placeholder="t('JABVOX_INTERNAL_CHAT.SEARCH_USERS')"
            class="flex-1 text-sm bg-transparent text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none"
          />
        </div>
      </div>

      <!-- Lista de chats -->
      <div class="flex-1 overflow-y-auto">
        <!-- Loading -->
        <div
          v-if="uiFlags.isFetchingChats && chats.length === 0"
          class="flex flex-col items-center justify-center gap-3 py-16 text-n-slate-9"
        >
          <span
            class="i-lucide-loader-circle w-7 h-7 animate-spin opacity-50"
          />
          <p class="text-xs">{{ t('JABVOX_INTERNAL_CHAT.LOADING') }}</p>
        </div>

        <!-- Empty -->
        <div
          v-else-if="filteredChats.length === 0"
          class="flex flex-col items-center justify-center gap-3 py-16 px-6 text-center text-n-slate-9"
        >
          <span class="i-lucide-message-circle-off w-10 h-10 opacity-30" />
          <p class="text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_INTERNAL_CHAT.NO_CHATS') }}
          </p>
          <button
            class="text-xs text-woot-500 hover:text-woot-600 font-medium"
            @click="openModal('direct')"
          >
            {{ t('JABVOX_INTERNAL_CHAT.NEW_DIRECT') }}
          </button>
        </div>

        <!-- Chat items -->
        <div
          v-for="chat in filteredChats"
          :key="chat.id"
          class="group flex items-center gap-3 px-4 py-3.5 cursor-pointer transition-colors border-b border-n-weak/40 last:border-0"
          :class="
            currentChatId === chat.id
              ? 'bg-woot-500/8 border-l-2 border-l-woot-500'
              : 'hover:bg-n-alpha-1 border-l-2 border-l-transparent'
          "
          @click="selectChat(chat)"
        >
          <!-- Avatar -->
          <div class="relative flex-shrink-0">
            <img
              v-if="chatAvatar(chat)"
              :src="chatAvatar(chat)"
              class="w-10 h-10 rounded-full object-cover ring-2 ring-n-weak"
            />
            <div
              v-else
              class="w-10 h-10 rounded-full flex items-center justify-center text-white text-sm font-bold ring-2 ring-n-weak"
              :style="{ background: avatarColor(chatDisplayName(chat)) }"
            >
              {{ chatDisplayName(chat)[0]?.toUpperCase() }}
            </div>
            <!-- Group badge -->
            <span
              v-if="chat.chat_type === 'group_chat'"
              class="absolute -bottom-0.5 -right-0.5 w-4 h-4 bg-n-surface-2 rounded-full flex items-center justify-center ring-1 ring-n-weak"
            >
              <span class="i-lucide-users w-2.5 h-2.5 text-n-slate-10" />
            </span>
          </div>

          <!-- Info -->
          <div class="flex-1 min-w-0">
            <div class="flex items-center justify-between gap-1 mb-0.5">
              <span
                class="text-sm font-semibold truncate"
                :class="
                  chat.unread_count > 0 ? 'text-n-slate-12' : 'text-n-slate-11'
                "
              >
                {{ chatDisplayName(chat) }}
              </span>
              <span class="text-[10px] text-n-slate-9 flex-shrink-0">
                {{ lastMessageTime(chat) }}
              </span>
            </div>
            <div class="flex items-center justify-between gap-1">
              <p
                class="text-xs truncate"
                :class="
                  chat.unread_count > 0
                    ? 'text-n-slate-11 font-medium'
                    : 'text-n-slate-9'
                "
              >
                {{ lastMessagePreview(chat) }}
              </p>
              <span
                v-if="chat.unread_count > 0"
                class="flex-shrink-0 min-w-[1.1rem] h-4 rounded-full bg-woot-500 text-white text-[10px] font-bold flex items-center justify-center px-1"
              >
                {{ chat.unread_count > 99 ? '99+' : chat.unread_count }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </aside>

    <!-- ═══════════════════════════════════════════
         PANEL DERECHO — mensajes
    ════════════════════════════════════════════ -->
    <main class="flex flex-col flex-1 min-w-0 bg-n-surface-1">
      <template v-if="currentChat">
        <!-- Header conversación -->
        <header
          class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak bg-n-surface-2 shrink-0"
        >
          <div class="flex items-center gap-3">
            <div class="relative flex-shrink-0">
              <img
                v-if="chatAvatar(currentChat)"
                :src="chatAvatar(currentChat)"
                class="w-9 h-9 rounded-full object-cover"
              />
              <div
                v-else
                class="w-9 h-9 rounded-full flex items-center justify-center text-white text-sm font-bold"
                :style="{
                  background: avatarColor(chatDisplayName(currentChat)),
                }"
              >
                {{ chatDisplayName(currentChat)[0]?.toUpperCase() }}
              </div>
            </div>
            <div class="min-w-0">
              <p class="text-sm font-semibold text-n-slate-12 leading-tight">
                {{ chatDisplayName(currentChat) }}
              </p>
              <p class="text-xs text-n-slate-9 truncate leading-tight mt-0.5">
                <template v-if="isGroupChat">
                  <span class="i-lucide-users w-3 h-3 inline-block mr-0.5" />
                  {{ currentChat.members?.length }}
                  {{ t('JABVOX_INTERNAL_CHAT.MEMBERS') }} ·
                  {{ chatMembersPreview(currentChat) }}
                </template>
                <template v-else>
                  <span
                    class="i-lucide-building-2 w-3 h-3 inline-block mr-0.5"
                  />
                  {{ t('JABVOX_INTERNAL_CHAT.TITLE') }}
                </template>
              </p>
            </div>
          </div>
        </header>

        <!-- Área de mensajes -->
        <div
          ref="messagesContainer"
          class="flex-1 overflow-y-auto px-5 py-4 space-y-1"
        >
          <div
            v-if="uiFlags.isFetchingMessages"
            class="flex items-center justify-center gap-2 py-10 text-n-slate-9"
          >
            <span class="i-lucide-loader-circle w-5 h-5 animate-spin" />
            <span class="text-sm">{{
              t('JABVOX_INTERNAL_CHAT.LOADING_MESSAGES')
            }}</span>
          </div>

          <template v-else-if="messages.length === 0">
            <div
              class="flex flex-col items-center justify-center gap-3 py-20 text-n-slate-9"
            >
              <span class="i-lucide-message-circle w-14 h-14 opacity-20" />
              <p class="text-sm font-medium text-n-slate-10">
                {{ t('JABVOX_INTERNAL_CHAT.NO_MESSAGES') }}
              </p>
              <p class="text-xs text-n-slate-9">
                {{ t('JABVOX_INTERNAL_CHAT.START_CONVERSATION') }}
              </p>
            </div>
          </template>

          <template v-else>
            <div v-for="(item, idx) in groupedMessages" :key="idx">
              <!-- Separador de fecha -->
              <div
                v-if="item.type === 'date'"
                class="flex items-center gap-3 my-4"
              >
                <div class="flex-1 h-px bg-n-weak" />
                <span
                  class="text-[11px] font-medium text-n-slate-9 px-3 py-1 rounded-full bg-n-surface-2 border border-n-weak"
                >
                  {{ item.label }}
                </span>
                <div class="flex-1 h-px bg-n-weak" />
              </div>

              <!-- Mensaje -->
              <div
                v-else
                class="flex mb-1"
                :class="isMine(item.msg) ? 'justify-end' : 'justify-start'"
              >
                <!-- Avatar del otro (solo en grupos o en el primer mensaje consecutivo) -->
                <div
                  v-if="!isMine(item.msg)"
                  class="flex items-end gap-2 max-w-[72%]"
                >
                  <div
                    class="w-7 h-7 rounded-full flex-shrink-0 flex items-center justify-center text-white text-xs font-bold mb-0.5"
                    :style="{ background: avatarColor(item.msg.sender?.name) }"
                  >
                    {{ item.msg.sender?.name?.[0]?.toUpperCase() }}
                  </div>
                  <div class="min-w-0">
                    <p
                      v-if="isGroupChat"
                      class="text-[11px] font-semibold text-n-slate-10 mb-0.5 ml-1"
                    >
                      {{ item.msg.sender?.name }}
                    </p>
                    <div
                      class="bg-n-surface-2 border border-n-weak text-n-slate-12 rounded-2xl rounded-bl-sm px-3.5 py-2.5 shadow-sm"
                    >
                      <p
                        class="text-sm whitespace-pre-wrap break-words leading-relaxed"
                      >
                        {{ item.msg.content }}
                      </p>
                      <p class="text-[10px] text-n-slate-9 mt-1">
                        {{ formatTime(item.msg.created_at) }}
                      </p>
                    </div>
                  </div>
                </div>

                <!-- Mis mensajes -->
                <div v-else class="max-w-[72%]">
                  <div
                    class="bg-woot-500 text-white rounded-2xl rounded-br-sm px-3.5 py-2.5 shadow-sm"
                  >
                    <p
                      class="text-sm whitespace-pre-wrap break-words leading-relaxed"
                    >
                      {{ item.msg.content }}
                    </p>
                    <div class="flex items-center justify-end gap-1 mt-1">
                      <p class="text-[10px] text-white/70">
                        {{ formatTime(item.msg.created_at) }}
                      </p>
                      <span
                        class="i-lucide-check-check w-3 h-3 text-white/60"
                      />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </template>
        </div>

        <!-- Input de mensaje -->
        <footer
          class="shrink-0 border-t border-n-weak bg-n-surface-2 px-4 py-3"
        >
          <div
            class="flex items-end gap-2 bg-n-surface-1 border border-n-weak rounded-xl px-3 py-2 focus-within:border-woot-500 focus-within:ring-1 focus-within:ring-woot-500/20 transition-all"
          >
            <textarea
              ref="textareaRef"
              v-model="newMessage"
              :placeholder="t('JABVOX_INTERNAL_CHAT.MESSAGE_PLACEHOLDER')"
              rows="1"
              class="flex-1 resize-none bg-transparent text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none max-h-32 overflow-y-auto leading-relaxed"
              @keydown="onKeydown"
            />
            <button
              class="p-1.5 rounded-lg bg-woot-500 text-white hover:bg-woot-600 disabled:opacity-40 disabled:cursor-not-allowed transition-colors flex-shrink-0 mb-0.5"
              :disabled="!newMessage.trim() || uiFlags.isSending"
              @click="send"
            >
              <span class="i-lucide-send w-4 h-4" />
            </button>
          </div>
          <p class="text-[10px] text-n-slate-8 mt-1.5 px-1">
            {{ t('JABVOX_INTERNAL_CHAT.SEND_HINT') }}
          </p>
        </footer>
      </template>

      <!-- Estado vacío — ningún chat seleccionado -->
      <div
        v-else
        class="flex-1 flex flex-col items-center justify-center gap-4 text-n-slate-9 px-8"
      >
        <div
          class="w-20 h-20 rounded-2xl bg-woot-500/10 flex items-center justify-center"
        >
          <span
            class="i-lucide-message-circle w-10 h-10 text-woot-500 opacity-60"
          />
        </div>
        <div class="text-center">
          <p class="text-base font-semibold text-n-slate-11 mb-1">
            {{ t('JABVOX_INTERNAL_CHAT.NO_CHAT_SELECTED') }}
          </p>
          <p class="text-sm text-n-slate-9">
            {{ t('JABVOX_INTERNAL_CHAT.NO_CHAT_SELECTED_HINT') }}
          </p>
        </div>
        <div class="flex gap-2 mt-2">
          <button
            class="flex items-center gap-2 px-4 py-2 rounded-lg bg-woot-500 text-white text-sm font-medium hover:bg-woot-600 transition-colors"
            @click="openModal('direct')"
          >
            <span class="i-lucide-message-square-plus w-4 h-4" />
            {{ t('JABVOX_INTERNAL_CHAT.NEW_DIRECT') }}
          </button>
          <button
            class="flex items-center gap-2 px-4 py-2 rounded-lg border border-n-weak text-n-slate-11 text-sm font-medium hover:bg-n-alpha-2 transition-colors"
            @click="openModal('group_chat')"
          >
            <span class="i-lucide-users-round w-4 h-4" />
            {{ t('JABVOX_INTERNAL_CHAT.NEW_GROUP') }}
          </button>
        </div>
      </div>
    </main>

    <!-- ═══════════════════════════════════════════
         MODAL — nuevo chat
    ════════════════════════════════════════════ -->
    <Transition name="modal">
      <div
        v-if="showNewChatModal"
        class="fixed inset-0 z-50 flex items-center justify-center p-4"
        @click.self="closeModal"
      >
        <!-- Backdrop -->
        <div
          class="absolute inset-0 bg-black/40 backdrop-blur-sm"
          @click="closeModal"
        />

        <!-- Modal card -->
        <div
          class="relative z-10 w-full max-w-md bg-n-surface-2 rounded-2xl shadow-2xl border border-n-weak overflow-hidden"
        >
          <!-- Modal header -->
          <div
            class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
          >
            <div class="flex items-center gap-2">
              <span
                class="w-8 h-8 rounded-lg flex items-center justify-center"
                :class="
                  newChatType === 'direct'
                    ? 'bg-woot-500/15 text-woot-500'
                    : 'bg-violet-500/15 text-violet-500'
                "
              >
                <span
                  :class="
                    newChatType === 'direct'
                      ? 'i-lucide-user w-4 h-4'
                      : 'i-lucide-users w-4 h-4'
                  "
                />
              </span>
              <h2 class="text-sm font-semibold text-n-slate-12">
                {{
                  newChatType === 'direct'
                    ? t('JABVOX_INTERNAL_CHAT.NEW_CHAT_TITLE')
                    : t('JABVOX_INTERNAL_CHAT.CREATE_GROUP_TITLE')
                }}
              </h2>
            </div>
            <button
              class="p-1.5 rounded-lg text-n-slate-9 hover:text-n-slate-12 hover:bg-n-alpha-2 transition-colors"
              @click="closeModal"
            >
              <span class="i-lucide-x w-4 h-4" />
            </button>
          </div>

          <!-- Toggle directo / grupo -->
          <div class="px-5 pt-4">
            <div class="flex gap-1 p-1 bg-n-alpha-1 rounded-lg">
              <button
                class="flex-1 flex items-center justify-center gap-1.5 py-1.5 rounded-md text-xs font-medium transition-all"
                :class="
                  newChatType === 'direct'
                    ? 'bg-n-surface-2 text-n-slate-12 shadow-sm'
                    : 'text-n-slate-9 hover:text-n-slate-11'
                "
                @click="newChatType = 'direct'"
              >
                <span class="i-lucide-user w-3.5 h-3.5" />
                {{ t('JABVOX_INTERNAL_CHAT.DIRECT_TAB') }}
              </button>
              <button
                class="flex-1 flex items-center justify-center gap-1.5 py-1.5 rounded-md text-xs font-medium transition-all"
                :class="
                  newChatType === 'group_chat'
                    ? 'bg-n-surface-2 text-n-slate-12 shadow-sm'
                    : 'text-n-slate-9 hover:text-n-slate-11'
                "
                @click="newChatType = 'group_chat'"
              >
                <span class="i-lucide-users w-3.5 h-3.5" />
                {{ t('JABVOX_INTERNAL_CHAT.GROUP_TAB') }}
              </button>
            </div>
          </div>

          <div class="px-5 py-4 space-y-3">
            <!-- Nombre grupo -->
            <div v-if="newChatType === 'group_chat'">
              <label class="block text-xs font-medium text-n-slate-10 mb-1.5">
                {{ t('JABVOX_INTERNAL_CHAT.GROUP_NAME_PLACEHOLDER') }}
              </label>
              <input
                v-model="groupName"
                type="text"
                :placeholder="t('JABVOX_INTERNAL_CHAT.GROUP_NAME_PLACEHOLDER')"
                class="w-full text-sm px-3 py-2 rounded-lg border border-n-weak bg-n-surface-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-1 focus:ring-woot-500/20 transition-all"
              />
            </div>

            <!-- Buscar usuario -->
            <div>
              <label class="block text-xs font-medium text-n-slate-10 mb-1.5">
                {{
                  newChatType === 'direct'
                    ? t('JABVOX_INTERNAL_CHAT.SELECT_USER')
                    : t('JABVOX_INTERNAL_CHAT.SELECT_MEMBERS')
                }}
              </label>
              <div
                class="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-n-weak bg-n-surface-1 mb-2 focus-within:border-woot-500 transition-all"
              >
                <span
                  class="i-lucide-search w-3.5 h-3.5 shrink-0 text-n-slate-9"
                />
                <input
                  v-model="userSearch"
                  type="text"
                  :placeholder="t('JABVOX_INTERNAL_CHAT.SEARCH_USERS')"
                  class="flex-1 text-sm bg-transparent text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none"
                />
              </div>

              <!-- Lista de usuarios -->
              <div
                class="max-h-48 overflow-y-auto rounded-lg border border-n-weak divide-y divide-n-weak/50"
              >
                <div
                  v-for="user in filteredUsers"
                  :key="user.id"
                  class="flex items-center gap-3 px-3 py-2.5 cursor-pointer transition-colors"
                  :class="
                    (newChatType === 'group_chat' &&
                      selectedGroupMembers.includes(user.id)) ||
                    (newChatType === 'direct' && selectedUserId === user.id)
                      ? 'bg-woot-500/8'
                      : 'hover:bg-n-alpha-1'
                  "
                  @click="
                    newChatType === 'group_chat'
                      ? toggleGroupMember(user.id)
                      : (selectedUserId = user.id)
                  "
                >
                  <img
                    v-if="user.avatar_url"
                    :src="user.avatar_url"
                    class="w-8 h-8 rounded-full object-cover flex-shrink-0"
                  />
                  <div
                    v-else
                    class="w-8 h-8 rounded-full flex-shrink-0 flex items-center justify-center text-white text-xs font-bold"
                    :style="{ background: avatarColor(user.name) }"
                  >
                    {{ user.name[0]?.toUpperCase() }}
                  </div>
                  <span class="text-sm text-n-slate-12 truncate flex-1">{{
                    user.name
                  }}</span>
                  <span
                    v-if="
                      (newChatType === 'group_chat' &&
                        selectedGroupMembers.includes(user.id)) ||
                      (newChatType === 'direct' && selectedUserId === user.id)
                    "
                    class="i-lucide-check-circle-2 w-4 h-4 text-woot-500 flex-shrink-0"
                  />
                </div>
                <div
                  v-if="filteredUsers.length === 0"
                  class="px-3 py-4 text-center text-xs text-n-slate-9"
                >
                  {{ t('JABVOX_INTERNAL_CHAT.NO_USERS_FOUND') }}
                </div>
              </div>
            </div>

            <!-- Chips miembros seleccionados en grupo -->
            <div
              v-if="
                newChatType === 'group_chat' && selectedGroupMembers.length > 0
              "
              class="flex flex-wrap gap-1.5"
            >
              <span
                v-for="uid in selectedGroupMembers"
                :key="uid"
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium text-woot-600 bg-woot-500/10"
              >
                {{ accountUsers.find(u => u.id === uid)?.name }}
                <button
                  class="i-lucide-x w-3 h-3 hover:text-woot-800"
                  @click="toggleGroupMember(uid)"
                />
              </span>
            </div>
          </div>

          <!-- Modal footer -->
          <div class="flex gap-2 px-5 pb-5">
            <button
              class="flex-1 py-2 rounded-lg border border-n-weak text-n-slate-11 text-sm font-medium hover:bg-n-alpha-2 transition-colors"
              @click="closeModal"
            >
              {{ t('JABVOX_INTERNAL_CHAT.CANCEL') }}
            </button>
            <button
              class="flex-1 py-2 rounded-lg bg-woot-500 text-white text-sm font-medium hover:bg-woot-600 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
              :disabled="
                newChatType === 'direct'
                  ? !selectedUserId
                  : !groupName.trim() || selectedGroupMembers.length === 0
              "
              @click="
                newChatType === 'direct'
                  ? createDirectChat()
                  : createGroupChat()
              "
            >
              {{ t('JABVOX_INTERNAL_CHAT.CREATE') }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.15s ease;
}
.modal-enter-active .relative,
.modal-leave-active .relative {
  transition:
    transform 0.15s ease,
    opacity 0.15s ease;
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}
</style>
