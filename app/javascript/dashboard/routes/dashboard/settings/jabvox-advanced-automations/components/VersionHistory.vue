<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFlowsStore, apiError } from 'dashboard/store/jabvox/flows/flows';
import { formatDateTime } from '../composables/useFlowDesign';

// Historial de versiones del flujo: listar, previsualizar y restaurar. El
// backend nunca reescribe una versión, así que restaurar solo AÑADE otra.
const props = defineProps({
  flowId: { type: [String, Number], required: true },
});

const emit = defineEmits(['close', 'restored']);

const { t } = useI18n();
const flowsStore = useFlowsStore();

const items = ref([]);
const loading = ref(true);
const error = ref(null);

// Versión abierta en previsualización, con su grafo ya cargado.
const previewOf = ref(null);
const preview = ref(null);
const loadingPreview = ref(false);

// Versión pendiente de confirmación para restaurar.
const pendingRestore = ref(null);
const restoring = ref(false);

const currentNumber = computed(
  () => items.value.find(v => v.isCurrent)?.version ?? null
);

async function load() {
  loading.value = true;
  error.value = null;
  try {
    items.value = await flowsStore.fetchVersions(props.flowId);
  } catch (e) {
    error.value = apiError(e);
  } finally {
    loading.value = false;
  }
}

async function togglePreview(version) {
  if (previewOf.value === version) {
    previewOf.value = null;
    preview.value = null;
    return;
  }
  previewOf.value = version;
  preview.value = null;
  loadingPreview.value = true;
  try {
    preview.value = await flowsStore.fetchVersion(props.flowId, version);
  } catch (e) {
    error.value = apiError(e);
    previewOf.value = null;
  } finally {
    loadingPreview.value = false;
  }
}

// Pasos de la versión previsualizada, con la etiqueta que guardó el editor.
const previewSteps = computed(() => {
  const nodes = preview.value?.graph?.nodes ?? [];
  return nodes.map(n => ({
    id: n.id,
    label: n.data?.label || n.id,
    type: n.type || n.data?.nodeType || '',
  }));
});

async function confirmRestore() {
  const target = pendingRestore.value;
  if (!target) return;
  restoring.value = true;
  try {
    const created = await flowsStore.restoreVersion(
      props.flowId,
      target.version
    );
    pendingRestore.value = null;
    previewOf.value = null;
    preview.value = null;
    await load();
    // El editor recarga su lienzo con el grafo restaurado.
    emit('restored', created);
  } catch (e) {
    error.value = apiError(e);
  } finally {
    restoring.value = false;
  }
}

onMounted(load);
watch(() => props.flowId, load);
defineExpose({ load });
</script>

<template>
  <aside
    class="flex w-full max-w-sm shrink-0 flex-col border-l border-n-weak bg-n-solid-1"
  >
    <header
      class="flex shrink-0 items-center gap-2 border-b border-n-weak px-4 py-2.5"
    >
      <span
        class="i-lucide-git-commit-vertical size-4 shrink-0 text-n-slate-11"
      />
      <h3
        class="min-w-0 flex-1 truncate text-xs font-semibold uppercase tracking-wide text-n-slate-11"
      >
        {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.TITLE') }}
      </h3>
      <button
        type="button"
        class="flex size-7 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.REFRESH')"
        @click="load"
      >
        <span
          class="i-lucide-refresh-cw size-3.5"
          :class="{ 'animate-spin': loading }"
        />
      </button>
      <button
        type="button"
        class="flex size-7 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.EDITOR.CLOSE')"
        @click="emit('close')"
      >
        <span class="i-lucide-x size-3.5" />
      </button>
    </header>

    <div class="min-h-0 flex-1 overflow-y-auto px-2 py-2">
      <div v-if="loading" class="flex flex-col gap-1.5 p-2" aria-hidden="true">
        <div
          v-for="i in 4"
          :key="i"
          class="h-12 animate-pulse rounded-lg bg-n-alpha-2"
        />
      </div>

      <div
        v-else-if="error"
        class="m-2 flex items-start gap-2 rounded-lg bg-n-ruby-3 px-3 py-2.5"
      >
        <span
          class="i-lucide-circle-alert mt-0.5 size-4 shrink-0 text-n-ruby-11"
        />
        <p class="min-w-0 flex-1 text-xs leading-relaxed text-n-ruby-11">
          {{ error }}
        </p>
      </div>

      <div
        v-else-if="!items.length"
        class="flex flex-col items-center gap-2 px-4 py-8 text-center"
      >
        <span class="i-lucide-git-commit-vertical size-5 text-n-slate-10" />
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.EMPTY') }}
        </p>
      </div>

      <template v-else>
        <article
          v-for="item in items"
          :key="item.id"
          class="mb-1 rounded-xl transition-colors"
          :class="
            item.isCurrent ? 'bg-n-alpha-1 ring-1 ring-inset ring-n-weak' : ''
          "
        >
          <div class="flex items-start gap-2.5 px-2.5 py-2">
            <span
              class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-lg text-[11px] font-semibold tabular-nums"
              :class="
                item.isCurrent
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              {{ item.version }}
            </span>

            <div class="min-w-0 flex-1">
              <p class="flex items-center gap-1.5 text-xs text-n-slate-12">
                <span class="truncate font-medium">
                  {{
                    item.createdByName ||
                    t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.UNKNOWN_AUTHOR')
                  }}
                </span>
                <span
                  v-if="item.isCurrent"
                  class="shrink-0 rounded-md bg-n-teal-3 px-1.5 py-0.5 text-[10px] font-medium text-n-teal-11"
                >
                  {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.CURRENT') }}
                </span>
              </p>
              <p class="mt-0.5 text-[11px] text-n-slate-11">
                {{ formatDateTime(item.createdAt) }}
              </p>
              <p class="mt-0.5 text-[11px] tabular-nums text-n-slate-10">
                {{
                  t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.COUNTS', {
                    nodes: item.nodeCount,
                    edges: item.edgeCount,
                  })
                }}
              </p>
            </div>

            <div class="flex shrink-0 items-center gap-0.5">
              <button
                type="button"
                class="flex size-7 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
                :title="t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.PREVIEW')"
                @click="togglePreview(item.version)"
              >
                <span
                  class="i-lucide-eye size-3.5"
                  :class="{ 'text-n-brand': previewOf === item.version }"
                />
              </button>
              <button
                v-if="!item.isCurrent"
                type="button"
                class="flex size-7 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
                :title="t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE')"
                @click="pendingRestore = item"
              >
                <span class="i-lucide-rotate-ccw size-3.5" />
              </button>
            </div>
          </div>

          <!-- Previsualización: qué pasos contenía esa versión, sin tocar el lienzo. -->
          <div
            v-if="previewOf === item.version"
            class="mx-2.5 mb-2 rounded-lg bg-n-alpha-1 px-2.5 py-2"
          >
            <p
              v-if="loadingPreview"
              class="flex items-center gap-1.5 text-[11px] text-n-slate-11"
            >
              <span class="i-lucide-loader-circle size-3 animate-spin" />
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.LOADING_PREVIEW') }}
            </p>
            <template v-else-if="preview">
              <p
                class="mb-1.5 text-[10px] font-semibold uppercase tracking-wide text-n-slate-10"
              >
                {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.PREVIEW_TITLE') }}
              </p>
              <p
                v-if="!previewSteps.length"
                class="text-[11px] text-n-slate-11"
              >
                {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.PREVIEW_EMPTY') }}
              </p>
              <ul v-else class="flex flex-col gap-1">
                <li
                  v-for="step in previewSteps"
                  :key="step.id"
                  class="flex items-center gap-1.5 text-[11px]"
                >
                  <span class="i-lucide-box size-3 shrink-0 text-n-slate-10" />
                  <span class="min-w-0 flex-1 truncate text-n-slate-12">
                    {{ step.label }}
                  </span>
                  <span class="shrink-0 truncate text-n-slate-10">
                    {{ step.type }}
                  </span>
                </li>
              </ul>
            </template>
          </div>
        </article>
      </template>
    </div>

    <!-- Confirmación de restauración: modal propio, no el confirm del navegador. -->
    <div
      v-if="pendingRestore"
      class="fixed inset-0 z-50 flex items-center justify-center bg-modal-backdrop-light p-4"
      @click.self="pendingRestore = null"
    >
      <div
        class="w-full max-w-md rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-lg"
      >
        <div class="flex items-start gap-3">
          <span
            class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-amber-3"
          >
            <span class="i-lucide-rotate-ccw size-4 text-n-amber-11" />
          </span>
          <div class="min-w-0 flex-1">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE_TITLE') }}
            </h2>
            <p class="mt-1.5 text-sm leading-relaxed text-n-slate-11">
              {{
                t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE_CONFIRM', {
                  version: pendingRestore.version,
                  current: currentNumber ?? '—',
                })
              }}
            </p>
            <p class="mt-2 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE_KEEPS') }}
            </p>
            <p class="mt-2 text-sm font-medium leading-relaxed text-n-amber-11">
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE_LOSES') }}
            </p>
          </div>
        </div>

        <div class="mt-5 flex justify-end gap-2">
          <button
            type="button"
            class="inline-flex h-9 items-center rounded-lg px-3 text-sm font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2"
            @click="pendingRestore = null"
          >
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.FORM.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex h-9 items-center gap-1.5 rounded-lg bg-n-brand px-3 text-sm font-medium text-white transition-all hover:brightness-110 disabled:opacity-50"
            :disabled="restoring"
            @click="confirmRestore"
          >
            <span
              v-if="restoring"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.VERSIONS.RESTORE') }}
          </button>
        </div>
      </div>
    </div>
  </aside>
</template>
