const setArrayValues = item => {
  return item.values[0]?.id ? item.values.map(val => val.id) : item.values;
};

const generateValues = item => {
  if (item.attribute_key === 'content') {
    const values = item.values || '';
    return values.split(',');
  }
  // Jabvox: la franja horaria guarda un objeto { from, to }; se preserva tal cual
  // (no es una lista de ids como el resto de condiciones).
  if (item.attribute_key === 'current_time') {
    return item.values || {};
  }
  if (Array.isArray(item.values)) {
    return setArrayValues(item);
  }
  if (typeof item.values === 'object') {
    return [item.values.id];
  }
  if (!item.values) {
    return [];
  }
  return [item.values];
};

// ¿Es un nodo de grupo (paréntesis) { type: 'group', conditions: [...] }?
const isGroup = item => item?.type === 'group';

// Las hijas de un grupo pueden venir en camelCase (la conversión snake_case de nivel
// superior no es profunda). Normalizamos SUS claves aquí para que el backend reciba
// attribute_key / filter_operator / query_operator como en las condiciones planas.
const toSnakeCaseCondition = item => ({
  attribute_key: item.attribute_key ?? item.attributeKey,
  filter_operator: item.filter_operator ?? item.filterOperator,
  query_operator: item.query_operator ?? item.queryOperator,
  values: item.values,
  custom_attribute_type: item.custom_attribute_type ?? item.customAttributeType,
});

// Normaliza una lista de condiciones PLANAS: pasa claves a snake_case, expande
// values y anula el query_operator de la última (si no, sobra un operador).
const normalizeFlatConditions = conditions => {
  const normalized = conditions.map(raw => {
    const item = toSnakeCaseCondition(raw);
    item.values = generateValues(item);
    return item;
  });
  if (normalized.length) {
    normalized[normalized.length - 1].query_operator = undefined;
  }
  return normalized;
};

const generatePayload = data => {
  // Make a copy of data to avoid vue data reactivity issues
  const filters = JSON.parse(JSON.stringify(data));

  const payload = filters.map(item => {
    if (isGroup(item)) {
      // Normaliza el grupo a snake_case (type, operadores) y sus hijas.
      return {
        type: 'group',
        query_operator: item.query_operator ?? item.queryOperator,
        child_operator: item.child_operator ?? item.childOperator,
        conditions: normalizeFlatConditions(item.conditions || []),
      };
    }
    item.values = generateValues(item);
    return item;
  });

  // El query_operator de la última condición/grupo de primer nivel se anula
  // (igual que antes): la API no espera operador tras el último elemento.
  if (payload.length) {
    payload[payload.length - 1].query_operator = undefined;
  }
  return { payload };
};

export default generatePayload;
