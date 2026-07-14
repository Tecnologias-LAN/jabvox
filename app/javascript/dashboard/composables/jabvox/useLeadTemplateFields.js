import { ref, watch, unref } from 'vue';
import leadsAPI from 'dashboard/api/jabvox/leads';

// Builds the field options + resolved values used to auto-fill WhatsApp template
// variables ({{n}}) from a contact's lead, for the 1-to-1 composer. Field keys
// mirror the bulk sender (default fields under plain keys, custom under
// "custom:<key>") so both paths speak the same language.
//
// Usage:
//   const { fieldOptions, fieldValues } = useLeadTemplateFields(contactIdRef);
// Pass a ref or a plain value; it refetches when the contact changes.
export function useLeadTemplateFields(contactIdSource) {
  const fieldOptions = ref([]);
  const fieldValues = ref({});

  const DEFAULT_LABELS = {
    nombre: 'Nombre',
    telefono: 'Teléfono',
    email: 'Correo',
    identificador: 'Identificador',
    country: 'País',
    campaign: 'Campaña',
    afiliado: 'Afiliado',
    assignee_name: 'Asesor asignado',
  };

  const reset = () => {
    fieldOptions.value = [];
    fieldValues.value = {};
  };

  const load = async contactId => {
    if (!contactId) {
      reset();
      return;
    }

    // A single call (agent-accessible) returns both this contact's values and
    // the account's custom-field definitions. We deliberately do NOT use the
    // bulk endpoint here because it is admin-only, which is why non-admin agents
    // previously saw only the default fields in the 1-to-1 composer.
    let values = {};
    let customDefs = [];
    try {
      const { data } = await leadsAPI.forContact(contactId);
      values = data?.fields || {};
      customDefs = data?.custom_field_defs || [];
    } catch {
      values = {};
      customDefs = [];
    }
    fieldValues.value = values;

    // Offer every default field plus EVERY defined custom field, regardless of
    // whether this contact has a value. Fall back to the custom keys present in
    // `values` if the definitions couldn't be loaded.
    const options = [];
    Object.keys(DEFAULT_LABELS).forEach(key => {
      options.push({ value: key, label: DEFAULT_LABELS[key] });
    });

    const seen = new Set();
    const addCustom = (key, label) => {
      const value = `custom:${key}`;
      if (!key || seen.has(value)) return;
      seen.add(value);
      options.push({ value, label: label || key });
    };

    customDefs.forEach(cf => addCustom(cf.key, cf.label));
    Object.keys(values)
      .filter(k => k.startsWith('custom:'))
      .forEach(k => addCustom(k.replace('custom:', '')));

    fieldOptions.value = options;
  };

  watch(
    () => unref(contactIdSource),
    id => load(id),
    { immediate: true }
  );

  return { fieldOptions, fieldValues };
}
