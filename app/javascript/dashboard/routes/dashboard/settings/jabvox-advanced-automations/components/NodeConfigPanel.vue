<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNodesStore } from 'dashboard/store/jabvox/flows/nodes';
import ParamField from './ParamField.vue';
import { nodeIcon, categoryStyle } from '../composables/useFlowDesign';

// Panel de configuración del paso seleccionado. Se dibuja ENTERO desde el
// catálogo: no hay ningún formulario codificado por tipo de nodo.
const props = defineProps({
  node: { type: Object, default: null },
  // Salida de la última prueba del paso, para el panel de salida.
  testResult: { type: Object, default: null },
  testing: { type: Boolean, default: false },
  // Embebido en la vista de detalle: sin ancho fijo, y sin las pestañas ni los
  // botones de probar, que allí viven en la columna de salida.
  embedded: { type: Boolean, default: false },
});
const emit = defineEmits(['updateParams', 'test', 'runFrom', 'delete']);

const { t } = useI18n();
const nodesStore = useNodesStore();
const tab = ref('config');

const definition = computed(() =>
  props.node ? nodesStore.getDefinition(props.node.data.nodeType) : null
);

const params = computed(() => props.node?.data?.params || {});
const icon = computed(() => nodeIcon(definition.value));
const category = computed(() => categoryStyle(definition.value?.category));

// Un param oculto por su visibilidad condicional no se pinta: el motor tampoco
// lo exige, así que enseñarlo solo confundiría.
function isVisible(spec) {
  const matches = cond =>
    cond && (cond.values || []).includes(params.value[cond.param]);
  if (spec.visibleWhen && !matches(spec.visibleWhen)) return false;
  return (spec.visibleWhenAll || []).every(matches);
}

const visibleParams = computed(() =>
  (definition.value?.params || []).filter(isVisible)
);

// Obligatorios sin valor: se avisa aquí antes de que lo rechace el backend.
const missingRequired = computed(() =>
  visibleParams.value.filter(spec => {
    if (!spec.required) return false;
    const value = params.value[spec.key] ?? spec.default;
    if (Array.isArray(value)) return value.length === 0;
    return value === undefined || value === null || value === '';
  })
);

function updateParam(key, value) {
  emit('updateParams', { ...params.value, [key]: value });
}

const testFailed = computed(() => Boolean(props.testResult?.error));

const outputPreview = computed(() => {
  if (!props.testResult) return null;
  return JSON.stringify(
    props.testResult.output ?? props.testResult.error,
    null,
    2
  );
});

// Ejemplo de salida del catálogo: sirve para saber qué se puede referenciar
// aunque el paso todavía no se haya probado.
const samplePreview = computed(() =>
  definition.value?.sampleOutput
    ? JSON.stringify(definition.value.sampleOutput, null, 2)
    : null
);
</script>

<template>
  <aside
    class="flex min-h-0 flex-col bg-n-solid-1"
    :class="
      embedded
        ? 'h-full w-full min-w-0'
        : 'w-[380px] shrink-0 border-l border-n-weak'
    "
  >
    <div
      v-if="!node"
      class="flex flex-1 flex-col items-center justify-center gap-3 px-8 text-center"
    >
      <span
        class="flex size-12 items-center justify-center rounded-2xl bg-n-alpha-2"
      >
        <span class="i-lucide-settings-2 size-6 text-n-slate-10" />
      </span>
      <p class="text-sm leading-relaxed text-n-slate-11">
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NO_SELECTION') }}
      </p>
      <p class="text-xs leading-relaxed text-n-slate-10">
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.DOUBLE_CLICK_HINT') }}
      </p>
    </div>

    <template v-else>
      <header class="border-b border-n-weak p-4">
        <div class="flex items-start gap-3">
          <span
            class="flex size-10 shrink-0 items-center justify-center rounded-xl text-white"
            :style="{ backgroundColor: definition?.color || '#64748b' }"
          >
            <span :class="icon" class="size-5" />
          </span>
          <div class="min-w-0 flex-1">
            <h3
              class="truncate text-sm font-semibold leading-tight text-n-slate-12"
            >
              {{ definition?.label || node.data.nodeType }}
            </h3>
            <span
              class="mt-1 inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-[10px] font-medium"
              :class="category.chip"
            >
              {{ category.label }}
            </span>
          </div>
          <button
            type="button"
            class="flex size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-ruby-3 hover:text-n-ruby-11"
            :title="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.DELETE_STEP')"
            @click="emit('delete')"
          >
            <span class="i-lucide-trash-2 size-4" />
          </button>
        </div>

        <p
          v-if="definition?.description"
          class="mt-3 text-xs leading-relaxed text-n-slate-11"
        >
          {{ definition.description }}
        </p>

        <!-- El detalle largo va plegado: la cabecera se lee de un vistazo. -->
        <details v-if="definition?.details" class="group mt-2">
          <summary
            class="inline-flex cursor-pointer list-none items-center gap-1 text-xs font-medium text-n-slate-11 transition-colors hover:text-n-slate-12"
          >
            <span
              class="i-lucide-chevron-right size-3.5 shrink-0 transition-transform group-open:rotate-90"
            />
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.MORE_INFO') }}
          </summary>
          <p class="mt-1.5 text-xs leading-relaxed text-n-slate-11">
            {{ definition.details }}
          </p>
        </details>

        <!-- En la vista de detalle probar el paso vive en la columna de salida. -->
        <div v-if="!embedded" class="mt-3 flex gap-2">
          <button
            type="button"
            class="inline-flex h-8 flex-1 items-center justify-center gap-1.5 rounded-lg bg-n-brand px-3 text-sm font-medium text-white transition-all hover:brightness-110 disabled:opacity-50"
            :disabled="testing"
            @click="emit('test')"
          >
            <span
              :class="
                testing
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-flask-conical'
              "
              class="size-4"
            />
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.TEST_STEP') }}
          </button>
          <button
            type="button"
            class="inline-flex h-8 items-center justify-center gap-1.5 rounded-lg px-3 text-sm font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2"
            @click="emit('runFrom')"
          >
            <span class="i-lucide-play size-4" />
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.RUN_FROM') }}
          </button>
        </div>
      </header>

      <!-- Configuración y salida en pestañas: el panel cabe sin scroll doble. -->
      <div
        v-if="!embedded"
        class="flex shrink-0 gap-1 border-b border-n-weak px-3 pt-2"
      >
        <button
          v-for="item in [
            {
              key: 'config',
              label: t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.CONFIG'),
            },
            {
              key: 'output',
              label: t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.OUTPUT'),
            },
          ]"
          :key="item.key"
          type="button"
          class="relative px-3 py-2 text-sm font-medium transition-colors"
          :class="
            tab === item.key
              ? 'text-n-slate-12'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="tab = item.key"
        >
          {{ item.label }}
          <span
            v-if="tab === item.key"
            class="absolute inset-x-2 -bottom-px h-0.5 rounded-full bg-n-brand"
          />
        </button>
      </div>

      <div class="min-h-0 flex-1 overflow-y-auto p-4">
        <template v-if="embedded || tab === 'config'">
          <div
            v-if="missingRequired.length"
            class="mb-4 flex gap-2 rounded-xl bg-n-amber-3 p-3"
          >
            <span
              class="i-lucide-triangle-alert mt-px size-4 shrink-0 text-n-amber-11"
            />
            <p class="text-xs leading-relaxed text-n-amber-11">
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.MISSING_REQUIRED') }}
              <strong>{{
                missingRequired.map(s => s.label).join(', ')
              }}</strong>
            </p>
          </div>

          <div v-if="visibleParams.length" class="flex flex-col gap-4">
            <ParamField
              v-for="spec in visibleParams"
              :key="spec.key"
              :spec="spec"
              :params="params"
              :model-value="params[spec.key] ?? spec.default ?? ''"
              @update:model-value="v => updateParam(spec.key, v)"
            />
          </div>
          <p v-else class="text-sm text-n-slate-11">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NO_CONFIG') }}
          </p>
        </template>

        <template v-else>
          <div
            v-if="outputPreview"
            class="overflow-hidden rounded-xl border"
            :class="testFailed ? 'border-n-ruby-8' : 'border-n-weak'"
          >
            <div
              class="flex items-center gap-1.5 border-b px-3 py-2 text-xs font-medium"
              :class="
                testFailed
                  ? 'border-n-ruby-8 bg-n-ruby-3 text-n-ruby-11'
                  : 'border-n-weak bg-n-alpha-2 text-n-teal-11'
              "
            >
              <span
                :class="
                  testFailed ? 'i-lucide-circle-alert' : 'i-lucide-circle-check'
                "
                class="size-3.5"
              />
              {{
                testFailed
                  ? t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.TEST_FAILED')
                  : t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.TEST_OK')
              }}
            </div>
            <pre
              class="max-h-[320px] overflow-auto p-3 font-mono text-[11px] leading-relaxed text-n-slate-12"
              >{{ outputPreview }}</pre
            >
          </div>

          <template v-else>
            <div class="flex flex-col items-center gap-2 px-4 py-8 text-center">
              <span class="i-lucide-flask-conical size-6 text-n-slate-10" />
              <p class="text-sm text-n-slate-11">
                {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NO_OUTPUT') }}
              </p>
            </div>

            <div v-if="samplePreview" class="mt-2">
              <p
                class="mb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
              >
                {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.SAMPLE_OUTPUT') }}
              </p>
              <pre
                class="max-h-[260px] overflow-auto rounded-xl border border-n-weak bg-n-alpha-2 p-3 font-mono text-[11px] leading-relaxed text-n-slate-11"
                >{{ samplePreview }}</pre
              >
            </div>
          </template>
        </template>
      </div>
    </template>
  </aside>
</template>
