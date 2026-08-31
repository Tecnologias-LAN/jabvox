<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useNodesStore } from 'dashboard/store/jabvox/flows/nodes';
import InputPanel from './InputPanel.vue';
import OutputPanel from './OutputPanel.vue';
import NodeConfigPanel from './NodeConfigPanel.vue';
import { nodeIcon } from '../composables/useFlowDesign';
import { provideFieldDrag } from '../composables/useFieldDrag';

// VISTA DE DETALLE de un paso, casi a pantalla completa y en tres columnas:
// ENTRADA | CONFIGURACIÓN | SALIDA. Se abre con doble clic sobre un paso.
const props = defineProps({
  node: { type: Object, required: true },
  previous: { type: Array, default: () => [] },
  directPrevious: { type: String, default: null },
  outputFor: { type: Function, required: true },
  loopNode: { type: Object, default: null },
  testResult: { type: Object, default: null },
  testing: { type: Boolean, default: false },
  // Pasos vecinos para navegar sin cerrar la vista.
  prevNode: { type: Object, default: null },
  nextNode: { type: Object, default: null },
});

const emit = defineEmits([
  'close',
  'navigate',
  'updateParams',
  'test',
  'runFrom',
  'delete',
  'runPrevious',
]);

const { t } = useI18n();
const nodesStore = useNodesStore();

// El estado del arrastre vive aquí y lo comparten los tres paneles: es lo que
// permite que arrastrar desde la ENTRADA resalte los params de la CONFIGURACIÓN.
const fieldDrag = provideFieldDrag();

const definition = computed(() =>
  nodesStore.getDefinition(props.node.data.nodeType)
);
const title = computed(
  () => props.node.data?.label || definition.value?.label || props.node.id
);
const icon = computed(() => nodeIcon(definition.value));
const accent = computed(() => definition.value?.color || '#64748b');

// Tres columnas en una pantalla estrecha dejan los datos ilegibles: por debajo
// del umbral se pasa a pestañas.
const COMPACT_BREAKPOINT = 1100;
const compact = ref(false);
const activeTab = ref('config');
const inputCollapsed = ref(false);
const outputCollapsed = ref(false);

function measure() {
  compact.value = window.innerWidth < COMPACT_BREAKPOINT;
}

// Anchos de las columnas laterales, en porcentaje.
const MIN_SIDE = 15;
const MAX_SIDE = 45;
const inputWidth = ref(27);
const outputWidth = ref(27);

const inputPct = computed(() => (inputCollapsed.value ? 0 : inputWidth.value));
const outputPct = computed(() =>
  outputCollapsed.value ? 0 : outputWidth.value
);
const configPct = computed(() => 100 - inputPct.value - outputPct.value);

const root = ref(null);
const dragging = ref(null);

function clamp(value) {
  return Math.min(MAX_SIDE, Math.max(MIN_SIDE, value));
}

function onDrag(event) {
  const container = root.value;
  if (!container || !dragging.value) return;
  const rect = container.getBoundingClientRect();
  if (rect.width === 0) return;
  const pct = ((event.clientX - rect.left) / rect.width) * 100;
  // El separador derecho se mide desde el borde derecho del contenedor.
  if (dragging.value === 'input') inputWidth.value = clamp(pct);
  else outputWidth.value = clamp(100 - pct);
}

function endDrag() {
  dragging.value = null;
  window.removeEventListener('pointermove', onDrag);
  window.removeEventListener('pointerup', endDrag);
}

function startDrag(which, event) {
  event.preventDefault();
  dragging.value = which;
  window.addEventListener('pointermove', onDrag);
  window.addEventListener('pointerup', endDrag);
}

function nudge(which, delta) {
  if (which === 'input') inputWidth.value = clamp(inputWidth.value + delta);
  else outputWidth.value = clamp(outputWidth.value + delta);
}

// Insertar sin arrastrar: en pestañas hay que saltar a Configuración, que es
// donde el campo se va a poder colocar.
function onInsertField(field) {
  fieldDrag.requestInsert(field);
  if (compact.value) activeTab.value = 'config';
}

const draggedField = computed(() => fieldDrag.dragged.value);
const pendingInsert = computed(() => fieldDrag.pendingInsert.value);

function onKeydown(event) {
  if (event.key !== 'Escape') return;
  event.preventDefault();
  emit('close');
}

function onBackdrop(event) {
  if (event.target !== event.currentTarget) return;
  emit('close');
}

function labelOf(node) {
  return node?.data?.label || node?.data?.nodeType || '';
}

// Al cambiar de paso se sueltan los estados del arrastre: eran del anterior.
watch(
  () => props.node.id,
  () => {
    activeTab.value = 'config';
    fieldDrag.clearInsert();
    fieldDrag.endDrag();
  }
);

onMounted(() => {
  measure();
  window.addEventListener('resize', measure);
  nextTick(() => root.value?.focus());
});

onBeforeUnmount(() => {
  window.removeEventListener('resize', measure);
  window.removeEventListener('pointermove', onDrag);
  window.removeEventListener('pointerup', endDrag);
});
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-2 backdrop-blur-sm sm:p-4"
      @mousedown="onBackdrop"
    >
      <div
        class="flex h-full w-full max-w-[1800px] flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-background shadow-lg"
        role="dialog"
        aria-modal="true"
        :aria-label="
          t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NODE_DETAIL', { title })
        "
        tabindex="-1"
        @keydown="onKeydown"
      >
        <header
          class="flex h-14 shrink-0 items-center gap-3 border-b border-n-weak bg-n-solid-1 px-3"
        >
          <span
            class="flex size-9 shrink-0 items-center justify-center rounded-xl text-white"
            :style="{ backgroundColor: accent }"
          >
            <span :class="icon" class="size-[18px]" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold text-n-slate-12">
              {{ title }}
            </p>
            <p class="truncate text-xs text-n-slate-11">
              {{ node.id }} · {{ node.data.nodeType }}
            </p>
          </div>

          <!-- Navegar al paso anterior/siguiente sin cerrar la vista. -->
          <div class="flex shrink-0 items-center gap-0.5">
            <button
              type="button"
              class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2 disabled:opacity-40"
              :disabled="!prevNode"
              :title="
                prevNode
                  ? t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.PREV_STEP', {
                      label: labelOf(prevNode),
                    })
                  : t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NO_PREV_STEP')
              "
              @click="prevNode && emit('navigate', prevNode.id)"
            >
              <span class="i-lucide-chevron-left size-4" />
            </button>
            <button
              type="button"
              class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2 disabled:opacity-40"
              :disabled="!nextNode"
              :title="
                nextNode
                  ? t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NEXT_STEP', {
                      label: labelOf(nextNode),
                    })
                  : t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NO_NEXT_STEP')
              "
              @click="nextNode && emit('navigate', nextNode.id)"
            >
              <span class="i-lucide-chevron-right size-4" />
            </button>
          </div>

          <template v-if="!compact">
            <button
              type="button"
              class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
              :title="
                inputCollapsed
                  ? t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.SHOW_INPUT')
                  : t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.HIDE_INPUT')
              "
              :aria-pressed="inputCollapsed"
              @click="inputCollapsed = !inputCollapsed"
            >
              <span
                :class="
                  inputCollapsed
                    ? 'i-lucide-panel-left-open'
                    : 'i-lucide-panel-left-close'
                "
                class="size-4"
              />
            </button>
            <button
              type="button"
              class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
              :title="
                outputCollapsed
                  ? t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.SHOW_OUTPUT')
                  : t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.HIDE_OUTPUT')
              "
              :aria-pressed="outputCollapsed"
              @click="outputCollapsed = !outputCollapsed"
            >
              <span
                :class="
                  outputCollapsed
                    ? 'i-lucide-panel-right-open'
                    : 'i-lucide-panel-right-close'
                "
                class="size-4"
              />
            </button>
          </template>

          <button
            type="button"
            class="flex size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-ruby-3 hover:text-n-ruby-11"
            :title="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.DELETE_STEP')"
            @click="emit('delete')"
          >
            <span class="i-lucide-trash-2 size-4" />
          </button>
          <button
            type="button"
            class="flex size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
            :title="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.CLOSE')"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </header>

        <!-- Mientras se arrastra se lee la ruta exacta que se va a insertar: así
        no se suelta a ciegas. -->
        <div
          v-if="draggedField"
          class="flex shrink-0 items-center gap-2 border-b border-n-brand bg-n-alpha-2 px-3 py-1.5"
        >
          <span class="i-lucide-move size-3.5 shrink-0 text-n-brand" />
          <span class="min-w-0 flex-1 truncate text-[11px] text-n-slate-12">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.DRAGGING') }}
            <code class="font-mono font-semibold">{{ draggedField.path }}</code>
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.DRAGGING_INSERTS') }}
            <code class="font-mono">{{ draggedField.reference }}</code>
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.DRAGGING_TARGETS') }}
          </span>
        </div>

        <div
          v-else-if="pendingInsert"
          class="flex shrink-0 items-center gap-2 border-b border-n-weak bg-n-alpha-1 px-3 py-1.5"
        >
          <span class="i-lucide-info size-3.5 shrink-0 text-n-slate-11" />
          <span class="min-w-0 flex-1 text-[11px] text-n-slate-12">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.PENDING_FIELD') }}
            <code class="font-mono font-semibold">{{
              pendingInsert.path
            }}</code>
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.PENDING_READY') }}
          </span>
          <button
            type="button"
            class="shrink-0 text-[11px] font-medium text-n-slate-11 underline"
            @click="fieldDrag.clearInsert()"
          >
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.CANCEL') }}
          </button>
        </div>

        <!-- MODO COMPACTO: pestañas en lugar de tres columnas. -->
        <div
          v-if="compact"
          class="flex shrink-0 items-center gap-1 border-b border-n-weak bg-n-solid-1 px-2 py-1.5"
          role="tablist"
        >
          <button
            v-for="tab in [
              {
                key: 'input',
                label: t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.INPUT'),
              },
              {
                key: 'config',
                label: t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.CONFIG'),
              },
              {
                key: 'output',
                label: t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.OUTPUT'),
              },
            ]"
            :key="tab.key"
            type="button"
            role="tab"
            :aria-selected="activeTab === tab.key"
            class="h-8 flex-1 rounded-lg px-3 text-xs font-medium transition-colors"
            :class="
              activeTab === tab.key
                ? 'bg-n-brand text-white'
                : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
            "
            @click="activeTab = tab.key"
          >
            {{ tab.label }}
          </button>
        </div>

        <div v-if="compact" class="min-h-0 flex-1 overflow-hidden">
          <div v-show="activeTab === 'input'" class="h-full">
            <InputPanel
              :node="node"
              :previous="previous"
              :direct-previous="directPrevious"
              :output-for="outputFor"
              :loop-node="loopNode"
              @insert-field="onInsertField"
              @run-previous="emit('runPrevious', $event)"
            />
          </div>
          <div v-show="activeTab === 'config'" class="h-full">
            <NodeConfigPanel
              embedded
              :node="node"
              @update-params="emit('updateParams', $event)"
            />
          </div>
          <div v-show="activeTab === 'output'" class="h-full">
            <OutputPanel
              :node="node"
              :test-result="testResult"
              :testing="testing"
              @test="emit('test')"
              @run-from="emit('runFrom')"
            />
          </div>
        </div>

        <!-- TRES COLUMNAS con separadores arrastrables. -->
        <div v-else ref="root" class="flex min-h-0 flex-1 overflow-hidden">
          <section
            v-if="!inputCollapsed"
            class="min-w-0 overflow-hidden border-r border-n-weak"
            :style="{ width: `${inputPct}%` }"
            :aria-label="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.INPUT')"
          >
            <InputPanel
              :node="node"
              :previous="previous"
              :direct-previous="directPrevious"
              :output-for="outputFor"
              :loop-node="loopNode"
              @insert-field="onInsertField"
              @run-previous="emit('runPrevious', $event)"
            />
          </section>
          <button
            v-else
            type="button"
            class="jf-rail"
            :title="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.SHOW_INPUT')"
            @click="inputCollapsed = false"
          >
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.INPUT') }}
          </button>

          <div
            v-if="!inputCollapsed"
            class="jf-splitter"
            :class="dragging === 'input' ? 'is-dragging' : ''"
            role="separator"
            aria-orientation="vertical"
            :aria-label="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.INPUT_WIDTH')"
            tabindex="0"
            @pointerdown="startDrag('input', $event)"
            @keydown.left.prevent="nudge('input', -2)"
            @keydown.right.prevent="nudge('input', 2)"
          />

          <section
            class="min-w-0 flex-1 overflow-hidden"
            :style="{ width: `${configPct}%` }"
            :aria-label="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.CONFIG')"
          >
            <NodeConfigPanel
              embedded
              :node="node"
              @update-params="emit('updateParams', $event)"
            />
          </section>

          <div
            v-if="!outputCollapsed"
            class="jf-splitter"
            :class="dragging === 'output' ? 'is-dragging' : ''"
            role="separator"
            aria-orientation="vertical"
            :aria-label="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.OUTPUT_WIDTH')"
            tabindex="0"
            @pointerdown="startDrag('output', $event)"
            @keydown.left.prevent="nudge('output', 2)"
            @keydown.right.prevent="nudge('output', -2)"
          />

          <section
            v-if="!outputCollapsed"
            class="min-w-0 overflow-hidden border-l border-n-weak"
            :style="{ width: `${outputPct}%` }"
            :aria-label="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.OUTPUT')"
          >
            <OutputPanel
              :node="node"
              :test-result="testResult"
              :testing="testing"
              @test="emit('test')"
              @run-from="emit('runFrom')"
            />
          </section>
          <button
            v-else
            type="button"
            class="jf-rail"
            :title="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.SHOW_OUTPUT')"
            @click="outputCollapsed = false"
          >
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.OUTPUT') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* Separador arrastrable: zona de agarre ancha con una línea fina visible. */
.jf-splitter {
  position: relative;
  flex: 0 0 auto;
  width: 6px;
  cursor: col-resize;
  background: transparent;
  transition: background-color 120ms ease;
}
.jf-splitter::after {
  content: '';
  position: absolute;
  inset: 0 2px;
  border-radius: 2px;
  background: transparent;
  transition: background-color 120ms ease;
}
.jf-splitter:hover::after,
.jf-splitter:focus-visible::after,
.jf-splitter.is-dragging::after {
  background: #2781f6;
}

/* Pestaña vertical para reabrir un lateral colapsado. */
.jf-rail {
  flex: 0 0 auto;
  width: 30px;
  writing-mode: vertical-rl;
  border-right: 1px solid rgb(var(--border-weak));
  background: rgb(var(--solid-1));
  color: rgb(var(--slate-11));
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
.jf-rail:hover {
  background: rgba(var(--alpha-2));
}
</style>
