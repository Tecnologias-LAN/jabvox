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
      const customLabelByKey = {};
      customDefs.forEach(cf => {
        customLabelByKey[`custom:${cf.key}`] = cf.label || cf.key;
      });

      // Only offer fields that actually have a value for this contact, plus the
      // known default fields (even if empty) so the user can still pick them.
      const options = [];
      Object.keys(DEFAULT_LABELS).forEach(key => {
        options.push({ value: key, label: DEFAULT_LABELS[key] });
      });
      Object.keys(values)
        .filter(k => k.startsWith('custom:'))
        .forEach(k => {
          options.push({
            value: k,
            label: customLabelByKey[k] || k.replace('custom:', ''),
          });
        });
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
