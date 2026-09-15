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

// The media-header flag is derived from the template inside the shared helper;
// the second argument is kept for backwards-compatible call sites.
export const buildTemplateParameters = template =>
  addFlowButtonParams(template, buildWhatsAppProcessedParams(template));

// @chatwoot/utils#isWhatsAppComplete treats any button with no `.parameter`
// as incomplete, which would permanently block sending a template that has a
// FLOW button (it never carries an agent-supplied parameter — see
// addFlowButtonParams above). Strip flow buttons before delegating so the
// shared completeness check only ever sees the buttons it knows how to judge.
export const isWhatsAppComplete = (template, processedParams) => {
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
