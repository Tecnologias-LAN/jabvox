import {
  isQuestionVisible,
  buildAnswersPayload,
  isManagementValid,
  resolveLeadField,
  seedAnswersFromLead,
} from '../useManagementState';

const q = (id, label, extra = {}) => ({
  id,
  label,
  question_type: 'text',
  required: false,
  ...extra,
});

describe('isQuestionVisible', () => {
  const source = q(1, 'Transferencia', { question_type: 'boolean' });
  const dependent = q(2, 'Motivo', {
    visibility: {
      logic: 'and',
      rules: [{ question: 'Transferencia', operator: 'equals', value: 'true' }],
    },
  });
  const questions = [source, dependent];

  it('shows a question with no rules', () => {
    expect(isQuestionVisible(q(9, 'X'), {}, questions)).toBe(true);
  });

  it('hides when the equals condition is not met', () => {
    expect(isQuestionVisible(dependent, { 1: false }, questions)).toBe(false);
  });

  it('shows when the equals condition is met', () => {
    expect(isQuestionVisible(dependent, { 1: true }, questions)).toBe(true);
  });

  it('hides when the referenced question is missing', () => {
    const orphan = q(3, 'Y', {
      visibility: { rules: [{ question: 'NoExiste', operator: 'answered' }] },
    });
    expect(isQuestionVisible(orphan, {}, [orphan])).toBe(false);
  });

  it('supports the answered operator', () => {
    const dep = q(3, 'Y', {
      visibility: {
        rules: [{ question: 'Transferencia', operator: 'answered' }],
      },
    });
    expect(isQuestionVisible(dep, { 1: false }, [source, dep])).toBe(true);
    expect(isQuestionVisible(dep, {}, [source, dep])).toBe(false);
  });

  it('supports includes against multiselect arrays', () => {
    const multi = q(1, 'Canales', { question_type: 'multiselect' });
    const dep = q(2, 'Y', {
      visibility: {
        rules: [{ question: 'Canales', operator: 'includes', value: 'Chat' }],
      },
    });
    expect(isQuestionVisible(dep, { 1: ['Chat', 'OV'] }, [multi, dep])).toBe(
      true
    );
    expect(isQuestionVisible(dep, { 1: ['OV'] }, [multi, dep])).toBe(false);
  });

  it('honours OR logic', () => {
    const a = q(1, 'A', { question_type: 'boolean' });
    const b = q(2, 'B', { question_type: 'boolean' });
    const dep = q(3, 'Y', {
      visibility: {
        logic: 'or',
        rules: [
          { question: 'A', operator: 'equals', value: 'true' },
          { question: 'B', operator: 'equals', value: 'true' },
        ],
      },
    });
    const all = [a, b, dep];
    expect(isQuestionVisible(dep, { 1: false, 2: true }, all)).toBe(true);
    expect(isQuestionVisible(dep, { 1: false, 2: false }, all)).toBe(false);
  });
});

describe('buildAnswersPayload', () => {
  it('drops answers to hidden questions', () => {
    const state = {
      questions: [
        q(1, 'Transferencia', { question_type: 'boolean' }),
        q(2, 'Motivo', {
          visibility: {
            rules: [
              { question: 'Transferencia', operator: 'equals', value: 'true' },
            ],
          },
        }),
      ],
    };
    // Motivo answered but its condition is NOT met -> must be dropped
    const payload = buildAnswersPayload(state, { 1: false, 2: 'algo' });
    expect(payload.map(a => a.question_id)).toEqual([1]);
  });

  it('keeps multiselect arrays and drops empty arrays', () => {
    const state = {
      questions: [
        q(1, 'Canales', { question_type: 'multiselect' }),
        q(2, 'Otros', { question_type: 'multiselect' }),
      ],
    };
    const payload = buildAnswersPayload(state, { 1: ['Chat'], 2: [] });
    expect(payload).toHaveLength(1);
    expect(payload[0].value).toEqual(['Chat']);
  });
});

describe('resolveLeadField', () => {
  const contact = {
    name: 'Ana',
    phone_number: '+573001234567',
    additional_attributes: { country: 'Colombia' },
    custom_attributes: { ciclo_c: '202610' },
  };
  const lead = {
    lead_number: 42,
    campaign: { name: 'Zafiro' },
    custom_fields_jabvox: { zona_c: '135' },
  };

  it('resolves base contact fields', () => {
    expect(resolveLeadField('contact.name', contact, lead)).toBe('Ana');
    expect(resolveLeadField('contact.phone_number', contact, lead)).toBe(
      '+573001234567'
    );
  });

  it('resolves additional and custom attributes', () => {
    expect(resolveLeadField('contact.additional.country', contact, lead)).toBe(
      'Colombia'
    );
    expect(resolveLeadField('contact.custom.ciclo_c', contact, lead)).toBe(
      '202610'
    );
  });

  it('resolves lead metadata and custom fields', () => {
    expect(resolveLeadField('lead.lead_number', contact, lead)).toBe(42);
    expect(resolveLeadField('lead.campaign', contact, lead)).toBe('Zafiro');
    expect(resolveLeadField('lead.zona_c', contact, lead)).toBe('135');
  });

  it('returns undefined for empty or unknown fields', () => {
    expect(resolveLeadField('', contact, lead)).toBeUndefined();
    expect(resolveLeadField('contact.nope', contact, lead)).toBeUndefined();
    expect(resolveLeadField('lead.nope', contact, lead)).toBeUndefined();
  });
});

describe('seedAnswersFromLead', () => {
  const contact = { phone_number: '+573001234567' };
  const state = {
    questions: [
      {
        id: 1,
        label: 'Tel',
        question_type: 'text',
        lead_field: 'contact.phone_number',
      },
      { id: 2, label: 'Libre', question_type: 'text', lead_field: '' },
    ],
  };

  it('pre-fills a mapped question when blank', () => {
    const seeded = seedAnswersFromLead(state, {}, contact, {});
    expect(seeded[1]).toBe('+573001234567');
    expect(seeded[2]).toBeUndefined();
  });

  it('never overwrites an existing answer', () => {
    const seeded = seedAnswersFromLead(state, { 1: 'manual' }, contact, {});
    expect(seeded[1]).toBe('manual');
  });
});

describe('isManagementValid', () => {
  it('does not block on a required question that is hidden', () => {
    const state = {
      note_mode: 'optional',
      questions: [
        q(1, 'Transferencia', { question_type: 'boolean' }),
        q(2, 'Motivo', {
          required: true,
          visibility: {
            rules: [
              { question: 'Transferencia', operator: 'equals', value: 'true' },
            ],
          },
        }),
      ],
    };
    // condition not met -> Motivo hidden -> valid even though unanswered
    expect(isManagementValid(state, { 1: false }, '')).toBe(true);
    // condition met -> Motivo required and unanswered -> invalid
    expect(isManagementValid(state, { 1: true }, '')).toBe(false);
  });
});
