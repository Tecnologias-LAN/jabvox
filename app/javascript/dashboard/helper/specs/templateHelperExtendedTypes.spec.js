import {
  isSendableTemplate,
  buildTemplateParameters,
  isWhatsAppComplete,
  isAuthenticationTemplate,
  hasLocationHeader,
  hasCarousel,
  hasLimitedTimeOffer,
  getCarouselCards,
} from '../templateHelper';

// Tipos de plantilla que el paquete compartido (@chatwoot/utils) no conoce y
// que Jabvox sí soporta al enviar. Ver
// docs/whatsapp-flows/templates-sending-architecture.md.
describe('templateHelper — tipos extendidos', () => {
  const authTemplate = {
    name: 'otp_login',
    category: 'AUTHENTICATION',
    components: [
      { type: 'BODY', add_security_recommendation: true },
      { type: 'BUTTONS', buttons: [{ type: 'OTP', otp_type: 'COPY_CODE' }] },
    ],
  };

  const locationTemplate = {
    name: 'delivery',
    components: [
      { type: 'HEADER', format: 'LOCATION' },
      { type: 'BODY', text: 'Tu pedido llega a {{1}}' },
    ],
  };

  const carouselTemplate = {
    name: 'promo',
    components: [
      { type: 'BODY', text: 'Hola {{1}}' },
      {
        type: 'CAROUSEL',
        cards: [
          {
            components: [
              { type: 'HEADER', format: 'IMAGE' },
              {
                type: 'BUTTONS',
                buttons: [{ type: 'QUICK_REPLY', text: 'A' }],
              },
            ],
          },
          {
            components: [
              { type: 'HEADER', format: 'IMAGE' },
              {
                type: 'BUTTONS',
                buttons: [{ type: 'QUICK_REPLY', text: 'B' }],
              },
            ],
          },
        ],
      },
    ],
  };

  const ltoTemplate = {
    name: 'oferta',
    category: 'MARKETING',
    components: [
      { type: 'BODY', text: 'Oferta {{1}}' },
      { type: 'LIMITED_TIME_OFFER' },
    ],
  };

  const plainTemplate = {
    name: 'simple',
    components: [{ type: 'BODY', text: 'Hola {{1}}' }],
  };

  describe('detección de tipo', () => {
    it('reconoce una plantilla de autenticación por su botón OTP', () => {
      expect(isAuthenticationTemplate(authTemplate)).toBe(true);
      expect(isAuthenticationTemplate(plainTemplate)).toBe(false);
    });

    it('reconoce un header LOCATION', () => {
      expect(hasLocationHeader(locationTemplate)).toBe(true);
      expect(hasLocationHeader(plainTemplate)).toBe(false);
    });

    it('reconoce un carousel y cuenta sus cards', () => {
      expect(hasCarousel(carouselTemplate)).toBe(true);
      expect(getCarouselCards(carouselTemplate)).toHaveLength(2);
      expect(hasCarousel(plainTemplate)).toBe(false);
    });

    it('reconoce una oferta por tiempo limitado', () => {
      expect(hasLimitedTimeOffer(ltoTemplate)).toBe(true);
      expect(hasLimitedTimeOffer(plainTemplate)).toBe(false);
    });
  });

  describe('buildTemplateParameters', () => {
    it('prepara el hueco del código en una plantilla de autenticación', () => {
      expect(buildTemplateParameters(authTemplate)).toHaveProperty(
        'auth_code',
        ''
      );
    });

    it('prepara los cuatro campos de una ubicación', () => {
      expect(buildTemplateParameters(locationTemplate).location).toEqual({
        latitude: '',
        longitude: '',
        name: '',
        address: '',
      });
    });

    it('prepara una card por cada una declarada, con sus botones', () => {
      const { cards } = buildTemplateParameters(carouselTemplate);
      expect(cards).toHaveLength(2);
      expect(cards[0].buttons).toEqual([
        { index: 0, type: 'QUICK_REPLY', parameter: '' },
      ]);
    });

    it('prepara el hueco de expiración de una oferta', () => {
      expect(buildTemplateParameters(ltoTemplate)).toHaveProperty(
        'lto_expiration_ms',
        ''
      );
    });

    it('no añade campos extra a una plantilla estándar', () => {
      const params = buildTemplateParameters(plainTemplate);
      expect(params.auth_code).toBeUndefined();
      expect(params.cards).toBeUndefined();
      expect(params.location).toBeUndefined();
      expect(params.lto_expiration_ms).toBeUndefined();
    });
  });

  describe('isWhatsAppComplete', () => {
    it('bloquea el envío de autenticación sin código y lo permite con él', () => {
      expect(isWhatsAppComplete(authTemplate, { auth_code: '' })).toBe(false);
      expect(isWhatsAppComplete(authTemplate, { auth_code: '123456' })).toBe(
        true
      );
    });

    it('exige latitud y longitud en un header de ubicación', () => {
      const body = { body: { 1: 'hoy' } };
      expect(
        isWhatsAppComplete(locationTemplate, {
          ...body,
          location: { latitude: '', longitude: '' },
        })
      ).toBe(false);
      expect(
        isWhatsAppComplete(locationTemplate, {
          ...body,
          location: { latitude: '4.7', longitude: '-74.07' },
        })
      ).toBe(true);
    });

    it('exige la media de cabecera de cada card del carousel', () => {
      const base = { body: { 1: 'Pablo' } };
      expect(
        isWhatsAppComplete(carouselTemplate, {
          ...base,
          cards: [
            { header: { media_url: 'https://x/1.jpg' } },
            { header: { media_url: '' } },
          ],
        })
      ).toBe(false);
      expect(
        isWhatsAppComplete(carouselTemplate, {
          ...base,
          cards: [
            { header: { media_url: 'https://x/1.jpg' } },
            { header: { media_url: 'https://x/2.jpg' } },
          ],
        })
      ).toBe(true);
    });

    it('rechaza un carousel con menos cards de las declaradas', () => {
      expect(
        isWhatsAppComplete(carouselTemplate, {
          body: { 1: 'Pablo' },
          cards: [{ header: { media_url: 'https://x/1.jpg' } }],
        })
      ).toBe(false);
    });

    it('exige la fecha de expiración de una oferta', () => {
      const base = { body: { 1: 'Pablo' } };
      expect(
        isWhatsAppComplete(ltoTemplate, { ...base, lto_expiration_ms: '' })
      ).toBe(false);
      expect(
        isWhatsAppComplete(ltoTemplate, {
          ...base,
          lto_expiration_ms: 1735689600000,
        })
      ).toBe(true);
    });
  });

  // El filtro compartido de Chatwoot escondía las de autenticación y las de
  // ubicación porque su interfaz no sabía pedir el código ni las coordenadas;
  // Jabvox sí, así que deben aparecer en el selector de envío.
  describe('isSendableTemplate', () => {
    const approved = extra => ({
      status: 'APPROVED',
      components: [{ type: 'BODY', text: 'Hola' }],
      ...extra,
    });

    it('acepta una plantilla aprobada normal', () => {
      expect(isSendableTemplate(approved())).toBe(true);
    });

    it('acepta una plantilla de autenticación', () => {
      expect(
        isSendableTemplate(
          approved({
            category: 'AUTHENTICATION',
            components: [
              { type: 'BODY' },
              { type: 'BUTTONS', buttons: [{ type: 'OTP' }] },
            ],
          })
        )
      ).toBe(true);
    });

    it('acepta una plantilla con encabezado de ubicación', () => {
      expect(
        isSendableTemplate(
          approved({
            components: [
              { type: 'HEADER', format: 'LOCATION' },
              { type: 'BODY', text: 'Hola' },
            ],
          })
        )
      ).toBe(true);
    });

    it('rechaza una plantilla que Meta no ha aprobado', () => {
      expect(isSendableTemplate(approved({ status: 'PENDING' }))).toBe(false);
    });

    it('rechaza las encuestas de satisfacción, que tienen su propio flujo', () => {
      expect(
        isSendableTemplate(approved({ name: 'customer_satisfaction_survey_1' }))
      ).toBe(false);
    });

    it('rechaza catálogo y listas, que no están implementados', () => {
      expect(
        isSendableTemplate(approved({ components: [{ type: 'CATALOG' }] }))
      ).toBe(false);
      expect(
        isSendableTemplate(approved({ components: [{ type: 'LIST' }] }))
      ).toBe(false);
    });
  });
});
