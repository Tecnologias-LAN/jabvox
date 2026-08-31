<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { nodesAPI } from 'dashboard/api/jabvox/flows';
import {
  isDroppableParam,
  readDroppedField,
  textForParam,
  useFieldDrag,
} from '../composables/useFieldDrag';

// Una casilla del panel de configuración, renderizada desde el CATÁLOGO. El tipo
// del param decide el widget; `optionsSource` carga sus opciones de la cuenta.
const props = defineProps({
  spec: { type: Object, required: true },
  modelValue: { type: [String, Number, Boolean, Object, Array], default: '' },
  // Valores del resto de params: los necesita `dependsOn` para pedir opciones.
  params: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const dynamicOptions = ref([]);
const loadingOptions = ref(false);
const optionsError = ref(false);

const value = computed({
  get: () => props.modelValue,
  set: v => emit('update:modelValue', v),
});

const options = computed(() =>
  props.spec.optionsSource ? dynamicOptions.value : props.spec.options || []
);

// Tipos compuestos: se editan como JSON para no alterar la forma que espera el
// motor. El widget da formato y avisa si el JSON deja de ser válido.
const isComposite = computed(() =>
  [
    'json',
    'conditions',
    'orderitems',
    'fieldmap',
    'variablemap',
    'key-value',
  ].includes(props.spec.type)
);
const isMultiselect = computed(() => props.spec.type === 'multiselect');
const isLongText = computed(() =>
  ['textarea', 'text', 'code'].includes(props.spec.type)
);
// `optionsSource` también convierte en desplegable a un param sin tipo select,
// salvo que ya lo trate otro widget (compuesto o multiselección).
const isSelect = computed(
  () =>
    props.spec.type === 'select' ||
    (props.spec.optionsSource && !isComposite.value && !isMultiselect.value)
);

// Un select cuyas opciones dependen de otro param no se pide hasta que ese
// param tiene valor: sin él el backend responde 400.
const dependencyValue = computed(() =>
  props.spec.dependsOn ? props.params[props.spec.dependsOn] : null
);

const blockedByDependency = computed(
  () => Boolean(props.spec.dependsOn) && !dependencyValue.value
);

async function loadOptions() {
  if (!props.spec.optionsSource) return;
  if (blockedByDependency.value) {
    dynamicOptions.value = [];
    return;
  }
  loadingOptions.value = true;
  optionsError.value = false;
  try {
    const params = props.spec.dependsOn
      ? { [props.spec.dependsOn]: dependencyValue.value }
      : undefined;
    const { data } = await nodesAPI.options(props.spec.optionsSource, params);
    dynamicOptions.value = data;
  } catch {
    dynamicOptions.value = [];
    optionsError.value = true;
  } finally {
    loadingOptions.value = false;
  }
}

// Multiselección: se guarda como array, igual que espera el catálogo.
const selectedList = computed(() =>
  Array.isArray(props.modelValue) ? props.modelValue : []
);

function toggleOption(optionValue) {
  const current = selectedList.value;
  emit(
    'update:modelValue',
    current.includes(optionValue)
      ? current.filter(v => v !== optionValue)
      : [...current, optionValue]
  );
}

// El JSON se edita como texto y solo se propaga cuando es válido: así no se
// guarda a medias mientras se escribe.
const jsonDraft = ref('');
const jsonInvalid = ref(false);

function syncJsonDraft() {
  if (!isComposite.value) return;
  const raw = props.modelValue;
  if (raw === '' || raw === undefined || raw === null) {
    jsonDraft.value = '';
    return;
  }
  jsonDraft.value =
    typeof raw === 'string' ? raw : JSON.stringify(raw, null, 2);
}

function onJsonInput(event) {
  const text = event.target.value;
  jsonDraft.value = text;
  if (!text.trim()) {
    jsonInvalid.value = false;
    emit('update:modelValue', props.spec.default ?? '');
    return;
  }
  try {
    emit('update:modelValue', JSON.parse(text));
    jsonInvalid.value = false;
  } catch {
    jsonInvalid.value = true;
  }
}

const inputClass =
  '!mb-0 block w-full rounded-lg border-0 bg-n-alpha-black2 !px-3 !py-2 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-all placeholder:text-n-slate-10 hover:outline-n-slate-6 focus:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50';

// ---- Recibir un campo arrastrado desde el panel de entrada ----
const fieldDrag = useFieldDrag();
const dropHover = ref(false);

const acceptsDrop = computed(() => isDroppableParam(props.spec));

// Resaltado mientras hay un arrastre en curso: se ve dónde se puede soltar.
const highlighted = computed(
  () => Boolean(fieldDrag?.dragging?.value) && acceptsDrop.value
);

function onDragOver(event) {
  if (!acceptsDrop.value) return;
  // preventDefault es lo que HABILITA el soltar: sin él el navegador lo rechaza.
  event.preventDefault();
  if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
  dropHover.value = true;
}

function onDragLeave(event) {
  const to = event.relatedTarget;
  const zone = event.currentTarget;
  // Pasar del borde al <input> de dentro emitía un dragleave y parpadeaba.
  if (to instanceof Node && zone instanceof Node && zone.contains(to)) return;
  dropHover.value = false;
}

// Inserta el texto respetando el tipo: number y json pasan a guardar TEXTO
// cuando reciben una plantilla, porque `{{…}}` no es un número ni JSON válido.
function applyText(text) {
  const current = props.modelValue;
  const asText = typeof current === 'string' ? current : '';
  const next = asText.trim() === '' ? text : `${asText}${text}`;
  if (isComposite.value) {
    jsonDraft.value = next;
    jsonInvalid.value = false;
  }
  emit('update:modelValue', next);
}

// Un <input>/<textarea> es destino de soltado NATIVO: si se le deja actuar pega
// el text/plain crudo sin pasar por aquí y, en un param 'path', pega la
// expresión donde debía ir la ruta pelada. Se corta en fase de CAPTURA.
function onDrop(event) {
  dropHover.value = false;
  if (!acceptsDrop.value) return;
  const dropped = readDroppedField(event);
  if (!dropped) return;
  event.preventDefault();
  event.stopPropagation();
  applyText(textForParam(props.spec, dropped));
  fieldDrag?.endDrag();
}

// Insertar sin arrastrar: el botón «+» del panel deja el campo pendiente y este
// param lo recoge. Es la alternativa accesible al arrastre.
const pendingInsert = computed(() => fieldDrag?.pendingInsert?.value ?? null);

function takePending() {
  const field = pendingInsert.value;
  if (!field) return;
  applyText(textForParam(props.spec, field));
  fieldDrag?.clearInsert();
}

onMounted(() => {
  loadOptions();
  syncJsonDraft();
});
watch(dependencyValue, loadOptions);
watch(() => props.modelValue, syncJsonDraft);
</script>

<template>
  <!-- La zona de soltado envuelve TODO el campo, y escucha en fase de captura:
  si no, el <input> se traga el evento y pega el texto crudo. -->
  <div
    class="flex flex-col gap-1.5 rounded-lg transition-all"
    :class="[
      highlighted
        ? 'outline-dashed outline-1 outline-offset-4 outline-n-brand'
        : '',
      dropHover ? 'bg-n-alpha-2' : '',
    ]"
    @dragenter.capture="onDragOver"
    @dragover.capture="onDragOver"
    @dragleave="onDragLeave"
    @drop.capture="onDrop"
  >
    <label
      :for="spec.key"
      class="flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
    >
      {{ spec.label }}
      <span v-if="spec.required" class="text-n-ruby-11">*</span>
      <span
        v-if="spec.templatable"
        class="i-lucide-braces size-3.5 shrink-0 text-n-slate-10"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.TEMPLATABLE_HINT')"
      />
      <!-- Un param 'path' espera el NOMBRE del campo, no la expresión. -->
      <span
        v-if="spec.dropSemantics === 'path'"
        class="rounded bg-n-alpha-2 px-1 py-px text-[10px] font-normal text-n-slate-11"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.PATH_HINT')"
      >
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.PATH_BADGE') }}
      </span>
      <button
        v-if="pendingInsert && acceptsDrop"
        type="button"
        class="ml-auto shrink-0 rounded-md bg-n-brand px-2 py-0.5 text-[11px] font-medium text-white transition-all hover:brightness-110"
        @click="takePending"
      >
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.INSERT_HERE') }}
      </button>
    </label>

    <!-- Selección múltiple: casillas, no un campo de texto suelto. -->
    <div
      v-if="isMultiselect"
      class="flex flex-wrap gap-1.5 rounded-lg border border-n-weak p-2"
    >
      <button
        v-for="opt in options"
        :key="opt.value"
        type="button"
        class="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs font-medium transition-colors"
        :class="
          selectedList.includes(opt.value)
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
        "
        @click="toggleOption(opt.value)"
      >
        <span
          v-if="selectedList.includes(opt.value)"
          class="i-lucide-check size-3"
        />
        {{ opt.label }}
      </button>
      <p v-if="!options.length" class="text-xs text-n-slate-10">
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.NO_OPTIONS') }}
      </p>
    </div>

    <!-- Interruptor: un booleano se lee mejor así que como casilla suelta. -->
    <button
      v-else-if="spec.type === 'boolean'"
      :id="spec.key"
      type="button"
      role="switch"
      :aria-checked="value === true"
      class="relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors"
      :class="value === true ? 'bg-n-brand' : 'bg-n-slate-6'"
      @click="value = !value"
    >
      <span
        class="inline-block size-3.5 rounded-full bg-white transition-transform"
        :class="value === true ? 'translate-x-[18px]' : 'translate-x-[3px]'"
      />
    </button>

    <select
      v-else-if="isSelect"
      :id="spec.key"
      v-model="value"
      :disabled="loadingOptions || blockedByDependency"
      :class="inputClass"
      class="appearance-none bg-none pr-9"
    >
      <option value="" />
      <option v-for="opt in options" :key="opt.value" :value="opt.value">
        {{ opt.label }}
      </option>
    </select>

    <textarea
      v-else-if="isComposite"
      :id="spec.key"
      :value="jsonDraft"
      rows="6"
      spellcheck="false"
      :class="inputClass"
      class="font-mono !text-xs"
      :placeholder="spec.placeholder"
      @input="onJsonInput"
    />

    <textarea
      v-else-if="isLongText"
      :id="spec.key"
      v-model="value"
      rows="4"
      :class="inputClass"
      :placeholder="spec.placeholder"
    />

    <input
      v-else-if="spec.type === 'number'"
      :id="spec.key"
      v-model.number="value"
      type="number"
      :min="spec.min"
      :max="spec.max"
      :class="inputClass"
      :placeholder="spec.placeholder"
    />

    <input
      v-else-if="spec.type === 'time'"
      :id="spec.key"
      v-model="value"
      type="time"
      :class="inputClass"
    />

    <input
      v-else
      :id="spec.key"
      v-model="value"
      type="text"
      :class="inputClass"
      :placeholder="spec.placeholder"
    />

    <!-- Mensajes: por qué un select está vacío, o que el JSON no es válido. -->
    <p
      v-if="jsonInvalid"
      class="flex items-center gap-1.5 text-xs text-n-ruby-11"
    >
      <span class="i-lucide-circle-alert size-3.5 shrink-0" />
      {{ t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.INVALID_JSON') }}
    </p>
    <p
      v-else-if="blockedByDependency"
      class="flex items-center gap-1.5 text-xs text-n-amber-11"
    >
      <span class="i-lucide-info size-3.5 shrink-0" />
      {{
        t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.BLOCKED_BY_DEPENDENCY', {
          field: spec.dependsOn,
        })
      }}
    </p>
    <p
      v-else-if="optionsError"
      class="flex items-center gap-1.5 text-xs text-n-ruby-11"
    >
      <span class="i-lucide-circle-alert size-3.5 shrink-0" />
      {{ t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.OPTIONS_ERROR') }}
    </p>
    <p
      v-else-if="loadingOptions"
      class="flex items-center gap-1.5 text-xs text-n-slate-11"
    >
      <span class="i-lucide-loader-circle size-3.5 shrink-0 animate-spin" />
      {{ t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.LOADING_OPTIONS') }}
    </p>

    <p v-if="spec.description" class="text-xs leading-relaxed text-n-slate-11">
      {{ spec.description }}
    </p>

    <!-- El detalle largo va plegado para no tapar el campo siguiente. -->
    <details v-if="spec.details" class="group">
      <summary
        class="inline-flex cursor-pointer list-none items-center gap-1 text-xs font-medium text-n-slate-11 transition-colors hover:text-n-slate-12"
      >
        <span
          class="i-lucide-chevron-right size-3.5 shrink-0 transition-transform group-open:rotate-90"
        />
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.PARAM.MORE_INFO') }}
      </summary>
      <p class="mt-1.5 text-xs leading-relaxed text-n-slate-11">
        {{ spec.details }}
      </p>
    </details>
  </div>
</template>
