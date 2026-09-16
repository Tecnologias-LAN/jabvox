import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import InlineFlowBuilder from '../InlineFlowBuilder.vue';

// El builder embebido reutiliza los componentes del módulo de Flows, así que
// este spec vigila sobre todo que ese acoplamiento siga funcionando.
const i18n = createI18n({ legacy: false, locale: 'en', messages: { en: {} } });

const mountWith = (modelValue = []) =>
  mount(InlineFlowBuilder, {
    props: { modelValue },
    global: { plugins: [i18n] },
  });

const screenWith = (id, order, components = []) => ({
  id,
  title: id,
  terminal: false,
  order,
  components,
});

describe('InlineFlowBuilder', () => {
  it('monta sin errores con el formulario vacío', () => {
    expect(mountWith().exists()).toBe(true);
  });

  // Sin esto el usuario vería un lienzo en blanco sin saber por dónde empezar.
  it('crea una primera pantalla automáticamente', () => {
    const wrapper = mountWith();

    const emitted = wrapper.emitted('update:modelValue');
    expect(emitted).toBeTruthy();
    expect(emitted[0][0]).toHaveLength(1);
  });

  it('no vuelve a crear pantallas si ya hay uno', () => {
    const wrapper = mountWith([screenWith('welcome', 0)]);

    expect(wrapper.emitted('update:modelValue')).toBeFalsy();
  });

  it('avisa cuando ninguna pantalla está marcada como final', () => {
    const wrapper = mountWith([screenWith('welcome', 0)]);

    expect(wrapper.vm.issues.some(i => i.includes('NEEDS_TERMINAL'))).toBe(
      true
    );
  });

  it('avisa de las pantallas sin botón de avance', () => {
    const wrapper = mountWith([
      { ...screenWith('welcome', 0), terminal: true, components: [] },
    ]);

    expect(wrapper.vm.issues.some(i => i.includes('NEEDS_FOOTER'))).toBe(true);
  });

  // El usuario no debería tener que descubrir que Meta exige un botón por
  // pantalla: viene puesto y solo cambia el texto si quiere.
  it('crea la primera pantalla con su botón de envío ya puesto', () => {
    const wrapper = mountWith();

    const [screens] = wrapper.emitted('update:modelValue')[0];
    const footer = screens[0].components.find(c => c.type === 'Footer');
    expect(footer).toBeTruthy();
    expect(footer.props.action).toEqual({ name: 'complete' });
  });

  it('al añadir una pantalla, la anterior pasa a avanzar hacia ella', async () => {
    const wrapper = mountWith([
      {
        ...screenWith('welcome', 0),
        terminal: true,
        components: [
          {
            id: 'f1',
            type: 'Footer',
            props: { label: 'Enviar', action: { name: 'complete' } },
          },
        ],
      },
    ]);

    await wrapper.findComponent({ name: 'ScreenList' }).vm.$emit('add');

    const emitted = wrapper.emitted('update:modelValue');
    const screens = emitted[emitted.length - 1][0];
    expect(screens).toHaveLength(2);
    // La primera ya no cierra el formulario: navega a la nueva.
    expect(screens[0].terminal).toBe(false);
    expect(screens[0].components[0].props.action).toEqual({
      name: 'navigate',
      next: screens[1].id,
    });
    // Y la última es la que ahora lo cierra.
    expect(screens[1].terminal).toBe(true);
    expect(screens[1].components[0].props.action).toEqual({ name: 'complete' });
  });

  it('no reporta problemas cuando el formulario está completo', () => {
    const footer = {
      id: 'f1',
      type: 'Footer',
      props: { label: 'Enviar', action: { name: 'complete' } },
    };
    const wrapper = mountWith([
      { ...screenWith('welcome', 0), terminal: true, components: [footer] },
    ]);

    expect(wrapper.vm.issues).toHaveLength(0);
  });
});
