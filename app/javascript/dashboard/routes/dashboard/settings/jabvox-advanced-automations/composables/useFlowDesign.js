// Sistema visual único del módulo: mapea los datos del catálogo (icono, color,
// categoría) y los estados de ejecución a clases Tailwind del tema Jabvox.

// El catálogo ya envía nombres de icono Lucide, así que basta prefijarlos.
export const FALLBACK_ICON = 'i-lucide-box';

export function nodeIcon(definition) {
  const icon = definition?.icon;
  return icon ? `i-lucide-${icon}` : FALLBACK_ICON;
}

// Cada categoría se pinta con una escala Radix del tema, no con hex sueltos:
// así el modo oscuro y los contrastes salen del mismo sitio que el resto.
export const CATEGORY_STYLES = {
  triggers: {
    label: 'Disparadores',
    icon: 'i-lucide-zap',
    chip: 'bg-n-ruby-3 text-n-ruby-11',
    ring: 'ring-n-ruby-8',
    accent: 'text-n-ruby-11',
    dot: 'bg-n-ruby-9',
  },
  logic: {
    label: 'Lógica',
    icon: 'i-lucide-git-branch',
    chip: 'bg-n-violet-3 text-n-violet-11',
    ring: 'ring-n-violet-8',
    accent: 'text-n-violet-11',
    dot: 'bg-n-violet-9',
  },
  jabvox: {
    label: 'Jabvox',
    icon: 'i-lucide-layers',
    chip: 'bg-n-teal-3 text-n-teal-11',
    ring: 'ring-n-teal-8',
    accent: 'text-n-teal-11',
    dot: 'bg-n-teal-9',
  },
  integration: {
    label: 'Integraciones',
    icon: 'i-lucide-globe',
    chip: 'bg-n-amber-3 text-n-amber-11',
    ring: 'ring-n-amber-8',
    accent: 'text-n-amber-11',
    dot: 'bg-n-amber-9',
  },
};

const NEUTRAL_CATEGORY = {
  label: '',
  icon: FALLBACK_ICON,
  chip: 'bg-n-slate-3 text-n-slate-11',
  ring: 'ring-n-slate-8',
  accent: 'text-n-slate-11',
  dot: 'bg-n-slate-9',
};

export function categoryStyle(category) {
  return CATEGORY_STYLES[category] || NEUTRAL_CATEGORY;
}

// Nombre legible de una sección de la paleta: los módulos no están en
// CATEGORY_STYLES, así que se capitaliza su clave.
export function sectionLabel(key) {
  if (CATEGORY_STYLES[key]) return CATEGORY_STYLES[key].label;
  return key.charAt(0).toUpperCase() + key.slice(1);
}

// Estados de una ejecución (flujo o paso), con su color e icono.
export const RUN_STATUS_STYLES = {
  pending: {
    chip: 'bg-n-slate-3 text-n-slate-11',
    icon: 'i-lucide-clock',
    text: 'text-n-slate-11',
  },
  running: {
    chip: 'bg-n-blue-3 text-n-blue-11',
    icon: 'i-lucide-loader-circle',
    text: 'text-n-blue-11',
    spin: true,
  },
  success: {
    chip: 'bg-n-teal-3 text-n-teal-11',
    icon: 'i-lucide-circle-check',
    text: 'text-n-teal-11',
  },
  failed: {
    chip: 'bg-n-ruby-3 text-n-ruby-11',
    icon: 'i-lucide-circle-alert',
    text: 'text-n-ruby-11',
  },
  waiting: {
    chip: 'bg-n-amber-3 text-n-amber-11',
    icon: 'i-lucide-pause',
    text: 'text-n-amber-11',
  },
  skipped: {
    chip: 'bg-n-slate-3 text-n-slate-11',
    icon: 'i-lucide-minus',
    text: 'text-n-slate-11',
  },
};

export function runStatusStyle(status) {
  return RUN_STATUS_STYLES[status] || RUN_STATUS_STYLES.pending;
}

// Estados de un flujo en la lista.
export const FLOW_STATUS_STYLES = {
  draft: { chip: 'bg-n-slate-3 text-n-slate-11', dot: 'bg-n-slate-9' },
  active: { chip: 'bg-n-teal-3 text-n-teal-11', dot: 'bg-n-teal-9' },
  paused: { chip: 'bg-n-amber-3 text-n-amber-11', dot: 'bg-n-amber-9' },
  archived: { chip: 'bg-n-slate-3 text-n-slate-10', dot: 'bg-n-slate-8' },
};

export function flowStatusStyle(status) {
  return FLOW_STATUS_STYLES[status] || FLOW_STATUS_STYLES.draft;
}

// Superficies compartidas: una sola definición para que ninguna pantalla
// invente su propio borde o sombra.
export const SURFACE = {
  card: 'rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm',
  panel: 'border-n-weak bg-n-solid-1',
  sectionTitle: 'text-xs font-semibold uppercase tracking-wide text-n-slate-11',
};

// Duración legible de una ejecución.
export function formatDuration(ms) {
  if (ms === null || ms === undefined) return '—';
  if (ms < 1000) return `${ms} ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)} s`;
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.round((ms % 60000) / 1000);
  return `${minutes} min ${seconds} s`;
}

// Fecha corta y legible; si no se puede interpretar se devuelve tal cual.
export function formatDateTime(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString('es', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}
