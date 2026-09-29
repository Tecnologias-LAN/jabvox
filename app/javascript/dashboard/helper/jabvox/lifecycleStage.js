// Colores de la etapa del ciclo de vida de un contacto.
//
// Vive aparte porque la misma pastilla se pinta en la tabla de contactos y en el detalle
// del Kanban: tenerlo en un solo sitio evita que una pantalla muestre un color y la otra
// otro para el mismo estado.
//
// Las claves son las de JabvoxContactLifecycle::LIFECYCLE_STAGES.
export const STAGE_STYLES = {
  prospecto: 'bg-n-slate-3 text-n-slate-11 border-n-slate-6',
  interesado: 'bg-n-amber-3 text-n-amber-11 border-n-amber-6',
  cliente: 'bg-n-teal-3 text-n-teal-11 border-n-teal-6',
  // Rojo: inactivo es el único estado que señala un problema, y en gris se confundía
  // con "prospecto" —que es el punto de partida normal— justo cuando hay que notarlo.
  inactivo: 'bg-n-ruby-3 text-n-ruby-11 border-n-ruby-6',
};

export const stageClass = stage =>
  STAGE_STYLES[stage] || STAGE_STYLES.prospecto;

// Un contacto sin etapa se trata como prospecto: es el estado inicial.
export const stageOf = (contact, extras = {}) =>
  extras.lifecycle_stage || contact?.lifecycle_stage || 'prospecto';
