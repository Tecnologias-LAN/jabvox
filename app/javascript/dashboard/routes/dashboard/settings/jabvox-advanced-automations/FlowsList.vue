<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useFlowsStore, apiError } from 'dashboard/store/jabvox/flows/flows';
import { flowStatusStyle, formatDateTime } from './composables/useFlowDesign';

// Lista de flujos de la cuenta: crear, abrir, duplicar y eliminar.
const { t } = useI18n();
const router = useRouter();
const flowsStore = useFlowsStore();

const query = ref('');
const statusFilter = ref('');
const creating = ref(false);
const newName = ref('');
const submitting = ref(false);
const pendingDelete = ref(null);
const deleting = ref(false);

const STATUSES = ['draft', 'active', 'paused', 'archived'];

const filtered = computed(() => {
  const term = query.value.trim().toLowerCase();
  return flowsStore.flows.filter(flow => {
    const matchesTerm = !term || flow.name.toLowerCase().includes(term);
    const matchesStatus =
      !statusFilter.value || flow.status === statusFilter.value;
    return matchesTerm && matchesStatus;
  });
});

// Recuento por estado para las pestañas de filtro.
function countOf(status) {
  if (!status) return flowsStore.flows.length;
  return flowsStore.flows.filter(f => f.status === status).length;
}

const hasFlows = computed(() => flowsStore.flows.length > 0);

function openFlow(flow) {
  router.push({
    name: 'jabvox_advanced_automations_editor',
    params: { flowId: flow.id },
  });
}

function startCreate() {
  creating.value = true;
  newName.value = '';
}

async function createFlow() {
  if (!newName.value.trim() || submitting.value) return;
  submitting.value = true;
  try {
    const flow = await flowsStore.create({ name: newName.value.trim() });
    newName.value = '';
    creating.value = false;
    openFlow(flow);
  } catch (e) {
    useAlert(apiError(e));
  } finally {
    submitting.value = false;
  }
}

async function duplicateFlow(flow) {
  try {
    await flowsStore.duplicate(flow.id);
  } catch (e) {
    useAlert(apiError(e));
  }
}

// Un flujo activo no se borra: el backend responde 409 y se explica por qué.
async function confirmDelete() {
  const flow = pendingDelete.value;
  if (!flow) return;
  deleting.value = true;
  try {
    await flowsStore.remove(flow.id);
    pendingDelete.value = null;
  } catch (e) {
    useAlert(
      e?.response?.status === 409
        ? t('JABVOX_ADVANCED_AUTOMATIONS.LIST.DELETE_ACTIVE')
        : apiError(e)
    );
  } finally {
    deleting.value = false;
  }
}

onMounted(() => flowsStore.fetchAll());
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Cabecera, con el mismo patrón que el resto de ajustes de Jabvox. -->
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="flex min-w-0 items-start gap-3">
          <span
            class="i-lucide-workflow size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.TITLE') }}
            </h1>
            <p class="mt-1 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.DESCRIPTION') }}
            </p>
          </div>
        </div>

        <button
          type="button"
          class="inline-flex h-10 shrink-0 items-center gap-2 rounded-lg bg-n-brand px-4 text-sm font-medium text-white transition-all hover:brightness-110"
          @click="startCreate"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.NEW') }}
        </button>
      </div>

      <!-- Filtros: buscador + estados con su recuento. -->
      <div v-if="hasFlows" class="flex flex-wrap items-center gap-3">
        <div class="relative min-w-0 flex-1 sm:max-w-xs">
          <span
            class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
          />
          <input
            v-model="query"
            type="search"
            class="!mb-0 block h-10 w-full rounded-lg border-0 bg-n-alpha-black2 !py-2 !pl-9 !pr-3 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-all placeholder:text-n-slate-10 hover:outline-n-slate-6 focus:outline-n-brand"
            :placeholder="t('JABVOX_ADVANCED_AUTOMATIONS.LIST.SEARCH')"
          />
        </div>

        <div class="flex flex-wrap gap-1">
          <button
            v-for="option in ['', ...STATUSES]"
            :key="option || 'all'"
            type="button"
            class="inline-flex h-8 items-center gap-1.5 rounded-lg px-3 text-sm font-medium transition-colors"
            :class="
              statusFilter === option
                ? 'bg-n-alpha-3 text-n-slate-12'
                : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            @click="statusFilter = option"
          >
            {{
              option
                ? t(`JABVOX_ADVANCED_AUTOMATIONS.STATUS.${option}`)
                : t('JABVOX_ADVANCED_AUTOMATIONS.LIST.ALL')
            }}
            <span class="text-xs tabular-nums text-n-slate-10">
              {{ countOf(option) }}
            </span>
          </button>
        </div>
      </div>

      <!-- Cargando -->
      <div
        v-if="flowsStore.loading && !hasFlows"
        class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3"
        aria-hidden="true"
      >
        <div
          v-for="i in 6"
          :key="i"
          class="h-32 animate-pulse rounded-2xl border border-n-weak bg-n-alpha-2"
        />
      </div>

      <!-- Error de carga -->
      <div
        v-else-if="flowsStore.error && !hasFlows"
        class="flex flex-col items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 px-6 py-14 text-center shadow-sm"
      >
        <span
          class="flex size-12 items-center justify-center rounded-2xl bg-n-ruby-3"
        >
          <span class="i-lucide-circle-alert size-6 text-n-ruby-11" />
        </span>
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.ERRORS.GENERIC') }}
        </p>
        <p class="max-w-md text-xs text-n-slate-11">{{ flowsStore.error }}</p>
        <button
          type="button"
          class="mt-1 inline-flex h-9 items-center gap-2 rounded-lg px-3 text-sm font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2"
          @click="flowsStore.fetchAll()"
        >
          <span class="i-lucide-refresh-cw size-4" />
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.RETRY') }}
        </button>
      </div>

      <!-- Vacío: sin flujos, o sin resultados para el filtro. -->
      <div
        v-else-if="!filtered.length"
        class="flex flex-col items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 px-6 py-16 text-center shadow-sm"
      >
        <span
          class="flex size-14 items-center justify-center rounded-2xl bg-n-alpha-2"
        >
          <span
            :class="hasFlows ? 'i-lucide-search-x' : 'i-lucide-workflow'"
            class="size-7 text-n-slate-10"
          />
        </span>
        <p class="max-w-sm text-sm leading-relaxed text-n-slate-11">
          {{
            hasFlows
              ? t('JABVOX_ADVANCED_AUTOMATIONS.LIST.NO_MATCHES')
              : t('JABVOX_ADVANCED_AUTOMATIONS.LIST.EMPTY')
          }}
        </p>
        <button
          v-if="!hasFlows"
          type="button"
          class="mt-1 inline-flex h-10 items-center gap-2 rounded-lg bg-n-brand px-4 text-sm font-medium text-white transition-all hover:brightness-110"
          @click="startCreate"
        >
          <span class="i-lucide-plus size-4" />
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.NEW') }}
        </button>
      </div>

      <!-- Cuadrícula de flujos -->
      <div v-else class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <article
          v-for="flow in filtered"
          :key="flow.id"
          class="group flex flex-col rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm transition-shadow hover:shadow-md"
        >
          <button
            type="button"
            class="flex flex-1 flex-col items-start gap-3 p-4 text-left"
            @click="openFlow(flow)"
          >
            <div class="flex w-full items-start gap-3">
              <span
                class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-brand"
              >
                <span class="i-lucide-workflow size-4" />
              </span>
              <div class="min-w-0 flex-1">
                <h3 class="truncate text-sm font-semibold text-n-slate-12">
                  {{ flow.name }}
                </h3>
                <p class="mt-1 truncate text-xs text-n-slate-11">
                  {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.UPDATED') }}:
                  {{ formatDateTime(flow.updatedAt) }}
                </p>
              </div>
            </div>

            <span
              class="inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-[11px] font-medium"
              :class="flowStatusStyle(flow.status).chip"
            >
              <span
                class="size-1.5 rounded-full"
                :class="flowStatusStyle(flow.status).dot"
              />
              {{ t(`JABVOX_ADVANCED_AUTOMATIONS.STATUS.${flow.status}`) }}
            </span>
          </button>

          <div
            class="flex items-center gap-1 border-t border-n-weak px-2 py-1.5"
          >
            <button
              type="button"
              class="inline-flex h-8 items-center gap-1.5 rounded-lg px-2.5 text-xs font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
              @click="openFlow(flow)"
            >
              <span class="i-lucide-pencil size-3.5" />
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.OPEN') }}
            </button>
            <button
              type="button"
              class="inline-flex h-8 items-center gap-1.5 rounded-lg px-2.5 text-xs font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
              @click="duplicateFlow(flow)"
            >
              <span class="i-lucide-copy size-3.5" />
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.DUPLICATE') }}
            </button>
            <button
              type="button"
              class="ml-auto flex size-8 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-ruby-3 hover:text-n-ruby-11"
              :title="t('JABVOX_ADVANCED_AUTOMATIONS.LIST.DELETE')"
              @click="pendingDelete = flow"
            >
              <span class="i-lucide-trash-2 size-3.5" />
            </button>
          </div>
        </article>
      </div>
    </div>

    <!-- Modal de creación -->
    <div
      v-if="creating"
      class="fixed inset-0 z-50 flex items-center justify-center bg-modal-backdrop-light p-4"
      @click.self="creating = false"
    >
      <div
        class="w-full max-w-md rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-lg"
      >
        <div class="flex items-start gap-3">
          <span
            class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-alpha-2 text-n-brand"
          >
            <span class="i-lucide-plus size-4" />
          </span>
          <h2 class="flex-1 text-base font-semibold text-n-slate-12">
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.NEW') }}
          </h2>
          <button
            type="button"
            class="flex size-7 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
            @click="creating = false"
          >
            <span class="i-lucide-x size-4" />
          </button>
        </div>

        <label
          for="jf-new-name"
          class="mt-4 block text-sm font-medium text-n-slate-12"
        >
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.FORM.NAME') }}
        </label>
        <input
          id="jf-new-name"
          v-model="newName"
          type="text"
          autofocus
          class="!mb-0 mt-1.5 block h-10 w-full rounded-lg border-0 bg-n-alpha-black2 !px-3 !py-2 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-all placeholder:text-n-slate-10 hover:outline-n-slate-6 focus:outline-n-brand"
          :placeholder="t('JABVOX_ADVANCED_AUTOMATIONS.FORM.NAME_PLACEHOLDER')"
          @keyup.enter="createFlow"
        />

        <div class="mt-5 flex justify-end gap-2">
          <button
            type="button"
            class="inline-flex h-9 items-center rounded-lg px-3 text-sm font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2"
            @click="creating = false"
          >
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.FORM.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex h-9 items-center gap-1.5 rounded-lg bg-n-brand px-3 text-sm font-medium text-white transition-all hover:brightness-110 disabled:opacity-50"
            :disabled="!newName.trim() || submitting"
            @click="createFlow"
          >
            <span
              v-if="submitting"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.FORM.CREATE') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Confirmación de borrado: sustituye al window.confirm del navegador. -->
    <div
      v-if="pendingDelete"
      class="fixed inset-0 z-50 flex items-center justify-center bg-modal-backdrop-light p-4"
      @click.self="pendingDelete = null"
    >
      <div
        class="w-full max-w-md rounded-2xl border border-n-weak bg-n-solid-1 p-5 shadow-lg"
      >
        <div class="flex items-start gap-3">
          <span
            class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-n-ruby-3"
          >
            <span class="i-lucide-triangle-alert size-4 text-n-ruby-11" />
          </span>
          <div class="min-w-0 flex-1">
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.DELETE') }}
            </h2>
            <p class="mt-1.5 text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.DELETE_CONFIRM') }}
            </p>
            <p class="mt-2 truncate text-sm font-medium text-n-slate-12">
              {{ pendingDelete.name }}
            </p>
          </div>
        </div>

        <div class="mt-5 flex justify-end gap-2">
          <button
            type="button"
            class="inline-flex h-9 items-center rounded-lg px-3 text-sm font-medium text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak transition-colors hover:bg-n-alpha-2"
            @click="pendingDelete = null"
          >
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.FORM.CANCEL') }}
          </button>
          <button
            type="button"
            class="inline-flex h-9 items-center gap-1.5 rounded-lg bg-n-ruby-9 px-3 text-sm font-medium text-white transition-all hover:bg-n-ruby-10 disabled:opacity-50"
            :disabled="deleting"
            @click="confirmDelete"
          >
            <span
              v-if="deleting"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
            {{ t('JABVOX_ADVANCED_AUTOMATIONS.LIST.DELETE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
