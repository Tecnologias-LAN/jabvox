<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useNodesStore,
  PALETTE_ORDER,
  normalizeSearch,
  searchIndexOf,
} from 'dashboard/store/jabvox/flows/nodes';
import {
  nodeIcon,
  categoryStyle,
  sectionLabel,
} from '../composables/useFlowDesign';

// Paleta de pasos. Agrupa por categoría/módulo en el orden de producto y busca
// por sinónimos, para que "cliente" encuentre los pasos de Leads.
const emit = defineEmits(['add']);

const { t } = useI18n();
const nodesStore = useNodesStore();
const query = ref('');
const collapsed = ref({});

// Los nodos ocultos son legacy: siguen en el catálogo para que los flujos
// guardados se rendericen, pero no se ofrecen para añadir.
const available = computed(() =>
  nodesStore.definitions.filter(def => !def.hidden)
);

const filtered = computed(() => {
  const term = normalizeSearch(query.value.trim());
  if (!term) return available.value;
  return available.value.filter(def => searchIndexOf(def).includes(term));
});

// Clave de sección: el módulo dentro de `jabvox`, o la categoría.
function sectionOf(def) {
  return def.category === 'jabvox' && def.module ? def.module : def.category;
}

const sections = computed(() => {
  const groups = {};
  filtered.value.forEach(def => {
    const key = sectionOf(def);
    (groups[key] = groups[key] || []).push(def);
  });
  const known = PALETTE_ORDER.filter(key => groups[key]);
  const rest = Object.keys(groups)
    .filter(key => !PALETTE_ORDER.includes(key))
    .sort();
  return [...known, ...rest].map(key => ({
    key,
    label: sectionLabel(key),
    items: groups[key],
    style: categoryStyle(groups[key][0].category),
  }));
});

// Buscando, todo se muestra abierto: colapsar escondería los resultados.
function isOpen(key) {
  if (query.value.trim()) return true;
  return collapsed.value[key] !== true;
}

function toggle(key) {
  collapsed.value = { ...collapsed.value, [key]: isOpen(key) };
}

function onDragStart(event, def) {
  event.dataTransfer.setData('application/jabvox-flow-node', def.type);
  event.dataTransfer.effectAllowed = 'move';
}
</script>

<template>
  <aside
    class="flex w-[272px] shrink-0 flex-col border-r border-n-weak bg-n-solid-1"
  >
    <div class="border-b border-n-weak p-3">
      <div class="relative">
        <span
          class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
        />
        <input
          v-model="query"
          type="search"
          class="!mb-0 block h-9 w-full rounded-lg border-0 bg-n-alpha-black2 !py-2 !pl-9 !pr-3 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-all placeholder:text-n-slate-10 hover:outline-n-slate-6 focus:outline-n-brand"
          :placeholder="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.PALETTE_SEARCH')"
        />
      </div>
      <p class="mt-2 flex items-center gap-1.5 text-xs text-n-slate-11">
        <span class="i-lucide-mouse-pointer-click size-3.5 shrink-0" />
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.ADD_HINT') }}
      </p>
    </div>

    <div class="min-h-0 flex-1 overflow-y-auto p-2">
      <div
        v-if="nodesStore.loading"
        class="flex flex-col gap-2 p-1"
        aria-hidden="true"
      >
        <div
          v-for="i in 6"
          :key="i"
          class="h-10 animate-pulse rounded-lg bg-n-alpha-2"
        />
      </div>

      <div
        v-else-if="!sections.length"
        class="flex flex-col items-center gap-2 px-4 py-10 text-center"
      >
        <span class="i-lucide-search-x size-7 text-n-slate-10" />
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.PALETTE_EMPTY') }}
        </p>
      </div>

      <section v-for="section in sections" :key="section.key" class="mb-1">
        <button
          type="button"
          class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left transition-colors hover:bg-n-alpha-2"
          @click="toggle(section.key)"
        >
          <span
            class="i-lucide-chevron-right size-3.5 shrink-0 text-n-slate-10 transition-transform"
            :class="{ 'rotate-90': isOpen(section.key) }"
          />
          <span
            class="size-1.5 shrink-0 rounded-full"
            :class="section.style.dot"
          />
          <span
            class="min-w-0 flex-1 truncate text-xs font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ section.label }}
          </span>
          <span class="text-[10px] tabular-nums text-n-slate-10">
            {{ section.items.length }}
          </span>
        </button>

        <div v-if="isOpen(section.key)" class="mt-0.5 flex flex-col gap-0.5">
          <button
            v-for="def in section.items"
            :key="def.type"
            type="button"
            draggable="true"
            class="flex w-full cursor-grab items-center gap-2.5 rounded-lg px-2 py-1.5 text-left transition-colors hover:bg-n-alpha-2 active:cursor-grabbing"
            :title="def.description"
            @dragstart="onDragStart($event, def)"
            @click="emit('add', def.type)"
          >
            <span
              class="flex size-7 shrink-0 items-center justify-center rounded-md text-white"
              :style="{ backgroundColor: def.color }"
            >
              <span :class="nodeIcon(def)" class="size-4" />
            </span>
            <span class="min-w-0 flex-1 truncate text-sm text-n-slate-12">
              {{ def.label }}
            </span>
          </button>
        </div>
      </section>
    </div>
  </aside>
</template>
