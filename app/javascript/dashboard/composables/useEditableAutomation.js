import useAutomationValues from './useAutomationValues';

import {
  getCustomAttributeInputType,
  filterCustomAttributes,
  getStandardAttributeInputType,
  isCustomAttribute,
} from 'dashboard/helper/automationHelper';

export function useEditableAutomation() {
  const { getConditionDropdownValues, getActionDropdownValues } =
    useAutomationValues();

  // Da formato a una condición plana (resuelve inputType y normaliza values) para
  // mostrarla en el modal de edición. Extraído para reutilizarlo en las hijas de
  // un grupo.
  const manifestFlatCondition = (
    condition,
    customAttributes,
    automation,
    automationTypes
  ) => {
    const customAttr = isCustomAttribute(
      customAttributes,
      condition.attribute_key
    );
    let inputType = 'plain_text';
    if (customAttr) {
      inputType = getCustomAttributeInputType(customAttr.type);
    } else {
      inputType = getStandardAttributeInputType(
        automationTypes,
        automation.event_name,
        condition.attribute_key
      );
    }
    if (inputType === 'plain_text' || inputType === 'date') {
      return { ...condition, values: condition.values[0] };
    }
    if (inputType === 'comma_separated_plain_text') {
      return { ...condition, values: condition.values.join(',') };
    }
    if (inputType === 'time_range') {
      // La franja horaria guarda un objeto { from, to }, no una lista. Se
      // preserva tal cual: hacer spread de un objeto ([...values]) revienta con
      // "f is not iterable" al editar una regla que la usa.
      return { ...condition, values: condition.values };
    }
    const dropdownValues = getConditionDropdownValues(condition.attribute_key);
    const hasBooleanOptions =
      inputType === 'search_select' &&
      dropdownValues.length &&
      dropdownValues.every(item => typeof item.id === 'boolean');

    if (hasBooleanOptions) {
      return {
        ...condition,
        query_operator: condition.query_operator || 'and',
        values: dropdownValues.find(item => item.id === condition.values[0]),
      };
    }
    // Reconstruye los valores guardados a partir del dropdown. Si un valor
    // guardado no está en el dropdown (etiqueta renombrada/borrada, opciones aún
    // sin cargar, o id guardado como texto), NO se descarta: se preserva como
    // opción sintética { id, name }. Sin esto, el valor quedaba vacío al editar y
    // la validación marcaba el recuadro de condiciones en rojo sin texto visible.
    const storedValues = [...(condition.values || [])];
    const matched = [...dropdownValues].filter(item =>
      storedValues.includes(item.id)
    );
    const matchedIds = matched.map(item => item.id);
    const missing = storedValues
      .filter(id => !matchedIds.includes(id))
      .map(id => ({ id, name: String(id) }));
    return {
      ...condition,
      query_operator: condition.query_operator || 'and',
      values: [...matched, ...missing],
    };
  };

  /**
   * This function sets the conditions for automation.
   * It help to format the conditions for the automation when we open the edit automation modal.
   * Soporta GRUPOS (paréntesis): un grupo conserva su estructura y sus hijas se
   * manifiestan una a una como condiciones planas.
   * @param {Object} automation - The automation object containing conditions to manifest.
   * @param {Array} allCustomAttributes - List of all custom attributes.
   * @param {Object} automationTypes - Object containing automation type definitions.
   * @returns {Array} An array of manifested conditions.
   */
  const manifestConditions = (
    automation,
    allCustomAttributes,
    automationTypes
  ) => {
    const customAttributes = filterCustomAttributes(allCustomAttributes);

    const manifestOne = condition =>
      manifestFlatCondition(
        condition,
        customAttributes,
        automation,
        automationTypes
      );

    return automation.conditions.map(condition => {
      // Un GRUPO (paréntesis) conserva su estructura; manifestamos sus hijas.
      if (condition?.type === 'group') {
        return {
          ...condition,
          query_operator: condition.query_operator || 'and',
          child_operator: condition.child_operator || 'or',
          conditions: (condition.conditions || []).map(manifestOne),
        };
      }
      return manifestOne(condition);
    });
  };

  /**
   * Generates an array of actions for the automation.
   * @param {Object} action - The action object.
   * @param {Array} automationActionTypes - List of available automation action types.
   * @returns {Array|Object} Generated actions array or object based on input type.
   */
  const generateActionsArray = (action, automationActionTypes) => {
    const params = action.action_params;
    // Guarda: una acción guardada podría no estar en la lista (módulo desactivado).
    // Sin esto, `.inputType` sobre undefined rompe la edición de la regla.
    const actionType = automationActionTypes.find(
      item => item.key === action.action_name
    );
    const inputType = actionType?.inputType;
    if (inputType === 'multi_select' || inputType === 'search_select') {
      return [...getActionDropdownValues(action.action_name)].filter(item =>
        [...params].includes(item.id)
      );
    }
    if (inputType === 'team_message') {
      return {
        team_ids: [...getActionDropdownValues(action.action_name)].filter(
          item => [...params[0].team_ids].includes(item.id)
        ),
        message: params[0].message,
      };
    }
    return [...params];
  };

  /**
   * This function sets the actions for automation.
   * It help to format the actions for the automation when we open the edit automation modal.
   * @param {Object} automation - The automation object containing actions.
   * @param {Array} automationActionTypes - List of available automation action types.
   * @returns {Array} An array of manifested actions.
   */
  const manifestActions = (automation, automationActionTypes) => {
    return automation.actions.map(action => ({
      ...action,
      action_params: action.action_params.length
        ? generateActionsArray(action, automationActionTypes)
        : [],
    }));
  };

  /**
   * Formats the automation object for use when we edit the automation.
   * It help to format the conditions and actions for the automation when we open the edit automation modal.
   * @param {Object} automation - The automation object to format.
   * @param {Array} allCustomAttributes - List of all custom attributes.
   * @param {Object} automationTypes - Object containing automation type definitions.
   * @param {Array} automationActionTypes - List of available automation action types.
   * @returns {Object} A new object with formatted automation data, including automation conditions and actions.
   */
  const formatAutomation = (
    automation,
    allCustomAttributes,
    automationTypes,
    automationActionTypes
  ) => {
    return {
      ...automation,
      conditions: manifestConditions(
        automation,
        allCustomAttributes,
        automationTypes
      ),
      actions: manifestActions(automation, automationActionTypes),
    };
  };

  return { formatAutomation };
}
