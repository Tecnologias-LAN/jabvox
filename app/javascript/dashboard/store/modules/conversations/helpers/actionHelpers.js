import types from '../../../mutation-types';

// El backend pagina las conversaciones de a 25 (CONVERSATION_RESULTS_PER_PAGE,
// ver conversation_finder.rb). Una página con menos de esto es la última.
const CONVERSATIONS_PER_PAGE = 25;

export const setPageFilter = ({ dispatch, filter, page, markEndReached }) => {
  dispatch('conversationPage/setCurrentPage', { filter, page }, { root: true });
  if (markEndReached) {
    dispatch('conversationPage/setEndReached', { filter }, { root: true });
  }
};

export const setContacts = (commit, chatList) => {
  commit(
    `contacts/${types.SET_CONTACTS}`,
    chatList.map(chat => chat.meta.sender)
  );
};

export const isOnMentionsView = ({ route: { name: routeName } }) => {
  const MENTION_ROUTES = [
    'conversation_mentions',
    'conversation_through_mentions',
  ];
  return MENTION_ROUTES.includes(routeName);
};

export const isOnUnattendedView = ({ route: { name: routeName } }) => {
  const UNATTENDED_ROUTES = [
    'conversation_unattended',
    'conversation_through_unattended',
  ];
  return UNATTENDED_ROUTES.includes(routeName);
};

export const isOnParticipatingView = ({ route: { name: routeName } }) => {
  const PARTICIPATING_ROUTES = [
    'conversation_participating',
    'conversation_through_participating',
  ];
  return PARTICIPATING_ROUTES.includes(routeName);
};

export const isOnFoldersView = ({ route: { name: routeName } }) => {
  const FOLDER_ROUTES = [
    'folder_conversations',
    'conversations_through_folders',
  ];
  return FOLDER_ROUTES.includes(routeName);
};

export const buildConversationList = (
  context,
  requestPayload,
  responseData,
  filterType
) => {
  const { payload: conversationList, meta: metaData } = responseData;
  context.commit(types.SET_ALL_CONVERSATION, conversationList);
  context.dispatch('conversationStats/set', metaData);
  context.dispatch(
    'conversationLabels/setBulkConversationLabels',
    conversationList
  );
  context.commit(types.CLEAR_LIST_LOADING_STATUS);
  setContacts(context.commit, conversationList);
  setPageFilter({
    dispatch: context.dispatch,
    filter: filterType,
    page: requestPayload.page,
    // Fin de la lista cuando la página viene incompleta (menos de CONVERSATIONS_PER_PAGE),
    // no solo cuando viene vacía: con filtros, la última página casi nunca cae en
    // exactamente 0 elementos, así que marcar fin solo con length===0 deja el scroll
    // pidiendo página tras página sin frenar (carga infinita).
    markEndReached: conversationList.length < CONVERSATIONS_PER_PAGE,
  });
};
