import filterQueryGenerator from '../filterQueryGenerator';

const testData = [
  {
    attribute_key: 'status',
    filter_operator: 'equal_to',
    values: [
      { id: 'pending', name: 'Pending' },
      { id: 'resolved', name: 'Resolved' },
    ],
    query_operator: 'and',
  },
  {
    attribute_key: 'assignee',
    filter_operator: 'equal_to',
    values: {
      id: 3,
      account_id: 1,
      auto_offline: true,
      confirmed: true,
      email: 'fayaz@test.com',
      available_name: 'Fayaz',
      name: 'Fayaz',
      role: 'agent',
      thumbnail:
        'https://www.gravatar.com/avatar/a35bf18a632f734c8d0c883dcc9fa0ef?d=404',
    },
    query_operator: 'and',
  },
  {
    attribute_key: 'id',
    filter_operator: 'equal_to',
    values: 'This is a test',
    query_operator: 'or',
  },
];

const finalResult = {
  payload: [
    {
      attribute_key: 'status',
      filter_operator: 'equal_to',
      values: ['pending', 'resolved'],
      query_operator: 'and',
    },
    {
      attribute_key: 'assignee',
      filter_operator: 'equal_to',
      values: [3],
      query_operator: 'and',
    },
    {
      attribute_key: 'id',
      filter_operator: 'equal_to',
      values: ['This is a test'],
    },
  ],
};

describe('#filterQueryGenerator', () => {
  it('returns the correct format of filter query', () => {
    expect(filterQueryGenerator(testData)).toMatchObject(finalResult);
    expect(
      filterQueryGenerator(testData).payload.every(i => Array.isArray(i.values))
    ).toBe(true);
  });

  it('serializes a selected contact object to contact id', () => {
    const result = filterQueryGenerator([
      {
        attribute_key: 'contact_id',
        filter_operator: 'equal_to',
        values: { id: 123, name: 'Jane Doe' },
        query_operator: 'and',
      },
    ]);

    expect(result).toMatchObject({
      payload: [
        {
          attribute_key: 'contact_id',
          filter_operator: 'equal_to',
          values: [123],
        },
      ],
    });
  });

  it('serializes a GROUP with camelCase child keys to snake_case', () => {
    const result = filterQueryGenerator([
      {
        attribute_key: 'status',
        filter_operator: 'equal_to',
        values: [{ id: 'open', name: 'Open' }],
        query_operator: 'and',
      },
      {
        type: 'group',
        queryOperator: 'and',
        childOperator: 'or',
        conditions: [
          {
            attributeKey: 'labels',
            filterOperator: 'equal_to',
            values: [{ id: 'vip', name: 'vip' }],
            queryOperator: 'or',
          },
          {
            attributeKey: 'labels',
            filterOperator: 'equal_to',
            values: [{ id: 'premium', name: 'premium' }],
            queryOperator: 'or',
          },
        ],
      },
    ]);

    expect(result).toMatchObject({
      payload: [
        {
          attribute_key: 'status',
          filter_operator: 'equal_to',
          values: ['open'],
          query_operator: 'and',
        },
        {
          type: 'group',
          child_operator: 'or',
          conditions: [
            {
              attribute_key: 'labels',
              filter_operator: 'equal_to',
              values: ['vip'],
              query_operator: 'or',
            },
            {
              attribute_key: 'labels',
              filter_operator: 'equal_to',
              values: ['premium'],
            },
          ],
        },
      ],
    });

    // La última condición del grupo y el último elemento raíz no llevan operador.
    const group = result.payload[1];
    expect(
      group.conditions[group.conditions.length - 1].query_operator
    ).toBeUndefined();
    expect(
      result.payload[result.payload.length - 1].query_operator
    ).toBeUndefined();
  });
});
