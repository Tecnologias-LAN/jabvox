/* global axios */
import ApiClient from '../ApiClient';

const client = new ApiClient('jabvox/internal_chats', { accountScoped: true });

export default {
  getChats: () => axios.get(client.url),
  createChat: params => axios.post(client.url, params),
  getMessages: chatId => axios.get(`${client.url}/${chatId}/messages`),
  sendMessage: (chatId, content) =>
    axios.post(`${client.url}/${chatId}/send_message`, { content }),
  markRead: chatId => axios.patch(`${client.url}/${chatId}/mark_read`),
  getUnreadCount: () => axios.get(`${client.url}/unread_count`),
  getAccountUsers: () => axios.get(`${client.url}/account_users`),
};
