import {
  isOnMentionsView,
  isOnFoldersView,
  isOnParticipatingView,
  buildConversationList,
} from '../actionHelpers';

describe('#buildConversationList — fin de paginación', () => {
  const buildContext = () => ({
    commit: vi.fn(),
    dispatch: vi.fn(),
  });

  const run = (count, filterType = 'appliedFilters') => {
    const context = buildContext();
    const payload = Array.from({ length: count }, (_, i) => ({
      id: i + 1,
      meta: { sender: { id: i + 1 } },
    }));
    buildConversationList(
      context,
      { page: 1 },
      { payload, meta: {} },
      filterType
    );
    // La llamada a setPageFilter dispara setCurrentPage y, si corresponde, setEndReached.
    const calledEndReached = context.dispatch.mock.calls.some(
      ([action]) => action === 'conversationPage/setEndReached'
    );
    return calledEndReached;
  };

  it('marca fin cuando la página viene incompleta (menos de 25)', () => {
    expect(run(10)).toBe(true);
  });

  it('marca fin cuando la página viene vacía', () => {
    expect(run(0)).toBe(true);
  });

  it('NO marca fin cuando la página viene llena (25): podría haber más', () => {
    expect(run(25)).toBe(false);
  });
});

describe('#isOnMentionsView', () => {
  it('return valid responses when passing the state', () => {
    expect(isOnMentionsView({ route: { name: 'conversation_mentions' } })).toBe(
      true
    );
    expect(isOnMentionsView({ route: { name: 'conversation_messages' } })).toBe(
      false
    );
  });
});

describe('#isOnFoldersView', () => {
  it('return valid responses when passing the state', () => {
    expect(isOnFoldersView({ route: { name: 'folder_conversations' } })).toBe(
      true
    );
    expect(
      isOnFoldersView({ route: { name: 'conversations_through_folders' } })
    ).toBe(true);
    expect(isOnFoldersView({ route: { name: 'conversation_messages' } })).toBe(
      false
    );
  });
});

describe('#isOnParticipatingView', () => {
  it('return valid responses when passing the state', () => {
    expect(
      isOnParticipatingView({ route: { name: 'conversation_participating' } })
    ).toBe(true);
    expect(
      isOnParticipatingView({
        route: { name: 'conversation_through_participating' },
      })
    ).toBe(true);
    expect(
      isOnParticipatingView({ route: { name: 'conversation_messages' } })
    ).toBe(false);
  });
});
