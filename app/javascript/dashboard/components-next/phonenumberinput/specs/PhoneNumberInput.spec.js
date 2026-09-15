import { mount } from '@vue/test-utils';
import PhoneNumberInput from '../PhoneNumberInput.vue';

const mountInput = (modelValue = '') =>
  mount(PhoneNumberInput, {
    props: { modelValue },
    global: {
      mocks: { $t: key => key },
      stubs: { Button: true, DropdownMenu: true },
      // La directiva del componente no aplica en pruebas de unidad.
      directives: { 'on-clickaway': () => {} },
    },
  });

// El campo de teléfono local, donde el usuario teclea el número sin prefijo.
const nationalInput = wrapper => wrapper.find('input[type="tel"]');

describe('PhoneNumberInput', () => {
  describe('al editar un contacto existente', () => {
    it('separa el país y el número local del valor guardado', () => {
      const wrapper = mountInput('+573001234567');

      expect(nationalInput(wrapper).element.value).toBe('3001234567');
    });

    it('usa el prefijo más largo, igual que el backend', () => {
      // +1684 (Samoa Americana). Partirlo como +1 dejaría el campo local
      // descuadrado respecto a lo que el backend tiene guardado.
      const wrapper = mountInput('+16847331234');

      expect(nationalInput(wrapper).element.value).toBe('7331234');
    });

    it('NO deja el campo vacío con un número que libphonenumber no reconoce', () => {
      // Antes el campo quedaba vacío y al guardar se BORRABA el teléfono.
      const wrapper = mountInput('+999123456789');

      expect(nationalInput(wrapper).element.value).not.toBe('');
      expect(nationalInput(wrapper).element.value).toContain('999123456789');
    });

    it('el campo local nunca muestra el prefijo', () => {
      const wrapper = mountInput('+573001234567');

      expect(nationalInput(wrapper).element.value.startsWith('57')).toBe(false);
    });

    it('un contacto sin teléfono deja el campo vacío, sin romperse', () => {
      const wrapper = mountInput('');

      expect(nationalInput(wrapper).element.value).toBe('');
    });
  });

  describe('al escribir un número', () => {
    it('emite el E.164 completo, con el prefijo del país', async () => {
      const wrapper = mountInput('+573001234567');

      await nationalInput(wrapper).setValue('3009999999');

      const emitted = wrapper.emitted('update:modelValue');
      expect(emitted).toBeTruthy();
      expect(emitted.at(-1)[0]).toBe('+573009999999');
    });

    it('vaciar el campo emite cadena vacía, no un prefijo suelto', async () => {
      const wrapper = mountInput('+573001234567');

      await nationalInput(wrapper).setValue('');

      const emitted = wrapper.emitted('update:modelValue');
      expect(emitted.at(-1)[0]).toBe('');
    });
  });
});
