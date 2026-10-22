export const DEFAULT_MESSAGE_CREATED_CONDITION = [
  {
    attribute_key: 'message_type',
    filter_operator: 'equal_to',
    values: '',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

export const DEFAULT_CONVERSATION_CONDITION = [
  {
    attribute_key: 'browser_language',
    filter_operator: 'equal_to',
    values: '',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

export const DEFAULT_OTHER_CONDITION = [
  {
    attribute_key: 'status',
    filter_operator: 'equal_to',
    values: '',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

export const DEFAULT_ACTIONS = [
  {
    action_name: 'assign_agent',
    action_params: [],
  },
];

export const MESSAGE_CONDITION_VALUES = [
  {
    id: 'incoming',
    name: 'Incoming',
    i18nKey: 'INCOMING',
  },
  {
    id: 'outgoing',
    name: 'Outgoing',
    i18nKey: 'OUTGOING',
  },
];

// Jabvox: tipo de contenido del mensaje para la condición attachment_type.
// 'text' = mensaje sin adjuntos; el resto son file_type del modelo Attachment.
export const ATTACHMENT_TYPE_CONDITION_VALUES = [
  { id: 'text', name: 'Text', i18nKey: 'TEXT' },
  { id: 'image', name: 'Image', i18nKey: 'IMAGE' },
  { id: 'audio', name: 'Audio', i18nKey: 'AUDIO' },
  { id: 'video', name: 'Video', i18nKey: 'VIDEO' },
  { id: 'file', name: 'File', i18nKey: 'FILE' },
];

export const PRIORITY_CONDITION_VALUES = [
  {
    id: 'nil',
    name: 'None',
    i18nKey: 'NONE',
  },
  {
    id: 'low',
    name: 'Low',
    i18nKey: 'LOW',
  },
  {
    id: 'medium',
    name: 'Medium',
    i18nKey: 'MEDIUM',
  },
  {
    id: 'high',
    name: 'High',
    i18nKey: 'HIGH',
  },
  {
    id: 'urgent',
    name: 'Urgent',
    i18nKey: 'URGENT',
  },
];
