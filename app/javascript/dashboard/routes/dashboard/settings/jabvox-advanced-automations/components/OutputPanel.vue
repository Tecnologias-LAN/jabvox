<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNodesStore } from 'dashboard/store/jabvox/flows/nodes';
import DataPanel from './DataPanel.vue';

// Panel de SALIDA: lo que devuelve ESTE paso, con el botón de probarlo. Si aún
// no se ha probado, se muestra el ejemplo del catálogo, que sirve para saber
// qué se podrá referenciar.
const props = defineProps({
  node: { type: Object, required: true },
  // Resultado de la última prueba del paso: { output, outputContract, error }.
  testResult: { type: Object, default: null },
  testing: { type: Boolean, default: false },
});

const emit = defineEmits(['test', 'runFrom']);

const { t } = useI18n();
const nodesStore = useNodesStore();

const definition = computed(() =>
  nodesStore.getDefinition(props.node.data.nodeType)
);

const failed = computed(() => Boolean(props.testResult?.error));

// La referencia se construye contra ESTE paso: es lo que se citará en los
// siguientes. `itemsPath` decide si `output` es un elemento.
const origin = computed(() => ({ kind: 'node', nodeId: props.node.id }));
const itemsPath = computed(() => definition.value?.itemsPath);

// Salida real de la prueba; si no hay, el EJEMPLO del catálogo.
const shown = computed(() => {
  if (props.testResult && !failed.value) {
    return {
      payload: props.testResult.output,
      contract: props.testResult.outputContract ?? null,
      source: t('JABVOX_ADVANCED_AUTOMATIONS.OUTPUT.SOURCE_TEST'),
      isSample: false,
    };
  }
  if (definition.value?.sampleOutput) {
    return {
      payload: definition.value.sampleOutput,
      contract: null,
      source: t('JABVOX_ADVANCED_AUTOMATIONS.OUTPUT.SOURCE_SAMPLE'),
      isSample: true,
    };
  }
  return null;
});
</script>

<template>
  <section class="flex h-full min-h-0 flex-col bg-n-solid-1">
    <header
      class="flex shrink-0 items-center gap-2 border-b border-n-weak px-3 py-2.5"
    >
      <span class="i-lucide-log-out size-4 shrink-0 text-n-slate-11" />
      <h3 class="text-xs font-semibold uppercase tracking-wide text-n-slate-11">
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.OUTPUT') }}
      </h3>
      <div class="ml-auto flex shrink-0 items-center gap-1.5">
        <button
          type="button"
          class="inline-flex h-7 items-center gap-1.5 rounded-lg px-2.5 text-xs font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2"
          :title="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.RUN_FROM')"
          @click="emit('runFrom')"
        >
          <span class="i-lucide-play size-3.5" />
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.RUN_FROM') }}
        </button>
        <button
          type="button"
          class="inline-flex h-7 items-center gap-1.5 rounded-lg bg-n-brand px-2.5 text-xs font-medium text-white transition-all hover:brightness-110 disabled:opacity-50"
          :disabled="testing"
          @click="emit('test')"
        >
          <span
            :class="
              testing
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-lucide-flask-conical'
            "
            class="size-3.5"
          />
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.TEST_STEP') }}
        </button>
      </div>
    </header>

    <!-- Un fallo de la prueba se lee entero: es el motivo por el que no avanza. -->
    <div v-if="failed" class="min-h-0 flex-1 overflow-y-auto bg-n-ruby-3 p-3">
      <p
        class="mb-2 flex items-center gap-1.5 text-xs font-semibold text-n-ruby-11"
      >
        <span class="i-lucide-circle-alert size-3.5 shrink-0" />
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.OUTPUT.TEST_FAILED') }}
      </p>
      <pre
        class="whitespace-pre-wrap font-mono text-[11px] leading-relaxed text-n-ruby-11"
        >{{ testResult.error }}</pre
      >
    </div>

    <!-- La salida propia no se arrastra: se cita desde los pasos SIGUIENTES. -->
    <DataPanel
      v-else-if="shown"
      :payload="shown.payload"
      :contract="shown.contract"
      :items-path="itemsPath"
      :origin="origin"
      :source="shown.source"
      :is-sample="shown.isSample"
      no-drag
    />

    <div
      v-else
      class="flex flex-1 flex-col items-center justify-center gap-2 px-6 text-center"
    >
      <span class="i-lucide-flask-conical size-6 text-n-slate-10" />
      <p class="text-sm text-n-slate-11">
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.NO_OUTPUT') }}
      </p>
    </div>
  </section>
</template>
