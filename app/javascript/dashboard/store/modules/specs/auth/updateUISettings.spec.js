import { actions } from '../../auth';
import authAPI from 'dashboard/api/auth';
import types from '../../../mutation-types';
import SessionStorage from 'shared/helpers/sessionStorage';

vi.mock('dashboard/api/auth', () => ({
  default: { updateUISettings: vi.fn() },
}));

const commit = vi.fn();

describe('updateUISettings action', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(SessionStorage, 'get').mockReturnValue(null);
  });

  it('persists user settings and reports success', async () => {
    authAPI.updateUISettings.mockResolvedValue({
      data: { id: 1, ui_settings: { locale: 'en' } },
    });

    const result = await actions.updateUISettings(
      {
        commit,
        state: { currentUser: { ui_settings: { locale: 'es' } } },
      },
      { uiSettings: { locale: 'en' } }
    );

    expect(result).toBe(true);
    expect(authAPI.updateUISettings).toHaveBeenCalledWith({
      uiSettings: { locale: 'en' },
    });
    expect(commit.mock.calls).toEqual([
      [types.SET_CURRENT_USER_UI_SETTINGS, { uiSettings: { locale: 'en' } }],
      [types.SET_CURRENT_USER, { id: 1, ui_settings: { locale: 'en' } }],
    ]);
  });

  it('restores the previous preference when persistence fails', async () => {
    authAPI.updateUISettings.mockRejectedValue(new Error('request failed'));

    const result = await actions.updateUISettings(
      {
        commit,
        state: { currentUser: { ui_settings: { locale: 'es' } } },
      },
      { uiSettings: { locale: 'en' } }
    );

    expect(result).toBe(false);
    expect(commit.mock.calls).toEqual([
      [types.SET_CURRENT_USER_UI_SETTINGS, { uiSettings: { locale: 'en' } }],
      [types.SET_CURRENT_USER_UI_SETTINGS, { uiSettings: { locale: 'es' } }],
    ]);
  });
});
