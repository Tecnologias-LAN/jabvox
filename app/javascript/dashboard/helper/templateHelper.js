import {
  processVariable,
  buildWhatsAppProcessedParams,
  isWhatsAppComplete as isWhatsAppCompleteShared,
} from '@chatwoot/utils';

// Constants and pure template helpers are shared with the mobile app via
// @chatwoot/utils so the logic lives in one place.
export {
  MEDIA_FORMATS,
  COMPONENT_TYPES,
  findComponentByType,
  processVariable,
} from '@chatwoot/utils';

export const DEFAULT_LANGUAGE = 'en';
export const DEFAULT_CATEGORY = 'UTILITY';

export const allKeysRequired = value => {
  const keys = Object.keys(value);
  return keys.every(key => value[key]);
};

export const replaceTemplateVariables = (templateText, processedParams) => {
  return templateText.replace(/{{([^}]+)}}/g, (match, variable) => {
    const variableKey = processVariable(variable);
    return processedParams.body?.[variableKey] || `{{${variable}}}`;
  });
};

// @chatwoot/utils#buildButtonParams only recognizes URL (with a {{var}}) and
// COPY_CODE buttons — a FLOW button never lands in processed_params.buttons,
// so the backend never emits its button component and Meta rejects the send
// with "#131009 Components sub_type invalid at index: 0" (confirmed against a
// real production send; matches Chatwoot's own unresolved flow-support gap,
// github.com/chatwoot/chatwoot issue #13267). Meta requires a FLOW button
// unconditionally, unlike a static quick reply, so we add it here rather than
// forking the shared package.
const addFlowButtonParams = (template, params) => {
  const buttonsComponent = (template.components || []).find(
    component => component.type === 'BUTTONS'
  );
  if (!buttonsComponent?.buttons) return params;

  let found = false;
  const buttons = params.buttons ? [...params.buttons] : [];
  buttonsComponent.buttons.forEach((button, index) => {
    if (button.type !== 'FLOW') return;
    found = true;
    buttons[index] = { type: 'flow' };
  });

  return found ? { ...params, buttons } : params;
};

const findComponent = (template, type) =>
  (template.components || []).find(component => component.type === type);

// ¿La plantilla es de autenticación? Meta genera su cuerpo, así que al enviarla
// no se piden variables: solo el código, que viaja en el body Y en el botón.
export const isAuthenticationTemplate = template => {
  const buttons = findComponent(template, 'BUTTONS');
  return (buttons?.buttons || []).some(button => button.type === 'OTP');
};

export const hasLocationHeader = template =>
  findComponent(template, 'HEADER')?.format === 'LOCATION';

export const getCarouselCards = template =>
  findComponent(template, 'CAROUSEL')?.cards || [];

export const hasCarousel = template => getCarouselCards(template).length > 0;

export const hasLimitedTimeOffer = template =>
  Boolean(findComponent(template, 'LIMITED_TIME_OFFER'));

// Huecos extra que el paquete compartido no conoce (existen solo en estos
// tipos de plantilla). Se rellenan en la UI y viajan en processed_params con
// las mismas claves que espera el backend
// (Whatsapp::TemplateProcessorService + SendComponentsBuilder).
export const buildExtendedParams = template => {
  const params = {};
  if (isAuthenticationTemplate(template)) params.auth_code = '';
  if (hasLocationHeader(template)) {
    params.location = { latitude: '', longitude: '', name: '', address: '' };
  }
  if (hasLimitedTimeOffer(template)) params.lto_expiration_ms = '';
  if (hasCarousel(template)) {
    params.cards = getCarouselCards(template).map(card => ({
      header: { media_url: '' },
      buttons: (
        (card.components || []).find(c => c.type === 'BUTTONS')?.buttons || []
      ).map((button, index) => ({ index, type: button.type, parameter: '' })),
    }));
  }
  return params;
};

// The media-header flag is derived from the template inside the shared helper;
// the second argument is kept for backwards-compatible call sites.
export const buildTemplateParameters = template => {
  // El BODY de una plantilla de autenticación no trae `text` (Meta lo genera),
  // y el helper compartido asume que siempre existe: revienta al leerlo. Estas
  // plantillas no tienen variables que descubrir, solo el código.
  if (isAuthenticationTemplate(template)) return buildExtendedParams(template);

  return {
    ...addFlowButtonParams(template, buildWhatsAppProcessedParams(template)),
    ...buildExtendedParams(template),
  };
};

// @chatwoot/utils#isWhatsAppComplete treats any button with no `.parameter`
// as incomplete, which would permanently block sending a template that has a
// FLOW button (it never carries an agent-supplied parameter — see
// addFlowButtonParams above). Strip flow buttons before delegating so the
// shared completeness check only ever sees the buttons it knows how to judge.
// Campos obligatorios de los tipos que el paquete compartido no conoce.
const isExtendedComplete = (template, processedParams) => {
  if (isAuthenticationTemplate(template) && !processedParams.auth_code) {
    return false;
  }
  if (hasLocationHeader(template)) {
    const { latitude, longitude } = processedParams.location || {};
    if (!latitude || !longitude) return false;
  }
  if (hasLimitedTimeOffer(template) && !processedParams.lto_expiration_ms) {
    return false;
  }
  if (hasCarousel(template)) {
    const cards = processedParams.cards || [];
    if (cards.length !== getCarouselCards(template).length) return false;
    // Cada card necesita su media de cabecera; los botones de card llevan su
    // payload solo si la plantilla lo declara dinámico.
    if (cards.some(card => !card?.header?.media_url && !card?.header?.media_id))
      return false;
  }
  return true;
};

export const isWhatsAppComplete = (template, processedParams) => {
  if (!isExtendedComplete(template, processedParams)) return false;
  // El cuerpo de una plantilla de autenticación lo genera Meta: el chequeo
  // compartido buscaría variables que esta plantilla no tiene.
  if (isAuthenticationTemplate(template)) return true;

  if (!processedParams.buttons) {
    return isWhatsAppCompleteShared(template, processedParams);
  }

  const judgeableButtons = processedParams.buttons.filter(
    button => !button || button.type !== 'flow'
  );
  return isWhatsAppCompleteShared(template, {
    ...processedParams,
    buttons: judgeableButtons,
  });
};

// @chatwoot/utils#isSendableTemplate esconde del selector de envío las
// plantillas de autenticación y las de encabezado de ubicación, porque la
// interfaz de Chatwoot no sabe pedir el código OTP ni las coordenadas. Jabvox sí
// los pide (ver buildExtendedParams), así que aquí solo se mantienen las
// exclusiones que siguen siendo ciertas:
//   · la plantilla debe estar aprobada en Meta;
//   · las encuestas de satisfacción tienen su propio flujo;
//   · catálogo, listas y permiso de llamada no están implementados.
const UNSENDABLE_COMPONENTS = [
  'LIST',
  'PRODUCT',
  'CATALOG',
  'CALL_PERMISSION_REQUEST',
];

export const isSendableTemplate = template => {
  if (!template?.status || !template.components) return false;
  if (template.status.toLowerCase() !== 'approved') return false;
  if (template.name?.startsWith('customer_satisfaction_survey')) return false;

  return !template.components.some(component =>
    UNSENDABLE_COMPONENTS.includes(component.type)
  );
};
