/**
 * Single declarative source of truth for the analytics reports panel.
 *
 * Adding a metric = adding one entry here (mirroring the backend
 * Jabvox::Reports::MetricRegistry). Everything — the KPI cards and the
 * drill-down table columns/formatters — is generic over this list, so no new
 * screen or component is needed per metric.
 *
 * Each metric declares:
 *   key       stable id used in the URL and the API
 *   label     card/heading label
 *   icon      lucide icon class
 *   accent    tailwind text token for the card icon
 *   columns   drill-down table columns: { key, label, type, sortable? }
 *
 * Column `type` drives the cell renderer in ReportTable:
 *   lead | datetime | text | status | money | duration | direction | badge
 */

// Shared leading column: the "lead visual" (name + avatar + channel) every
// drill-down opens with.
const LEAD_COLUMN = { key: 'lead', label: 'Lead', type: 'lead' };
const DATE_COLUMN = {
  key: 'created_at',
  label: 'Fecha',
  type: 'datetime',
  sortable: true,
};
const AGENT_COLUMN = { key: 'agent_name', label: 'Agente', type: 'text' };
const LINK_COLUMN = { key: 'conversation_url', label: '', type: 'link' };

export const REPORT_METRICS = [
  {
    key: 'messages_sent',
    label: 'Mensajes con éxito',
    icon: 'i-lucide-send',
    accent: 'text-n-teal-9',
    columns: [
      DATE_COLUMN,
      LEAD_COLUMN,
      { key: 'inbox_name', label: 'Bandeja', type: 'text' },
      AGENT_COLUMN,
      {
        key: 'content',
        label: 'Mensaje',
        type: 'text-expand',
        full: 'content_full',
      },
      { key: 'status', label: 'Estado', type: 'status' },
      LINK_COLUMN,
    ],
  },
  {
    key: 'messages_failed',
    label: 'Mensajes fallidos',
    icon: 'i-lucide-triangle-alert',
    accent: 'text-n-ruby-9',
    columns: [
      DATE_COLUMN,
      LEAD_COLUMN,
      { key: 'inbox_name', label: 'Bandeja', type: 'text' },
      AGENT_COLUMN,
      {
        key: 'content',
        label: 'Mensaje',
        type: 'text-expand',
        full: 'content_full',
      },
      { key: 'error_reason', label: 'Motivo del error', type: 'text' },
      LINK_COLUMN,
    ],
  },
  {
    key: 'private_notes',
    label: 'Notas privadas',
    icon: 'i-lucide-sticky-note',
    accent: 'text-n-amber-9',
    columns: [
      DATE_COLUMN,
      LEAD_COLUMN,
      { key: 'agent_name', label: 'Autor', type: 'text' },
      {
        key: 'content',
        label: 'Nota',
        type: 'text-expand',
        full: 'content_full',
      },
      LINK_COLUMN,
    ],
  },
  {
    key: 'managements',
    label: 'Gestiones',
    icon: 'i-lucide-clipboard-check',
    accent: 'text-n-blue-9',
    columns: [
      DATE_COLUMN,
      LEAD_COLUMN,
      AGENT_COLUMN,
      { key: 'management_type', label: 'Tipo de gestión', type: 'badge' },
      {
        key: 'result',
        label: 'Resultado',
        type: 'text-expand',
        full: 'result_full',
      },
      LINK_COLUMN,
    ],
  },
  {
    key: 'orders',
    label: 'Pedidos',
    icon: 'i-lucide-shopping-cart',
    accent: 'text-n-green-9',
    columns: [
      DATE_COLUMN,
      LEAD_COLUMN,
      AGENT_COLUMN,
      { key: 'order_ref', label: 'Pedido', type: 'text' },
      { key: 'amount', label: 'Monto', type: 'money' },
      { key: 'status', label: 'Estado', type: 'badge' },
      LINK_COLUMN,
    ],
  },
  {
    key: 'calls',
    label: 'Llamadas',
    icon: 'i-lucide-phone',
    accent: 'text-n-indigo-9',
    columns: [
      DATE_COLUMN,
      LEAD_COLUMN,
      AGENT_COLUMN,
      { key: 'direction', label: 'Dirección', type: 'direction' },
      { key: 'duration', label: 'Duración', type: 'duration' },
      { key: 'result', label: 'Resultado', type: 'badge' },
    ],
  },
  {
    key: 'resolved',
    label: 'Conversaciones resueltas',
    icon: 'i-lucide-circle-check-big',
    accent: 'text-n-teal-9',
    columns: [
      {
        key: 'created_at',
        label: 'Resuelta',
        type: 'datetime',
        sortable: true,
      },
      LEAD_COLUMN,
      { key: 'agent_name', label: 'Resuelta por', type: 'text' },
      {
        key: 'resolution_seconds',
        label: 'Tiempo de resolución',
        type: 'duration',
      },
      LINK_COLUMN,
    ],
  },
  {
    key: 'conversations',
    label: 'Conversaciones',
    icon: 'i-lucide-messages-square',
    accent: 'text-n-blue-9',
    columns: [
      {
        key: 'created_at',
        label: 'Última actividad',
        type: 'datetime',
        sortable: true,
      },
      LEAD_COLUMN,
      { key: 'agent_name', label: 'Asignado', type: 'text' },
      { key: 'status', label: 'Estado', type: 'badge' },
      LINK_COLUMN,
    ],
  },
  {
    key: 'labels_added',
    label: 'Etiquetas puestas',
    icon: 'i-lucide-tag',
    accent: 'text-n-purple-9',
    columns: [
      DATE_COLUMN,
      LEAD_COLUMN,
      { key: 'label', label: 'Etiqueta', type: 'badge' },
      LINK_COLUMN,
    ],
  },
  {
    key: 'labels_removed',
    label: 'Etiquetas quitadas',
    icon: 'i-lucide-tag',
    accent: 'text-n-slate-9',
    columns: [
      DATE_COLUMN,
      LEAD_COLUMN,
      { key: 'label', label: 'Etiqueta', type: 'badge' },
      LINK_COLUMN,
    ],
  },
];

export const METRIC_BY_KEY = REPORT_METRICS.reduce((acc, m) => {
  acc[m.key] = m;
  return acc;
}, {});

export const PAGE_SIZES = [25, 50, 100];
