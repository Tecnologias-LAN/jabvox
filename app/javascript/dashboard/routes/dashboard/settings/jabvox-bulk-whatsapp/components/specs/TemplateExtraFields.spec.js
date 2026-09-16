import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import TemplateExtraFields from '../TemplateExtraFields.vue';

// Campos de los tipos de plantilla no estándar en envío masivo.
// Ver docs/whatsapp-flows/templates-sending-architecture.md.
const i18n = createI18n({ legacy: false, locale: 'en', messages: { en: {} } });

const mountWith = (template, modelValue = {}) =>
  mount(TemplateExtraFields, {
    props: { template, modelValue },
    global: { plugins: [i18n] },
  });

// v-show deja el nodo montado y solo añade display:none; cuando es visible no
// hay atributo style en absoluto.
const isHidden = wrapper =>
  Boolean(wrapper.find('div').attributes('style')?.includes('display: none'));

describe('TemplateExtraFields', () => {
  it('permanece oculto para una plantilla estándar', () => {
    const wrapper = mountWith({
      name: 'simple',
      components: [{ type: 'BODY', text: 'Hola {{1}}' }],
    });

    expect(isHidden(wrapper)).toBe(true);
  });

  it('pide el código en una plantilla de autenticación', async () => {
    const wrapper = mountWith({
      name: 'otp',
      components: [
        { type: 'BODY' },
        { type: 'BUTTONS', buttons: [{ type: 'OTP', otp_type: 'COPY_CODE' }] },
      ],
    });

    expect(isHidden(wrapper)).toBe(false);
    await wrapper.find('input[type="text"]').setValue('123456');

    const emitted = wrapper.emitted('update:modelValue');
    expect(emitted.at(-1)[0].authCode).toBe('123456');
  });

  it('pide los cuatro campos de una ubicación', () => {
    const wrapper = mountWith({
      name: 'loc',
      components: [
        { type: 'HEADER', format: 'LOCATION' },
        { type: 'BODY', text: 'Hola' },
      ],
    });

    expect(wrapper.findAll('input')).toHaveLength(4);
  });

  it('pide el cupón cuando la plantilla tiene botón COPY_CODE', async () => {
    const wrapper = mountWith({
      name: 'cupon',
      components: [
        { type: 'BODY', text: 'Tu cupón' },
        { type: 'BUTTONS', buttons: [{ type: 'COPY_CODE', text: 'Copiar' }] },
      ],
    });

    await wrapper.find('input[type="text"]').setValue('VERANO25');

    expect(wrapper.emitted('update:modelValue').at(-1)[0].copyCode).toBe(
      'VERANO25'
    );
  });

  it('convierte la fecha de la oferta a epoch en milisegundos', async () => {
    const wrapper = mountWith({
      name: 'lto',
      components: [
        { type: 'BODY', text: 'Oferta' },
        { type: 'LIMITED_TIME_OFFER' },
      ],
    });

    await wrapper
      .find('input[type="datetime-local"]')
      .setValue('2027-01-01T10:00');

    const value = wrapper
      .emitted('update:modelValue')
      .at(-1)[0].ltoExpirationMs;
    expect(typeof value).toBe('number');
    expect(value).toBe(new Date('2027-01-01T10:00').getTime());
  });

  it('muestra una entrada de media y otra de botón por cada card', async () => {
    const card = {
      components: [
        { type: 'HEADER', format: 'IMAGE' },
        { type: 'BUTTONS', buttons: [{ type: 'QUICK_REPLY', text: 'Ver' }] },
      ],
    };
    const wrapper = mountWith({
      name: 'carrusel',
      components: [
        { type: 'BODY', text: 'Hola' },
        { type: 'CAROUSEL', cards: [card, card] },
      ],
    });

    // 2 cards x (media + botón)
    expect(wrapper.findAll('input')).toHaveLength(4);

    await wrapper.find('input[type="url"]').setValue('https://x/1.jpg');
    expect(
      wrapper.emitted('update:modelValue').at(-1)[0].cards[0].header.media_url
    ).toBe('https://x/1.jpg');
  });
});
