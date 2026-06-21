/**
 * Shared helpers for applying a management state's note rule + dynamic questions
 * when an agent picks a state in conversations, leads, kanban or the dialer.
 */

// Serializes the answers map into the snapshot stored in content_attributes
// (and later materialized into jabvox_management_answers rows by the backend).
export function buildAnswersPayload(state, answers) {
  const questions = state?.questions || [];
  return questions
    .map(question => {
      const value = answers?.[question.id];
      if (value === undefined || value === null || value === '') return null;
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

  return (state.questions || []).every(question => {
    if (!question.required) return true;
    const value = answers?.[question.id];
    if (question.question_type === 'boolean')
      return value === true || value === false;
    if (Array.isArray(value)) return value.length > 0;
    return value !== undefined && value !== null && `${value}`.trim() !== '';
  });
}

// Builds the content_attributes block for the management state + answers.
export function buildManagementContentAttributes(state, answers) {
  if (!state) return {};
  return {
    jabvox_management_state_id: state.id,
    jabvox_management_state_name: state.name_jabvox || '',
    jabvox_management_state_color: state.color_jabvox || '',
    jabvox_management_note_mode: state.note_mode || 'optional',
    jabvox_management_answers: buildAnswersPayload(state, answers),
  };
}
