<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNodesStore } from 'dashboard/store/jabvox/flows/nodes';
import DataPanel from './DataPanel.vue';

// Panel de ENTRADA: qué datos le llegan a este paso. Si hay varios previos, un
// selector elige cuál mirar. Dentro de un bucle ofrece el elemento en curso.
const props = defineProps({
  // Paso cuyo detalle está abierto.
  node: { type: Object, required: true },
  // Pasos ANTERIORES en el grafo, ya en orden.
  previous: { type: Array, default: () => [] },
  // Paso anterior INMEDIATO: es la fuente por defecto.
  directPrevious: { type: String, default: null },
  // Salida conocida de un paso: { value, contract, source }.
  outputFor: { type: Function, required: true },
  // Bucle que ENCIERRA a este paso; null si no está dentro de ninguno.
  loopNode: { type: Object, default: null },
});

const emit = defineEmits(['insertField', 'runPrevious']);

const { t } = useI18n();
const nodesStore = useNodesStore();

// Valor especial: dentro del bucle la referencia correcta es `{{item.*}}`, no
// `{{node.<id>.output.*}}`, que procesaría siempre el primer elemento.
const LOOP_SOURCE = '__bucle__';

// null = el usuario no ha elegido y manda la fuente por defecto.
const sourceId = ref(null);

function labelOf(node) {
  return node?.data?.label || node?.data?.nodeType || node?.id || '';
}

function definitionOf(node) {
  return node ? nodesStore.getDefinition(node.data?.nodeType) : null;
}

// Elemento en curso del bucle: el PRIMERO de la colección que resolvió. Es lo
// que `{{item.*}}` vale en la primera vuelta y sirve para mapear los campos.
const loopItem = computed(() => {
  if (!props.loopNode) return undefined;
  const known = props.outputFor(props.loopNode.id);
  const items = known?.value?.items;
  return Array.isArray(items) ? items[0] : undefined;
});

const options = computed(() => {
  const list = [];

  if (props.loopNode) {
    list.push({
      value: LOOP_SOURCE,
      label: t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.LOOP_ITEM', {
        label: labelOf(props.loopNode),
      }),
      hasData: loopItem.value !== undefined,
    });
  }

  props.previous.forEach(node => {
    const known = props.outputFor(node.id);
    const isTrigger = definitionOf(node)?.isTrigger === true;
    list.push({
      value: node.id,
      label: isTrigger
        ? t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.TRIGGER_SUFFIX', {
            label: labelOf(node),
          })
        : labelOf(node),
      hasData: known !== null && known !== undefined,
    });
  });
  return list;
});

// Por defecto manda el elemento del bucle; fuera, el paso anterior INMEDIATO.
// Caer en el primero de la lista mostraba el disparador en vez de lo que de
// verdad alimenta al paso.
const defaultSource = computed(() => {
  if (props.loopNode) return LOOP_SOURCE;
  const direct = props.directPrevious;
  if (direct && options.value.some(o => o.value === direct)) return direct;
  return options.value[0]?.value ?? '';
});

const effectiveSource = computed(() => {
  if (
    sourceId.value !== null &&
    options.value.some(o => o.value === sourceId.value)
  ) {
    return sourceId.value;
  }
  return defaultSource.value;
});

const selectedNode = computed(
  () => props.previous.find(n => n.id === effectiveSource.value) ?? null
);

const SOURCE_LABELS = {
  run: t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.SOURCE_RUN'),
  test: t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.SOURCE_TEST'),
  sample: t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.SOURCE_SAMPLE'),
};

// Datos que se pintan y de dónde salen.
const current = computed(() => {
  if (effectiveSource.value === LOOP_SOURCE) {
    if (loopItem.value === undefined) return null;
    return {
      payload: loopItem.value,
      contract: null,
      source: t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.SOURCE_LOOP_ITEM'),
      isSample: props.outputFor(props.loopNode?.id)?.source === 'sample',
    };
  }
  const known = props.outputFor(effectiveSource.value);
  if (!known) return null;
  return {
    payload: known.value,
    contract: known.contract ?? null,
    source: SOURCE_LABELS[known.source] ?? known.source,
    isSample: known.source === 'sample',
  };
});

// El `itemsPath` del paso del que vienen los datos: manda su definición, porque
// es lo que decide si `output` es un elemento y qué va a `.meta.*`.
const itemsPath = computed(() => {
  // El elemento en curso YA es un elemento: no tiene colección que proyectar.
  if (effectiveSource.value === LOOP_SOURCE) return undefined;
  return definitionOf(selectedNode.value)?.itemsPath;
});

// Prefijo con el que se construyen las referencias que se arrastran.
const origin = computed(() => {
  if (effectiveSource.value === LOOP_SOURCE) return { kind: 'item' };
  if (definitionOf(selectedNode.value)?.isTrigger === true) {
    return { kind: 'trigger' };
  }
  return { kind: 'node', nodeId: effectiveSource.value };
});

// Al cambiar de paso abierto se suelta la elección: manda la fuente por defecto.
watch(
  () => props.node.id,
  () => {
    sourceId.value = null;
  }
);
</script>

<template>
  <section class="flex h-full min-h-0 flex-col bg-n-solid-1">
    <header
      class="flex shrink-0 items-center gap-2 border-b border-n-weak px-3 py-2.5"
    >
      <span class="i-lucide-log-in size-4 shrink-0 text-n-slate-11" />
      <h3
        class="shrink-0 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
      >
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.INPUT') }}
      </h3>
      <select
        v-if="options.length > 1"
        :value="effectiveSource"
        class="!mb-0 ml-auto min-w-0 max-w-[60%] appearance-none rounded-md border-0 bg-n-alpha-2 !px-2 !py-1 text-xs text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak"
        @change="sourceId = $event.target.value"
      >
        <option v-for="opt in options" :key="opt.value" :value="opt.value">
          {{ opt.label
          }}{{
            opt.hasData
              ? ''
              : t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.NO_DATA_SUFFIX')
          }}
        </option>
      </select>
    </header>

    <DataPanel
      v-if="current"
      :payload="current.payload"
      :contract="current.contract"
      :items-path="itemsPath"
      :origin="origin"
      :source="current.source"
      :is-sample="current.isSample"
      @insert-field="emit('insertField', $event)"
    />

    <!-- Sin datos NO se deja el panel en blanco: se dice qué hacer. -->
    <div
      v-else
      class="flex flex-1 flex-col items-center justify-center gap-3 px-6 text-center"
    >
      <span
        class="flex size-11 items-center justify-center rounded-2xl bg-n-alpha-2"
      >
        <span class="i-lucide-database size-5 text-n-slate-10" />
      </span>
      <p class="text-sm leading-relaxed text-n-slate-11">
        {{
          options.length
            ? t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.EMPTY_WITH_PREVIOUS')
            : t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.EMPTY_NO_PREVIOUS')
        }}
      </p>
      <button
        v-if="effectiveSource && effectiveSource !== LOOP_SOURCE"
        type="button"
        class="inline-flex h-8 items-center gap-1.5 rounded-lg px-3 text-sm font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2"
        @click="emit('runPrevious', effectiveSource)"
      >
        <span class="i-lucide-flask-conical size-4" />
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.INPUT.RUN_PREVIOUS') }}
      </button>
    </div>
  </section>
</template>
