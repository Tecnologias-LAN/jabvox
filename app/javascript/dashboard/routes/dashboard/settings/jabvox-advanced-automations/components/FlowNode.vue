<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Handle, Position } from '@vue-flow/core';
import { useNodesStore } from 'dashboard/store/jabvox/flows/nodes';
import {
  nodeIcon,
  categoryStyle,
  runStatusStyle,
} from '../composables/useFlowDesign';

// Nodo del lienzo. El aspecto sale del CATÁLOGO (icono, color, puertos), así que
// un tipo nuevo del backend se dibuja sin tocar este componente.
const props = defineProps({
  data: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
});

const { t } = useI18n();
const nodesStore = useNodesStore();

const definition = computed(
  () => nodesStore.getDefinition(props.data.nodeType) || {}
);
const label = computed(
  () => props.data.label || definition.value.label || props.data.nodeType
);
const color = computed(() => definition.value.color || '#64748b');
const isTrigger = computed(() => definition.value.isTrigger === true);
const icon = computed(() => nodeIcon(definition.value));
const category = computed(() => categoryStyle(definition.value.category));

// Subtítulo: el dato más útil ya configurado, para leer el nodo sin abrirlo.
const subtitle = computed(() => {
  const params = props.data.params || {};
  const specs = definition.value.params || [];
  const first = specs.find(
    s =>
      params[s.key] !== undefined &&
      params[s.key] !== '' &&
      s.type !== 'boolean'
  );
  if (!first)
    return definition.value.category === 'jabvox'
      ? definition.value.module
      : '';
  const value = params[first.key];
  const text = Array.isArray(value) ? value.join(', ') : String(value);
  return text.length > 38 ? `${text.slice(0, 38)}…` : text;
});

// `logic.switch` deriva sus salidas de los casos configurados, no del catálogo.
const outputs = computed(() => {
  if (props.data.nodeType === 'logic.switch') {
    const cases = Array.isArray(props.data.params?.cases)
      ? props.data.params.cases
      : [];
    return [
      ...cases.map((c, i) => ({ id: c.key || `case${i}`, label: c.label })),
      {
        id: 'default',
        label: t('JABVOX_ADVANCED_AUTOMATIONS.NODE.DEFAULT_PORT'),
      },
    ];
  }
  return definition.value.outputs?.length
    ? definition.value.outputs
    : [{ id: 'out' }];
});

// Estado del paso en la ejecución que se está viendo (solo en modo lectura).
const runStatus = computed(() => props.data.runStatus);
const statusStyle = computed(() =>
  runStatus.value ? runStatusStyle(runStatus.value) : null
);

// El borde comunica el estado; la prioridad es error > correcto > ejecutando.
const stateRing = computed(() => {
  if (props.data.disabled) return 'border-n-weak';
  if (runStatus.value === 'failed') return 'border-n-ruby-9';
  if (runStatus.value === 'success') return 'border-n-teal-9';
  if (runStatus.value === 'running') return 'border-n-blue-9';
  if (props.selected) return 'border-transparent';
  return 'border-n-weak';
});
</script>

<template>
  <div
    class="group relative min-w-[224px] max-w-[280px] rounded-xl border bg-n-solid-1 shadow-sm transition-shadow duration-150 hover:shadow-md"
    :class="[stateRing, { 'opacity-50': data.disabled }]"
    :style="selected ? { boxShadow: `0 0 0 2px ${color}` } : null"
  >
    <Handle
      v-if="!isTrigger"
      id="in"
      type="target"
      :position="Position.Left"
      class="!size-3 !rounded-full !border-2 !border-n-solid-1 !bg-n-slate-8"
    />

    <div class="flex items-start gap-3 p-3">
      <span
        class="flex size-9 shrink-0 items-center justify-center rounded-lg text-white"
        :style="{ backgroundColor: color }"
      >
        <span :class="icon" class="size-5" />
      </span>

      <div class="min-w-0 flex-1">
        <p class="truncate text-sm font-semibold leading-tight text-n-slate-12">
          {{ label }}
        </p>
        <p v-if="subtitle" class="mt-0.5 truncate text-xs text-n-slate-11">
          {{ subtitle }}
        </p>
      </div>

      <span
        v-if="statusStyle"
        class="flex size-5 shrink-0 items-center justify-center rounded-full"
        :class="statusStyle.chip"
      >
        <span
          :class="[statusStyle.icon, { 'animate-spin': statusStyle.spin }]"
          class="size-3.5"
        />
      </span>
    </div>

    <div
      v-if="isTrigger || data.disabled"
      class="flex flex-wrap gap-1 px-3 pb-2.5"
    >
      <span
        v-if="isTrigger"
        class="inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[10px] font-medium"
        :class="category.chip"
      >
        <span class="i-lucide-zap size-2.5" />
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.NODE.TRIGGER') }}
      </span>
      <span
        v-if="data.disabled"
        class="inline-flex items-center gap-1 rounded-md bg-n-amber-3 px-1.5 py-0.5 text-[10px] font-medium text-n-amber-11"
      >
        <span class="i-lucide-power-off size-2.5" />
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.NODE.OFF') }}
      </span>
    </div>

    <Handle
      v-for="(port, index) in outputs"
      :id="port.id"
      :key="port.id"
      type="source"
      :position="Position.Right"
      class="!size-3 !rounded-full !border-2 !border-n-solid-1"
      :style="{
        top: `${((index + 1) * 100) / (outputs.length + 1)}%`,
        backgroundColor: color,
      }"
    />

    <!-- Con varias salidas hay que decir cuál es cuál: si no, no se distinguen. -->
    <div
      v-if="outputs.length > 1"
      class="border-t border-n-weak px-3 py-1.5 text-right"
    >
      <span
        v-for="port in outputs"
        :key="port.id"
        class="ml-2 text-[10px] font-medium text-n-slate-11"
      >
        {{ port.label || port.id }}
      </span>
    </div>
  </div>
</template>
