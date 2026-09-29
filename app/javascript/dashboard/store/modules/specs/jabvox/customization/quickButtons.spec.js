import customization from '../../../jabvox/customization';
import api from '../../../../../api/jabvox/customization';

vi.mock('../../../../../api/jabvox/customization', () => ({
  default: { getButtons: vi.fn() },
}));

// Los botones rápidos se montan una vez por tarjeta del kanban y por cabecera de
// conversación. La guarda vivía en el componente y comprobaba `buttons.length`, así que una
// cuenta SIN botones dejaba la lista vacía para siempre y cada tarjeta repetía la petición:
// seis tarjetas visibles eran seis GET idénticos por render.
const { actions, mutations } = customization;

const runFetch = async (stateOverrides, payload) => {
  const commit = vi.fn();
  const state = {
    buttonsLoaded: false,
    uiFlags: { isFetchingButtons: false },
    ...(stateOverrides || {}),
  };
  await actions.fetchButtons({ commit, state }, payload);
  return commit;
};

describe('fetchButtons', () => {
  beforeEach(() => {
    api.getButtons.mockReset();
    api.getButtons.mockResolvedValue({ data: [] });
  });

  it('pide los botones la primera vez', async () => {
    await runFetch({});
    expect(api.getButtons).toHaveBeenCalledTimes(1);
  });

  it('no vuelve a pedirlos aunque la cuenta no tenga ninguno', async () => {
    await runFetch({ buttonsLoaded: true });
    expect(api.getButtons).not.toHaveBeenCalled();
  });

  it('no lanza una segunda petición mientras la primera está en curso', async () => {
    await runFetch({ uiFlags: { isFetchingButtons: true } });
    expect(api.getButtons).not.toHaveBeenCalled();
  });

  it('con force vuelve a pedirlos, para la pantalla de ajustes', async () => {
    await runFetch({ buttonsLoaded: true }, { force: true });
    expect(api.getButtons).toHaveBeenCalledTimes(1);
  });

  it('marca buttonsLoaded al guardar, incluso con lista vacía', () => {
    const state = { buttons: [], buttonsLoaded: false };
    mutations.SET_BUTTONS(state, []);
    expect(state.buttonsLoaded).toBe(true);
  });
});
