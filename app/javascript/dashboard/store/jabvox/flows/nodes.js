import { defineStore } from 'pinia';
import { computed, ref } from 'vue';
import { nodesAPI } from 'dashboard/api/jabvox/flows';

// Color de cada categoría en la paleta. El color real del nodo manda desde el
// catálogo del backend (`def.color`); aquí solo se pintan los agrupadores.
export const CATEGORY_META = [
  { key: 'triggers', label: 'Disparadores', color: '#db2777' },
  { key: 'logic', label: 'Lógica', color: '#7c3aed' },
  { key: 'jabvox', label: 'Jabvox', color: '#186d6a' },
  { key: 'integration', label: 'Integraciones', color: '#0891b2' },
];

// Orden de las secciones de la paleta: es decisión de producto (se empieza por
// disparadores y lógica), no el orden en que el backend enumere los nodos.
export const PALETTE_ORDER = Object.freeze([
  'triggers',
  'logic',
  'jabvox',
  'leads',
  'contactos',
  'conversaciones',
  'tareas',
  'kanban',
  'calendario',
  'email',
  'whatsapp',
  'sms',
  'tipificaciones',
  'etiquetas',
  'campanas',
  'ordenes',
  'estados',
  'integration',
]);

// Sinónimos de búsqueda: buscar "cliente" debe traer los nodos de Leads aunque
// su etiqueta no lleve esa palabra.
const SEARCH_SYNONYMS = {
  leads: [
    'lead',
    'leads',
    'cliente',
    'clientes',
    'prospecto',
    'oportunidad',
    'negocio',
  ],
  contactos: [
    'contacto',
    'contactos',
    'contact',
    'persona',
    'telefono',
    'celular',
  ],
  conversaciones: [
    'conversacion',
    'conversaciones',
    'chat',
    'mensaje',
    'mensajes',
    'ticket',
  ],
  tareas: ['tarea', 'tareas', 'task', 'pendiente', 'recordatorio', 'todo'],
  kanban: [
    'kanban',
    'tablero',
    'embudo',
    'funnel',
    'etapa',
    'etapas',
    'pipeline',
  ],
  calendario: [
    'calendario',
    'cita',
    'citas',
    'evento',
    'eventos',
    'agenda',
    'reunion',
  ],
  email: ['email', 'correo', 'mail', 'e-mail'],
  whatsapp: ['whatsapp', 'wa', 'wsp', 'plantilla', 'template'],
  sms: ['sms', 'texto', 'mensaje de texto'],
  tipificaciones: [
    'tipificacion',
    'tipificaciones',
    'disposicion',
    'resultado',
    'motivo',
  ],
  etiquetas: ['etiqueta', 'etiquetas', 'label', 'labels', 'tag', 'tags'],
  campanas: ['campana', 'campanas', 'campaign', 'difusion', 'masivo'],
  ordenes: [
    'orden',
    'ordenes',
    'pedido',
    'pedidos',
    'venta',
    'ventas',
    'producto',
  ],
  estados: ['estado', 'estados', 'status'],
  triggers: [
    'disparador',
    'disparadores',
    'trigger',
    'inicio',
    'cuando',
    'evento',
  ],
  logic: [
    'logica',
    'logic',
    'condicion',
    'si',
    'if',
    'bucle',
    'loop',
    'esperar',
    'variable',
  ],
  integration: [
    'integracion',
    'integraciones',
    'webhook',
    'http',
    'api',
    'externo',
  ],
};

// Quita acentos y pasa a minúsculas: "campana" debe encontrar "Campaña".
export function normalizeSearch(text) {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

// Texto contra el que se busca un nodo, ya normalizado y sin acentos.
export function searchIndexOf(def) {
  const parts = [def.label, def.description, def.type];
  if (def.module)
    parts.push(def.module, ...(SEARCH_SYNONYMS[def.module] ?? []));
  parts.push(...(SEARCH_SYNONYMS[def.category] ?? []));
  // Sinónimos declarados por el propio catálogo, si algún día los envía.
  if (Array.isArray(def.keywords)) parts.push(...def.keywords);
  return normalizeSearch(parts.filter(Boolean).join(' '));
}

export const useNodesStore = defineStore('jabvoxFlowNodes', () => {
  const definitions = ref([]);
  const loading = ref(false);
  const loaded = ref(false);
  const error = ref(null);
  // Módulos habilitados; [] = todos. El catálogo ya llega filtrado del servidor.
  const enabledModules = ref([]);
  // Tipos que el backend filtró por módulo no habilitado (diagnóstico).
  const hiddenByModule = ref([]);

  // Índice tipo → definición para búsquedas directas.
  const byType = computed(() => {
    const map = {};
    definitions.value.forEach(def => {
      map[def.type] = def;
    });
    return map;
  });

  // Definiciones agrupadas por categoría, en el orden de CATEGORY_META.
  const byCategory = computed(() => {
    return CATEGORY_META.map(meta => ({
      meta,
      items: definitions.value.filter(d => d.category === meta.key),
    })).filter(g => g.items.length > 0);
  });

  function getDefinition(type) {
    return byType.value[type];
  }

  function categoryColor(cat) {
    return CATEGORY_META.find(c => c.key === cat)?.color ?? '#64748b';
  }

  async function load(force = false) {
    if (loaded.value && !force) return;
    loading.value = true;
    error.value = null;
    try {
      const { data } = await nodesAPI.catalog();
      definitions.value = data.nodes || [];
      enabledModules.value = data.enabledModules || [];
      hiddenByModule.value = data.hiddenByModule || [];
      loaded.value = true;
    } catch (e) {
      error.value = e?.response?.data?.error || e.message;
    } finally {
      loading.value = false;
    }
  }

  // Solo se usa para EXPLICAR por qué falta un nodo: filtrar es del servidor.
  function isModuleEnabled(module) {
    if (!module) return true;
    if (enabledModules.value.length === 0) return true;
    return enabledModules.value.includes(module);
  }

  // Módulos que la cuenta no tiene, deducidos de los tipos filtrados.
  const missingModules = computed(() => {
    if (hiddenByModule.value.length === 0) return [];
    // El tipo es `jabvox.<recurso>.<accion>`: el recurso basta para nombrarlo.
    const known = new Set(enabledModules.value);
    if (known.size === 0) return [];
    return Object.keys(SEARCH_SYNONYMS)
      .filter(
        mod =>
          !known.has(mod) && hiddenByModule.value.some(t => t.includes(mod))
      )
      .sort((a, b) => a.localeCompare(b, 'es'));
  });

  return {
    definitions,
    loading,
    loaded,
    error,
    enabledModules,
    hiddenByModule,
    missingModules,
    isModuleEnabled,
    byType,
    byCategory,
    getDefinition,
    categoryColor,
    load,
  };
});
