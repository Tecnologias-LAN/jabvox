import dashboardAPI from '../jabvox/dashboard';

describe('Jabvox dashboard API', () => {
  const originalAxios = window.axios;
  const originalPath = window.location.pathname;
  const axiosMock = { get: vi.fn(() => Promise.resolve({ data: {} })) };

  beforeEach(() => {
    window.axios = axiosMock;
    window.history.pushState({}, '', '/app/accounts/42/dashboard');
  });

  afterEach(() => {
    window.axios = originalAxios;
    window.history.pushState({}, '', originalPath);
    vi.clearAllMocks();
  });

  it('requests the account-scoped summary with calendar-day filters', () => {
    const params = { date_from: '2025-03-01', date_to: '2025-03-07' };

    dashboardAPI.getSummary(params);

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/42/jabvox/dashboard',
      { params }
    );
  });
});
