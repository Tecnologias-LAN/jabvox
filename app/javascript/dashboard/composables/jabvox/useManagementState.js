/**
 * Shared helpers for applying a management state's note rule + dynamic questions
 * when an agent picks a state in conversations, leads, kanban or the dialer.
 */

// Resolves a namespaced lead_field key against the live lead/contact objects.
// Returns undefined when the field maps to nothing, so callers can skip it.
// Supported namespaces (must match the backend whitelist):
//   contact.<base>            -> contact.name / email / phone_number / …
//   contact.additional.<key>  -> contact.additional_attributes[key]
//   contact.custom.<key>      -> contact.custom_attributes[key]
//   lead.<key>                -> lead[key] (lead_number, custom_fields, …)
export function resolveLeadField(leadField, contact, lead) {
  if (!leadField) return undefined;
  const c = contact || {};
  const l = lead || {};

  if (leadField.startsWith('contact.additional.')) {
    const key = leadField.slice('contact.additional.'.length);
    return c.additional_attributes?.[key];
  }
  if (leadField.startsWith('contact.custom.')) {
    const key = leadField.slice('contact.custom.'.length);
    return c.custom_attributes?.[key];
  }
  if (leadField.startsWith('contact.')) {
    return c[leadField.slice('contact.'.length)];
  }
  if (leadField === 'lead.campaign') return l.campaign?.name ?? l.campaign;
  if (leadField.startsWith('lead.')) {
    const key = leadField.slice('lead.'.length);
    return l[key] ?? l.custom_fields_jabvox?.[key];
  }
  return undefined;
}

// Builds the initial answers map for a state, pre-filling any question that maps
// to a lead field. Existing answers win, so re-opening never clobbers edits.
export function seedAnswersFromLead(state, existing, contact, lead) {
  const answers = { ...(existing || {}) };
  (state?.questions || []).forEach(q => {
    if (!q.lead_field) return;
    if (answers[q.id] !== undefined && answers[q.id] !== '') return;
    const value = resolveLeadField(q.lead_field, contact, lead);
    if (value !== undefined && value !== null && `${value}` !== '') {
      answers[q.id] = value;
    }
  });
  return answers;
}

// Compares an answered value against a single visibility rule.
function ruleMatches(rule, value) {
  const target = `${rule.value ?? ''}`;
  switch (rule.operator) {
    case 'answered':
      if (Array.isArray(value)) return value.length > 0;
      return value !== undefined && value !== null && `${value}`.trim() !== '';
    case 'not_equals':
      if (Array.isArray(value)) return !value.map(String).includes(target);
      return `${value ?? ''}` !== target;
    case 'includes':
      if (Array.isArray(value)) return value.map(String).includes(target);
      return `${value ?? ''}` === target;
    case 'equals':
    default:
      if (Array.isArray(value))
        return value.length === 1 && `${value[0]}` === target;
      // booleans stored as true/false compare against the string 'true'/'false'
      return `${value ?? ''}` === target;
  }
}

// Whether a question should be shown given the current answers. A question with
// no rules is always visible. Rules reference OTHER questions by their label.
// This is the single source of truth used by both render and validation, so a
// hidden question is never rendered, never required, and never persisted.
export function isQuestionVisible(question, answers, questions) {
  const rules = question?.visibility?.rules;
  if (!Array.isArray(rules) || rules.length === 0) return true;

  const byLabel = {};
  (questions || []).forEach(q => {
    byLabel[q.label] = q;
  });

  const evaluate = rule => {
    const source = byLabel[rule.question];
    if (!source) return false; // rule points at a missing question -> not met
    return ruleMatches(rule, answers?.[source.id]);
  };

  const logic = question.visibility.logic === 'or' ? 'or' : 'and';
  return logic === 'or' ? rules.some(evaluate) : rules.every(evaluate);
}

// Serializes the answers map into the snapshot stored in content_attributes
// (and later materialized into jabvox_management_answers rows by the backend).
// Answers to hidden (condition-not-met) questions are dropped so we never
// persist data the agent could not see.
export function buildAnswersPayload(state, answers) {
  const questions = state?.questions || [];
  return questions
    .filter(question => isQuestionVisible(question, answers, questions))
    .map(question => {
      const value = answers?.[question.id];
      if (value === undefined || value === null || value === '') return null;
      if (Array.isArray(value) && value.length === 0) return null;
      return {
        question_id: question.id,
        label: question.label,
        type: question.question_type,
        value,
      };
    })
    .filter(Boolean);
}

// Whether the free-text note field should be shown / required / hidden.
export function noteRule(state) {
  const mode = state?.note_mode || 'optional';
  return {
    hidden: mode === 'hidden',
    required: mode === 'required',
    optional: mode === 'optional',
  };
}

// True when every required question is answered and the note rule is satisfied.
export function isManagementValid(state, answers, noteText) {
  if (!state) return true;
  const rule = noteRule(state);
  if (rule.required && !`${noteText || ''}`.trim()) return false;

  const questions = state.questions || [];
  return questions.every(question => {
    if (!question.required) return true;
    // A required question that is hidden by its conditions must not block save.
    if (!isQuestionVisible(question, answers, questions)) return true;
    const value = answers?.[question.id];
    if (question.question_type === 'boolean')
      return value === true || value === false;
    if (Array.isArray(value)) return value.length > 0;
    return value !== undefined && value !== null && `${value}`.trim() !== '';
  });
}

// Distinct group ("Estado") names among the given states, in list order.
export function stateGroups(states) {
  const groups = [];
  (states || []).forEach(state => {
    const group = state.state_group_jabvox || '';
    if (!groups.includes(group)) groups.push(group);
  });
  return groups;
}

// Substates that belong to a given group ('' = ungrouped/legacy).
export function statesInGroup(states, group) {
  return (states || []).filter(
    state => (state.state_group_jabvox || '') === (group || '')
  );
}

// Whether the account uses grouped states (any state carries a group). When
// false the pickers keep the historical single flat select.
export function hasGroups(states) {
  return (states || []).some(state => state.state_group_jabvox);
}

// Orígenes válidos de una gestión (de dónde se tipificó). Se guarda en
// content_attributes.jabvox_call_source y se muestra en el detalle del lead.
export const CALL_SOURCES = Object.freeze({
  DIALER: 'dialer',
  CLICK_TO_CALL: 'click_to_call',
  LEAD_DETAIL: 'lead_detail',
  // Ficha unificada del contacto, la que sustituye al detalle de lead.
  CONTACT_DETAIL: 'contact_detail',
  KANBAN: 'kanban',
  CONVERSATIONS: 'conversations',
});

// Builds the content_attributes block for the management state + answers.
// Includes the classification snapshot so history and reports keep the values
// even if the state's configuration changes later.
// `callSource` (uno de CALL_SOURCES) marca el ORIGEN de la gestión y SIEMPRE se
// incluye cuando se pasa — incluso en una nota libre sin estado —, para que el
// detalle del lead pueda mostrar desde dónde se tipificó. Centralizarlo aquí
// evita que cada origen tenga que acordarse de añadirlo por su cuenta (era la
// causa de que Kanban/Conversaciones guardaran gestiones sin marca de origen).
export function buildManagementContentAttributes(
  state,
  answers,
  callSource = null
) {
  const source = callSource ? { jabvox_call_source: callSource } : {};
  if (!state) return source;
  return {
    jabvox_management_state_id: state.id,
    jabvox_management_state_name: state.name_jabvox || '',
    jabvox_management_state_group: state.state_group_jabvox || '',
    jabvox_management_state_color: state.color_jabvox || '',
    jabvox_management_note_mode: state.note_mode || 'optional',
    jabvox_management_managed: state.managed_jabvox !== false,
    jabvox_management_contact: state.contact_jabvox === true,
    jabvox_management_effective_contact:
      state.effective_contact_jabvox === true,
    jabvox_management_advisory: state.advisory_jabvox === true,
    jabvox_management_service_type: state.service_type_jabvox || 'No',
    jabvox_management_positivity_level: state.positivity_level_jabvox || 0,
    jabvox_management_answers: buildAnswersPayload(state, answers),
    ...source,
  };
}
