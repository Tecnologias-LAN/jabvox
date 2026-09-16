import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

// El componente lo comparten conversación, Leads y Kanban, así que estos tipos
// deben renderizar en los tres. Ver
// docs/whatsapp-flows/templates-sending-architecture.md.
const i18n = createI18n({ legacy: false, locale: 'en', messages: { en: {} } });

const mountWith = template =>
  mount(WhatsAppTemplateParser, {
    props: { template },
    global: { plugins: [i18n] },
  });

const inputCount = wrapper => wrapper.findAll('input').length;

describe('WhatsAppTemplateParser', () => {
  it('renderiza una plantilla estándar mostrando su cuerpo', () => {
    const wrapper = mountWith({
      name: 'x',
      components: [{ type: 'BODY', text: 'Hola {{1}}' }],
    });

    expect(wrapper.text()).toContain('Hola');
  });

  // El BODY de una plantilla de autenticación no trae `text` y el helper
  // compartido reventaba al leerlo: esto cubre esa regresión.
  it('renderiza una plantilla de autenticación pidiendo solo el código', () => {
    const wrapper = mountWith({
      name: 'otp',
      category: 'AUTHENTICATION',
      components: [
        { type: 'BODY', add_security_recommendation: true },
        { type: 'BUTTONS', buttons: [{ type: 'OTP', otp_type: 'COPY_CODE' }] },
      ],
    });

    expect(wrapper.exists()).toBe(true);
    expect(inputCount(wrapper)).toBe(1);
  });

  it('renderiza los cuatro campos de un header de ubicación', () => {
    const wrapper = mountWith({
      name: 'loc',
      components: [
        { type: 'HEADER', format: 'LOCATION' },
        { type: 'BODY', text: 'Hola' },
      ],
    });

    // latitud, longitud, nombre y dirección.
    expect(inputCount(wrapper)).toBe(4);
  });

  it('renderiza una entrada de media por cada card del carrusel', () => {
    const card = {
      components: [
        { type: 'HEADER', format: 'IMAGE' },
        { type: 'BUTTONS', buttons: [{ type: 'QUICK_REPLY', text: 'A' }] },
      ],
    };
    const wrapper = mountWith({
      name: 'car',
      components: [
        { type: 'BODY', text: 'Hola {{1}}' },
        { type: 'CAROUSEL', cards: [card, card] },
      ],
    });

    // 2 cards x (media + botón). La variable del cuerpo usa el componente
    // Input de Jabvox, que no expone un <input> plano en el entorno de test.
    expect(inputCount(wrapper)).toBe(4);
  });

  it('renderiza el selector de vencimiento de una oferta por tiempo limitado', () => {
    const wrapper = mountWith({
      name: 'lto',
      category: 'MARKETING',
      components: [
        { type: 'BODY', text: 'Oferta {{1}}' },
        { type: 'LIMITED_TIME_OFFER' },
      ],
    });

    expect(wrapper.find('input[type="datetime-local"]').exists()).toBe(true);
  });
});
