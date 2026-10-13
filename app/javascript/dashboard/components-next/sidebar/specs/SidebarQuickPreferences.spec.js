import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import SidebarQuickPreferences from '../SidebarQuickPreferences.vue';

const {
  updateUISettings,
  alert,
  localStorageGet,
  localStorageSet,
  setColorTheme,
} = vi.hoisted(() => ({
  updateUISettings: vi.fn(),
  alert: vi.fn(),
  localStorageGet: vi.fn(),
  localStorageSet: vi.fn(),
  setColorTheme: vi.fn(),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ updateUISettings }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
vi.mock('shared/helpers/localStorage', () => ({
  LocalStorage: { get: localStorageGet, set: localStorageSet },
}));
vi.mock('dashboard/helper/themeHelper', () => ({ setColorTheme }));

const mountPreferences = () => {
  const i18n = createI18n({
    legacy: false,
    locale: 'es',
    messages: {
      es: {
        COMMAND_BAR: {
          COMMANDS: { DARK_MODE: 'Modo oscuro', LIGHT_MODE: 'Modo claro' },
        },
        PROFILE_SETTINGS: {
          FORM: {
            INTERFACE_SECTION: {
              LANGUAGE: { UPDATE_ERROR: 'Error al guardar el idioma' },
            },
          },
        },
      },
    },
  });

  return {
    i18n,
    wrapper: mount(SidebarQuickPreferences, {
      global: { plugins: [i18n] },
    }),
  };
};

describe('SidebarQuickPreferences', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorageGet.mockReturnValue('auto');
    updateUISettings.mockResolvedValue(true);
    window.matchMedia = vi.fn().mockReturnValue({ matches: false });
  });

  it('saves a user language preference and applies it immediately', async () => {
    const { i18n, wrapper } = mountPreferences();

    await wrapper.get('button[aria-label="English"]').trigger('click');
    await flushPromises();

    expect(updateUISettings).toHaveBeenCalledWith({ locale: 'en' });
    expect(i18n.global.locale.value).toBe('en');
  });

  it('does not change language when saving the preference fails', async () => {
    updateUISettings.mockResolvedValue(false);
    const { i18n, wrapper } = mountPreferences();

    await wrapper.get('button[aria-label="English"]').trigger('click');
    await flushPromises();

    expect(i18n.global.locale.value).toBe('es');
    expect(alert).toHaveBeenCalledWith('Error al guardar el idioma');
  });

  it('toggles between explicit light and dark themes', async () => {
    const { wrapper } = mountPreferences();

    await wrapper.findAll('button').at(2).trigger('click');

    expect(localStorageSet).toHaveBeenCalledWith('color_scheme', 'dark');
    expect(setColorTheme).toHaveBeenCalledWith(true);
  });
});
