<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  effectiveContract,
  fieldsOfItemAt,
  shortValue,
} from '../composables/useOutputContract';
import {
  buildValueRef,
  buildItemsRef,
  hasItemsRef,
  writeDraggedField,
  useFieldDrag,
} from '../composables/useFieldDrag';

// Panel de datos arrastrable. Lo usan la ENTRADA y la SALIDA de la vista de
// detalle: los dos muestran un payload y de los dos se arrastran campos.
const props = defineProps({
  // Payload crudo del paso (la salida tal cual la devuelve el motor).
  payload: { type: null, default: undefined },
  // Contrato servido por `run_node`; si falta se proyecta de reserva.
  contract: { type: Object, default: null },
  // `itemsPath` del tipo del paso: decide qué es `output` y qué es `.meta`.
  itemsPath: { type: String, default: undefined },
  // Prefijo de las referencias: trigger, item o node.<id>.
  origin: { type: Object, required: true },
  // Procedencia legible del dato («prueba de este paso», «ejemplo»…).
  source: { type: String, default: '' },
  // true cuando el dato es un EJEMPLO del catálogo, no de la cuenta.
  isSample: { type: Boolean, default: false },
  // La salida propia no se arrastra a la configuración del mismo paso.
  noDrag: { type: Boolean, default: false },
});

const emit = defineEmits(['insertField']);

const { t } = useI18n();

const fieldDrag = useFieldDrag();
const view = ref('schema');
const itemIndex = ref(0);

// La proyección se decide en un único sitio para que las dos vistas coincidan.
const shape = computed(() =>
  effectiveContract(props.contract, props.payload, props.itemsPath)
);

const fields = computed(() => fieldsOfItemAt(shape.value, itemIndex.value));
const currentItem = computed(() => shape.value.items[itemIndex.value]);

const metaEntries = computed(() => Object.entries(shape.value.metadata || {}));

const jsonText = computed(() => {
  try {
    return JSON.stringify(currentItem.value ?? props.payload ?? null, null, 2);
  } catch {
    return String(currentItem.value);
  }
});

// Última porción legible de una ruta, para la etiqueta del arrastre.
function labelOf(path) {
  const match = path.match(/(?:\["(.*)"\]|(?:^|\.)([^.[\]]+))$/);
  return match?.[1] ?? match?.[2] ?? path;
}

function fieldFor(path) {
  return {
    path,
    reference: buildValueRef(props.origin, path),
    label: labelOf(path),
  };
}

function startFieldDrag(event, path) {
  if (props.noDrag) return;
  writeDraggedField(event, fieldDrag, fieldFor(path));
}

function onDragEnd() {
  fieldDrag?.endDrag();
}

function insertField(path) {
  emit('insertField', fieldFor(path));
}

// ASA DE COLECCIÓN: solo cuando el tipo declara `itemsPath`. Es lo que espera el
// param «Colección» del bucle, y NO es lo mismo que un campo del elemento.
const canDragItems = computed(
  () => !props.noDrag && hasItemsRef(props.origin, shape.value)
);

const itemsField = computed(() => ({
  path: 'items',
  reference: buildItemsRef(props.origin),
  label: `Los ${shape.value.itemCount} ${
    shape.value.itemCount === 1 ? 'elemento' : 'elementos'
  }`,
}));

function startItemsDrag(event) {
  if (!canDragItems.value) return;
  writeDraggedField(event, fieldDrag, itemsField.value);
}

// En una constante: el texto lleva `.meta.*` y en la plantilla se concatena
// con el rótulo de metadatos.
const META_HINT = t('JABVOX_ADVANCED_AUTOMATIONS.DATA.META_HINT');

const typeColor = {
  string: 'text-n-teal-11',
  number: 'text-n-blue-11',
  boolean: 'text-n-violet-11',
  null: 'text-n-slate-10',
  object: 'text-n-amber-11',
  array: 'text-n-amber-11',
};

// Al cambiar de origen se vuelve al primer elemento: el índice era de otra lista.
watch(
  () => [props.origin.kind, props.origin.nodeId, props.payload],
  () => {
    itemIndex.value = 0;
  }
);
</script>

<template>
  <div class="flex h-full min-h-0 flex-col">
    <!-- Procedencia del dato: mapear contra un ejemplo está bien, creer que son
    los datos de tu cuenta no. -->
    <div
      v-if="source"
      class="flex shrink-0 items-center gap-1.5 px-3 py-1.5 text-[11px]"
      :class="
        isSample
          ? 'bg-n-amber-3 text-n-amber-11'
          : 'bg-n-alpha-1 text-n-slate-11'
      "
    >
      <span
        :class="isSample ? 'i-lucide-triangle-alert' : 'i-lucide-info'"
        class="size-3.5 shrink-0"
      />
      <span class="truncate">{{ source }}</span>
    </div>

    <div
      class="flex shrink-0 items-center gap-2 border-b border-n-weak px-3 py-2"
    >
      <div class="flex gap-1">
        <button
          v-for="item in [
            {
              key: 'schema',
              label: t('JABVOX_ADVANCED_AUTOMATIONS.DATA.FIELDS'),
            },
            { key: 'json', label: t('JABVOX_ADVANCED_AUTOMATIONS.DATA.JSON') },
          ]"
          :key="item.key"
          type="button"
          class="rounded-md px-2 py-1 text-xs font-medium transition-colors"
          :class="
            view === item.key
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="view = item.key"
        >
          {{ item.label }}
        </button>
      </div>

      <!-- Navegar entre elementos cuando el paso devuelve una colección. -->
      <div
        v-if="shape.itemCount > 1"
        class="ml-auto flex items-center gap-1 text-xs text-n-slate-11"
      >
        <button
          type="button"
          class="flex size-6 items-center justify-center rounded-md hover:bg-n-alpha-2 disabled:opacity-40"
          :disabled="itemIndex === 0"
          @click="itemIndex -= 1"
        >
          <span class="i-lucide-chevron-left size-3.5" />
        </button>
        <span class="tabular-nums"
          >{{ itemIndex + 1 }} / {{ shape.itemCount }}</span
        >
        <button
          type="button"
          class="flex size-6 items-center justify-center rounded-md hover:bg-n-alpha-2 disabled:opacity-40"
          :disabled="itemIndex >= shape.itemCount - 1"
          @click="itemIndex += 1"
        >
          <span class="i-lucide-chevron-right size-3.5" />
        </button>
      </div>
    </div>

    <div class="min-h-0 flex-1 overflow-y-auto p-3">
      <!-- Asa de la colección completa: `{{node.<id>.items}}`. -->
      <div
        v-if="canDragItems"
        :draggable="true"
        class="mb-3 flex cursor-grab items-center gap-2 rounded-lg border border-dashed border-n-amber-8 bg-n-amber-3 px-2.5 py-2 active:cursor-grabbing"
        @dragstart="startItemsDrag"
        @dragend="onDragEnd"
      >
        <span class="i-lucide-list size-4 shrink-0 text-n-amber-11" />
        <span class="min-w-0 flex-1 text-xs font-medium text-n-amber-11">
          {{ itemsField.label }}
        </span>
        <button
          type="button"
          class="shrink-0 rounded-md px-1.5 py-0.5 text-[11px] font-medium text-n-amber-11 hover:bg-n-amber-4"
          :title="t('JABVOX_ADVANCED_AUTOMATIONS.DATA.INSERT_NO_DRAG')"
          @click="emit('insertField', itemsField)"
        >
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.DATA.INSERT') }}
        </button>
      </div>

      <template v-if="view === 'schema'">
        <ul v-if="fields.length" class="flex flex-col gap-0.5">
          <li
            v-for="field in fields"
            :key="field.path"
            :draggable="!noDrag"
            class="group flex items-center gap-2 rounded-md px-2 py-1.5 transition-colors hover:bg-n-alpha-2"
            :class="noDrag ? '' : 'cursor-grab active:cursor-grabbing'"
            :style="{ paddingLeft: `${8 + field.depth * 14}px` }"
            :title="field.path"
            @dragstart="startFieldDrag($event, field.path)"
            @dragend="onDragEnd"
          >
            <span
              class="i-lucide-grip-vertical size-3 shrink-0 text-n-slate-9 opacity-0 group-hover:opacity-100"
              :class="noDrag ? '!opacity-0' : ''"
            />
            <span
              class="truncate text-xs font-medium text-n-slate-12"
              :class="field.leaf ? '' : 'font-semibold'"
            >
              {{ field.label }}
            </span>
            <span
              class="shrink-0 text-[10px] uppercase"
              :class="typeColor[field.type] || 'text-n-slate-10'"
            >
              {{ field.type }}
            </span>
            <span
              class="ml-auto max-w-[45%] truncate text-right font-mono text-[11px] text-n-slate-11"
            >
              {{ shortValue(field.sample, 40) }}
            </span>
            <button
              v-if="!noDrag"
              type="button"
              class="shrink-0 rounded px-1 text-[11px] font-medium text-n-brand opacity-0 transition-opacity hover:bg-n-alpha-2 group-hover:opacity-100"
              :title="t('JABVOX_ADVANCED_AUTOMATIONS.DATA.INSERT_NO_DRAG')"
              @click="insertField(field.path)"
            >
              +
            </button>
          </li>
        </ul>
        <p v-else class="px-1 py-4 text-xs text-n-slate-11">
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.DATA.NO_FIELDS') }}
        </p>

        <!-- Los metadatos NO están en `output` cuando hay colección: van a `.meta.*`. -->
        <div v-if="metaEntries.length" class="mt-4">
          <p
            class="mb-1.5 px-1 text-[10px] font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.DATA.META') }} ({{ META_HINT }})
          </p>
          <ul class="flex flex-col gap-0.5">
            <li
              v-for="[key, value] in metaEntries"
              :key="key"
              class="flex items-center gap-2 rounded-md px-2 py-1 text-xs"
            >
              <span class="truncate font-medium text-n-slate-12">{{
                key
              }}</span>
              <span
                class="ml-auto truncate font-mono text-[11px] text-n-slate-11"
              >
                {{ shortValue(value, 32) }}
              </span>
            </li>
          </ul>
        </div>
      </template>

      <pre
        v-else
        class="overflow-x-auto rounded-lg bg-n-alpha-1 p-3 font-mono text-[11px] leading-relaxed text-n-slate-12"
        >{{ jsonText }}</pre
      >
    </div>
  </div>
</template>
