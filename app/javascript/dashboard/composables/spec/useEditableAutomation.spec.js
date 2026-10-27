import { useEditableAutomation } from '../useEditableAutomation';
import useAutomationValues from '../useAutomationValues';

vi.mock('../useAutomationValues');

describe('useEditableAutomation', () => {
  beforeEach(() => {
    useAutomationValues.mockReturnValue({
      getConditionDropdownValues: vi.fn(attributeKey => {
        if (attributeKey === 'private_note') {
          return [
            { id: true, name: 'True' },
            { id: false, name: 'False' },
          ];
        }

        return [];
      }),
      getActionDropdownValues: vi.fn(actionName => {
        if (actionName === 'assign_agent') {
          return [
            { id: 'nil', name: 'None' },
            {
              id: 'last_responding_agent',
              name: 'Last Responding Agent',
            },
            { id: 1, name: 'Agent 1' },
          ];
        }

        return [];
      }),
    });
  });

  it('rehydrates boolean conditions as a single selected option', () => {
    const automation = {
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'private_note',
          filter_operator: 'equal_to',
          values: [false],
          query_operator: null,
        },
      ],
      actions: [],
    };
    const automationTypes = {
      message_created: {
        conditions: [{ key: 'private_note', inputType: 'search_select' }],
      },
    };

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], automationTypes, []);

    expect(result.conditions).toEqual([
      {
        attribute_key: 'private_note',
        filter_operator: 'equal_to',
        values: { id: false, name: 'False' },
        query_operator: 'and',
      },
    ]);
  });

  it('rehydrates a current_time (time_range) condition without crashing', () => {
    // Regresión: antes reventaba con "f is not iterable" al editar una regla con
    // la condición de hora, porque sus values son un objeto { from, to }, no una
    // lista, y el código hacía spread [...values].
    const automation = {
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'current_time',
          filter_operator: 'is_between',
          values: { from: '18:30', to: '08:00' },
          query_operator: null,
        },
      ],
      actions: [],
    };
    const automationTypes = {
      message_created: {
        conditions: [{ key: 'current_time', inputType: 'time_range' }],
      },
    };

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], automationTypes, []);

    expect(result.conditions[0].values).toEqual({ from: '18:30', to: '08:00' });
  });

  it('rehydrates a GROUP (parentheses) condition preserving its structure', () => {
    // Al editar una regla guardada con un grupo "A AND (B OR C)", el grupo debe
    // conservar type/child_operator y manifestar cada hija como condición plana,
    // sin reventar al leer condition.attribute_key (que en el grupo es undefined).
    const automation = {
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'private_note',
          filter_operator: 'equal_to',
          values: [true],
          query_operator: 'and',
        },
        {
          type: 'group',
          query_operator: null,
          child_operator: 'or',
          conditions: [
            {
              attribute_key: 'private_note',
              filter_operator: 'equal_to',
              values: [false],
              query_operator: 'or',
            },
            {
              attribute_key: 'private_note',
              filter_operator: 'equal_to',
              values: [true],
              query_operator: null,
            },
          ],
        },
      ],
      actions: [],
    };
    const automationTypes = {
      message_created: {
        conditions: [{ key: 'private_note', inputType: 'search_select' }],
      },
    };

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], automationTypes, []);

    // La condición plana se manifiesta normal.
    expect(result.conditions[0].attribute_key).toBe('private_note');
    // El grupo conserva su estructura.
    const group = result.conditions[1];
    expect(group.type).toBe('group');
    expect(group.child_operator).toBe('or');
    expect(group.conditions).toHaveLength(2);
    // Sus hijas se manifiestan (values resueltos a la opción seleccionada).
    expect(group.conditions[0].values).toEqual({ id: false, name: 'False' });
    expect(group.conditions[1].values).toEqual({ id: true, name: 'True' });
  });

  it('preserves a stored label value even if the dropdown has not loaded', () => {
    // Regresión (regla "Asignar a melany", cuenta 37): una condición de etiquetas
    // con values ["asesor-diferente"]. Si getConditionDropdownValues('labels')
    // devuelve [] (etiquetas aún sin cargar, renombradas o id como texto), el
    // valor NO debe perderse: se preserva como opción sintética { id, name } para
    // que la validación no marque el recuadro de condiciones en rojo sin texto.
    const automation = {
      event_name: 'message_created',
      conditions: [
        {
          attribute_key: 'message_type',
          filter_operator: 'equal_to',
          values: ['incoming'],
          query_operator: 'and',
        },
        {
          attribute_key: 'labels',
          filter_operator: 'not_equal_to',
          values: ['asesor-diferente'],
          query_operator: null,
        },
      ],
      actions: [],
    };
    const automationTypes = {
      message_created: {
        conditions: [
          { key: 'message_type', inputType: 'multi_select' },
          { key: 'labels', inputType: 'multi_select' },
        ],
      },
    };

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], automationTypes, []);

    // El valor de la etiqueta se conserva aunque el dropdown esté vacío.
    expect(result.conditions[1].values).toEqual([
      { id: 'asesor-diferente', name: 'asesor-diferente' },
    ]);
  });

  it('rehydrates last responding agent as a selected action option', () => {
    const automation = {
      event_name: 'conversation_created',
      conditions: [],
      actions: [
        {
          action_name: 'assign_agent',
          action_params: ['last_responding_agent'],
        },
      ],
    };
    const automationActionTypes = [
      { key: 'assign_agent', inputType: 'search_select' },
    ];

    const { formatAutomation } = useEditableAutomation();
    const result = formatAutomation(automation, [], {}, automationActionTypes);

    expect(result.actions).toEqual([
      {
        action_name: 'assign_agent',
        action_params: [
          {
            id: 'last_responding_agent',
            name: 'Last Responding Agent',
          },
        ],
      },
    ]);
  });
});
