// Solo empresa: los campos de contacto se crean desde Personalización y los de
// conversación no se usan. El id es el del enum `attribute_model` del backend
// (company_attribute: 2), que no cambia aunque aquí se ofrezca uno solo.
export const ATTRIBUTE_MODELS = [{ id: 2, key: 'COMPANY' }];

export const ATTRIBUTE_TYPES = [
  { id: 0, key: 'TEXT' },
  { id: 1, key: 'NUMBER' },
  { id: 4, key: 'LINK' },
  { id: 5, key: 'DATE' },
  { id: 6, key: 'LIST' },
  { id: 7, key: 'CHECKBOX' },
];
