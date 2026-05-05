import internalChatAPI from 'dashboard/api/jabvox/internalChat';

const state = {
  chats: [],
  currentChatId: null,
  messages: [],
  unreadTotal: 0,
  accountUsers: [],
  uiFlags: {
    isFetchingChats: false,
    isFetchingMessages: false,
    isSending: false,
  },
};

const getters = {
  getChats: s => s.chats,
  getCurrentChatId: s => s.currentChatId,
  getCurrentChat: s => s.chats.find(c => c.id === s.currentChatId) || null,
  getMessages: s => s.messages,
  getUnreadTotal: s => s.unreadTotal,
  getAccountUsers: s => s.accountUsers,
  getUIFlags: s => s.uiFlags,
};

const actions = {
  fetchChats: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetchingChats: true });
    try {
      const { data } = await internalChatAPI.getChats();
      commit('SET_CHATS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingChats: false });
    }
  },
  createChat: async ({ commit }, params) => {
    const { data } = await internalChatAPI.createChat(params);
    commit('ADD_CHAT', data);
    return data;
  },
  fetchMessages: async ({ commit }, chatId) => {
    commit('SET_UI_FLAG', { isFetchingMessages: true });
    try {
      const { data } = await internalChatAPI.getMessages(chatId);
      commit('SET_MESSAGES', data);
    } finally {
      commit('SET_UI_FLAG', { isFetchingMessages: false });
    }
  },
  sendMessage: async ({ commit, state: s }, { chatId, content }) => {
    commit('SET_UI_FLAG', { isSending: true });
    try {
      const { data } = await internalChatAPI.sendMessage(chatId, content);
      if (s.currentChatId === chatId) commit('ADD_MESSAGE', data);
      commit('UPDATE_CHAT_LAST_MESSAGE', { chatId, message: data });
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSending: false });
    }
  },
  markRead: async ({ commit }, chatId) => {
    await internalChatAPI.markRead(chatId);
    commit('RESET_UNREAD', chatId);
    commit('REFRESH_UNREAD_TOTAL');
  },
  fetchUnreadCount: async ({ commit }) => {
    const { data } = await internalChatAPI.getUnreadCount();
    commit('SET_UNREAD_TOTAL', data.count);
  },
  fetchAccountUsers: async ({ commit }) => {
    const { data } = await internalChatAPI.getAccountUsers();
    commit('SET_ACCOUNT_USERS', data);
  },
  setCurrentChat: ({ commit }, chatId) => {
    commit('SET_CURRENT_CHAT_ID', chatId);
  },
};

const mutations = {
  SET_CHATS: (s, chats) => {
    s.chats = chats;
    s.unreadTotal = chats.reduce((sum, c) => sum + (c.unread_count || 0), 0);
  },
  ADD_CHAT: (s, chat) => {
    s.chats = [chat, ...s.chats];
  },
  SET_CURRENT_CHAT_ID: (s, id) => {
    s.currentChatId = id;
  },
  SET_MESSAGES: (s, messages) => {
    s.messages = messages;
  },
  ADD_MESSAGE: (s, msg) => {
    s.messages = [...s.messages, msg];
  },
  UPDATE_CHAT_LAST_MESSAGE: (s, { chatId, message }) => {
    s.chats = s.chats.map(c =>
      c.id === chatId
        ? {
            ...c,
            last_message: {
              content: message.content,
              created_at: message.created_at,
              sender_id: message.sender.id,
            },
          }
        : c
    );
  },
  RESET_UNREAD: (s, chatId) => {
    s.chats = s.chats.map(c =>
      c.id === chatId ? { ...c, unread_count: 0 } : c
    );
  },
  REFRESH_UNREAD_TOTAL: s => {
    s.unreadTotal = s.chats.reduce((sum, c) => sum + (c.unread_count || 0), 0);
  },
  SET_UNREAD_TOTAL: (s, count) => {
    s.unreadTotal = count;
  },
  SET_ACCOUNT_USERS: (s, users) => {
    s.accountUsers = users;
  },
  SET_UI_FLAG: (s, flags) => {
    Object.assign(s.uiFlags, flags);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
