import { ref, watch, unref } from 'vue';
import leadsAPI from 'dashboard/api/jabvox/leads';
import bulkWhatsappAPI from 'dashboard/api/jabvox/bulkWhatsapp';

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
    try {
      // Values for THIS contact/lead (default + custom, already flattened).
      const { data } = await leadsAPI.forContact(contactId);
      const values = data?.fields || {};
      fieldValues.value = values;

      // Labels for custom fields come from the account's field definitions.
      let customDefs = [];
      try {
        const res = await bulkWhatsappAPI.getLeadFields();
        customDefs = res?.data?.custom || [];
      } catch {
        customDefs = [];
      }
      // Offer every default field plus EVERY custom field defined for the
      // account (from customDefs), regardless of whether this contact has a
      // value — the user must be able to pick any field. Fall back to the
      // custom keys present in `values` if the definitions couldn't be loaded.
      const options = [];
      Object.keys(DEFAULT_LABELS).forEach(key => {
        options.push({ value: key, label: DEFAULT_LABELS[key] });
      });

      const seen = new Set();
      const addCustom = (key, label) => {
        const value = `custom:${key}`;
        if (seen.has(value)) return;
        seen.add(value);
        options.push({ value, label: label || key });
      };

      customDefs.forEach(cf => addCustom(cf.key, cf.label));
      // Any custom value the contact has that wasn't in the definitions.
      Object.keys(values)
        .filter(k => k.startsWith('custom:'))
        .forEach(k => addCustom(k.replace('custom:', '')));

      fieldOptions.value = options;
    } catch {
      reset();
    }
  };

  watch(
    () => unref(contactIdSource),
    id => load(id),
    { immediate: true }
  );

  return { fieldOptions, fieldValues };
}
