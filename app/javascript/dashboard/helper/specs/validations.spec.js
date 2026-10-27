import { describe, it, expect } from 'vitest';
import { validateAutomation } from '../validations';

describe('validateAutomation', () => {
  it('should return no errors for a valid automation', () => {
    const validAutomation = {
      name: 'Test Automation',
      description: 'A test automation',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'content',
          filter_operator: 'contains',
          values: 'hello',
        },
      ],
      actions: [
        { action_name: 'send_message', action_params: ['Hello there!'] },
      ],
    };
    const errors = validateAutomation(validAutomation);
    expect(errors).toEqual({});
  });

  it('should return errors for missing basic fields', () => {
    const invalidAutomation = {
      name: '',
      description: '',
      event_name: '',
      conditions: [],
      actions: [],
    };
    const errors = validateAutomation(invalidAutomation);
    expect(errors).toHaveProperty('name');
    expect(errors).toHaveProperty('description');
    expect(errors).toHaveProperty('event_name');
  });

  it('should return errors for invalid conditions', () => {
    const automationWithInvalidConditions = {
      name: 'Test',
      description: 'Test',
      event_name: 'message_created',
      conditions: [{ attribute_key: '', filter_operator: '', values: '' }],
      actions: [{ action_name: 'send_message', action_params: ['Hello'] }],
    };
    const errors = validateAutomation(automationWithInvalidConditions);
    expect(errors).toHaveProperty('condition_0');
  });

  it('should return errors for invalid actions', () => {
    const automationWithInvalidActions = {
      name: 'Test',
      description: 'Test',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'content',
          filter_operator: 'contains',
          values: 'hello',
        },
      ],
      actions: [{ action_name: 'send_message', action_params: [] }],
    };
    const errors = validateAutomation(automationWithInvalidActions);
    expect(errors).toHaveProperty('action_0');
  });

  it('should not flag a valid GROUP condition as invalid', () => {
    // Regresión: validar un nodo { type: 'group' } como filtro plano fallaba
    // siempre (no tiene attribute_key), encendiendo el recuadro de condiciones
    // en rojo sin texto. Debe validar las hijas del grupo en su lugar.
    const automationWithGroup = {
      name: 'Test',
      description: 'Test',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'message_type',
          filter_operator: 'equal_to',
          values: ['incoming'],
        },
        {
          type: 'group',
          child_operator: 'or',
          conditions: [
            {
              attribute_key: 'labels',
              filter_operator: 'not_equal_to',
              values: ['asesor-diferente'],
            },
            {
              attribute_key: 'labels',
              filter_operator: 'is_not_present',
            },
          ],
        },
      ],
      actions: [{ action_name: 'mute_conversation' }],
    };
    const errors = validateAutomation(automationWithGroup);
    expect(errors).toEqual({});
  });

  it('should flag an empty GROUP as invalid', () => {
    const automationWithEmptyGroup = {
      name: 'Test',
      description: 'Test',
      event_name: 'message_created',
      conditions: [{ type: 'group', child_operator: 'or', conditions: [] }],
      actions: [{ action_name: 'mute_conversation' }],
    };
    const errors = validateAutomation(automationWithEmptyGroup);
    expect(errors).toHaveProperty('condition_0');
  });

  it('should not require action params for specific actions', () => {
    const automationWithNoParamAction = {
      name: 'Test',
      description: 'Test',
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'content',
          filter_operator: 'contains',
          values: 'hello',
        },
      ],
      actions: [{ action_name: 'mute_conversation' }],
    };
    const errors = validateAutomation(automationWithNoParamAction);
    expect(errors).toEqual({});
  });
});
