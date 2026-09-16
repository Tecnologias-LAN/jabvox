<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useJabvoxPermissions } from 'dashboard/composables/useJabvoxPermissions';
import { wfFlowsAPI } from 'dashboard/api/jabvox/whatsappFlows';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const router = useRouter();
const { jabvoxCan } = useJabvoxPermissions();

const canManage = computed(() => jabvoxCan('jabvox_whatsapp_flows_manage'));

const flows = ref([]);
const total = ref(0);
const loading = ref(false);
const page = ref(1);
const perPage = 20;
const totalPages = computed(() => Math.ceil(total.value / perPage) || 1);

const statusFilter = ref('');

const loadFlows = async () => {
  loading.value = true;
  try {
    const { data } = await wfFlowsAPI.getAll({
      page: page.value,
      per_page: perPage,
      ...(statusFilter.value ? { status: statusFilter.value } : {}),
    });
    flows.value = data.flows || [];
    total.value = data.total || 0;
  } catch {
    useAlert(t('JABVOX_WA_FLOWS.LIST.ERROR'));
  } finally {
    loading.value = false;
  }
};

onMounted(loadFlows);

const changePage = delta => {
  const n = page.value + delta;
  if (n < 1 || n > totalPages.value) return;
  page.value = n;
  loadFlows();
};

const applyStatusFilter = status => {
  statusFilter.value = statusFilter.value === status ? '' : status;
  page.value = 1;
  loadFlows();
};

const createFlow = () => {
  router.push({
    name: 'jabvox_whatsapp_flows_builder',
    params: { flowId: 'new' },
  });
};

const openFlow = flow => {
  router.push({
    name: 'jabvox_whatsapp_flows_builder',
    params: { flowId: flow.id },
  });
};

const duplicateFlow = async flow => {
  try {
    await wfFlowsAPI.duplicate(flow.id);
    useAlert(t('JABVOX_WA_FLOWS.LIST.DUPLICATED'));
    loadFlows();
  } catch {
    useAlert(t('JABVOX_WA_FLOWS.LIST.ERROR'));
  }
};

const syncFlow = async flow => {
  try {
    await wfFlowsAPI.sync(flow.id);
    useAlert(t('JABVOX_WA_FLOWS.LIST.SYNCED'));
    loadFlows();
  } catch {
    useAlert(t('JABVOX_WA_FLOWS.LIST.ERROR'));
  }
};

const publishFlow = async flow => {
  try {
    await wfFlowsAPI.publish(flow.id);
    useAlert(t('JABVOX_WA_FLOWS.LIST.PUBLISHED'));
    loadFlows();
  } catch (err) {
    // El backend responde 422 con { error, errors } cuando la validación
    // local o la publicación en Meta fallan — el detalle campo a campo solo
    // se revisa en el builder (pestaña Validación), aquí solo el mensaje.
    useAlert(err?.response?.data?.error || t('JABVOX_WA_FLOWS.LIST.ERROR'));
  }
};

const confirmDialog = ref(null);

const askDelete = flow => {
  confirmDialog.value?.open({
    title: t('JABVOX_WA_FLOWS.LIST.DELETE_CONFIRM_TITLE'),
    description: t('JABVOX_WA_FLOWS.LIST.DELETE_CONFIRM_BODY', {
      name: flow.name,
    }),
    data: { action: 'delete', flow },
  });
};

const onConfirm = async data => {
  if (data?.action === 'delete') {
    try {
      await wfFlowsAPI.delete(data.flow.id);
      useAlert(t('JABVOX_WA_FLOWS.LIST.DELETED'));
      loadFlows();
    } catch (err) {
      useAlert(err?.response?.data?.error || t('JABVOX_WA_FLOWS.LIST.ERROR'));
    }
  }
};

// Métricas rápidas (solo lo que el backend realmente calcula — sección 20 de
// la arquitectura: sent/completed/completion_rate, nada inventado).
const metricsOpenFor = ref(null);
const metricsData = ref(null);
const loadingMetrics = ref(false);

const openMetrics = async flow => {
  metricsOpenFor.value = flow;
  metricsData.value = null;
  loadingMetrics.value = true;
  try {
    const { data } = await wfFlowsAPI.metrics(flow.id);
    metricsData.value = data;
  } catch {
    useAlert(t('JABVOX_WA_FLOWS.LIST.ERROR'));
  } finally {
    loadingMetrics.value = false;
  }
};

const closeMetrics = () => {
  metricsOpenFor.value = null;
  metricsData.value = null;
};

const STATUS_LABELS = {
  draft: 'JABVOX_WA_FLOWS.STATUS.DRAFT',
  validating: 'JABVOX_WA_FLOWS.STATUS.VALIDATING',
  ready: 'JABVOX_WA_FLOWS.STATUS.READY',
  published: 'JABVOX_WA_FLOWS.STATUS.PUBLISHED',
  sync_failed: 'JABVOX_WA_FLOWS.STATUS.SYNC_FAILED',
};
const statusLabel = s =>
  t(STATUS_LABELS[s] || s || 'JABVOX_WA_FLOWS.STATUS.DRAFT');

const statusClass = s => {
  switch (s) {
    case 'published':
      return 'bg-n-teal-11/15 text-n-teal-11 ring-1 ring-inset ring-n-teal-11/30';
    case 'ready':
      return 'bg-n-brand/15 text-n-brand ring-1 ring-inset ring-n-brand/30';
    case 'validating':
      return 'bg-n-amber-11/15 text-n-amber-11 ring-1 ring-inset ring-n-amber-11/30';
    case 'sync_failed':
      return 'bg-n-ruby-11/15 text-n-ruby-11 ring-1 ring-inset ring-n-ruby-11/30';
    default:
      return 'bg-n-alpha-2 text-n-slate-11 ring-1 ring-inset ring-n-weak';
  }
};

const metaStatusClass = s => {
  switch (s) {
    case 'PUBLISHED':
      return 'text-n-teal-11';
    case 'BLOCKED':
    case 'THROTTLED':
      return 'text-n-ruby-11';
    case 'DEPRECATED':
      return 'text-n-slate-9';
    default:
      return 'text-n-slate-10';
  }
};

const statusQuickFilters = ['draft', 'ready', 'published', 'sync_failed'];
</script>

<template>
  <div class="flex flex-col flex-1 h-full overflow-hidden">
    <div
      class="sticky top-0 z-10 bg-n-background border-b border-n-weak px-4 sm:px-6 py-4 shrink-0"
    >
      <div
        class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4"
      >
        <div>
          <h1 class="text-xl sm:text-2xl font-semibold text-n-slate-12">
            {{ t('JABVOX_WA_FLOWS.LIST.HEADER.TITLE') }}
          </h1>
          <p class="text-xs sm:text-sm text-n-slate-10 mt-1 max-w-2xl">
            {{ t('JABVOX_WA_FLOWS.LIST.HEADER.SUBTITLE') }}
          </p>
        </div>
        <button
          v-if="canManage"
          class="inline-flex items-center gap-1.5 px-3.5 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 transition-opacity shrink-0 self-start"
          @click="createFlow"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
          {{ t('JABVOX_WA_FLOWS.LIST.HEADER.CREATE') }}
        </button>
      </div>

      <div class="flex items-center gap-2 flex-wrap mt-4">
        <button
          v-for="s in statusQuickFilters"
          :key="s"
          class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs border transition-all"
          :class="
            statusFilter === s
              ? 'border-n-brand bg-n-brand text-white shadow-sm'
              : 'border-n-weak text-n-slate-11 bg-n-solid-1 hover:bg-n-alpha-1 hover:border-n-strong'
          "
          @click="applyStatusFilter(s)"
        >
          {{ statusLabel(s) }}
        </button>
      </div>
    </div>

    <div class="flex-1 overflow-y-auto px-4 sm:px-6 py-4">
      <div
        v-if="loading"
        class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
      >
        <div
          v-for="n in 6"
          :key="n"
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 animate-pulse"
        >
          <div class="h-4 w-2/3 bg-n-alpha-2 rounded mb-2" />
          <div class="h-3 w-1/2 bg-n-alpha-2 rounded mb-4" />
          <div class="h-20 bg-n-alpha-2 rounded-xl" />
        </div>
      </div>

      <div
        v-else-if="!flows.length"
        class="rounded-2xl border border-dashed border-n-weak bg-n-solid-1 py-20 text-center"
      >
        <div
          class="mx-auto mb-4 flex items-center justify-center size-16 rounded-2xl bg-n-background border border-n-weak"
        >
          <span
            class="i-lucide-layout-list size-7 text-n-brand"
            aria-hidden="true"
          />
        </div>
        <p class="text-base font-semibold text-n-slate-12">
          {{ t('JABVOX_WA_FLOWS.LIST.EMPTY_TITLE') }}
        </p>
        <p class="text-sm text-n-slate-10 mt-1.5 max-w-md mx-auto">
          {{ t('JABVOX_WA_FLOWS.LIST.EMPTY_BODY') }}
        </p>
        <button
          v-if="canManage"
          class="mt-5 px-4 py-2 text-sm rounded-xl inline-flex items-center gap-1.5 bg-n-brand text-white hover:opacity-90"
          @click="createFlow"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
          {{ t('JABVOX_WA_FLOWS.LIST.EMPTY_CTA') }}
        </button>
      </div>

      <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <article
          v-for="flow in flows"
          :key="flow.id"
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 hover:border-n-strong hover:-translate-y-0.5 transition-all shadow-sm"
        >
          <div class="flex items-start justify-between gap-2 mb-2">
            <span
              class="inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-full"
              :class="statusClass(flow.status)"
            >
              {{ statusLabel(flow.status) }}
            </span>
            <span
              v-if="flow.meta_status"
              class="text-[11px] font-medium"
              :class="metaStatusClass(flow.meta_status)"
            >
              {{ flow.meta_status }}
            </span>
          </div>

          <button class="w-full text-left" @click="openFlow(flow)">
            <h3 class="text-sm font-semibold text-n-slate-12 truncate">
              {{ flow.name }}
            </h3>
            <p class="text-xs text-n-slate-10 mt-0.5">
              {{ flow.inbox_name || t('JABVOX_WA_FLOWS.LIST.NO_INBOX') }} ·
              {{ t(`JABVOX_WA_FLOWS.CATEGORIES.${flow.category}`) }}
            </p>
            <p
              v-if="flow.description"
              class="text-xs text-n-slate-10 mt-2 line-clamp-2"
            >
              {{ flow.description }}
            </p>
          </button>

          <div class="mt-3 flex items-center gap-1 flex-wrap">
            <button
              class="wf-list-icon-btn"
              :title="t('JABVOX_WA_FLOWS.LIST.ACTIONS.OPEN')"
              @click="openFlow(flow)"
            >
              <span class="i-lucide-pencil size-3.5" aria-hidden="true" />
            </button>
            <button
              class="wf-list-icon-btn"
              :title="t('JABVOX_WA_FLOWS.LIST.ACTIONS.METRICS')"
              @click="openMetrics(flow)"
            >
              <span class="i-lucide-bar-chart-3 size-3.5" aria-hidden="true" />
            </button>
            <template v-if="canManage">
              <button
                class="wf-list-icon-btn"
                :title="t('JABVOX_WA_FLOWS.LIST.ACTIONS.DUPLICATE')"
                @click="duplicateFlow(flow)"
              >
                <span class="i-lucide-copy size-3.5" aria-hidden="true" />
              </button>
              <button
                v-if="flow.meta_flow_id"
                class="wf-list-icon-btn"
                :title="t('JABVOX_WA_FLOWS.LIST.ACTIONS.SYNC')"
                @click="syncFlow(flow)"
              >
                <span class="i-lucide-refresh-cw size-3.5" aria-hidden="true" />
              </button>
              <button
                v-if="flow.status !== 'published'"
                class="wf-list-icon-btn"
                :title="t('JABVOX_WA_FLOWS.LIST.ACTIONS.PUBLISH')"
                @click="publishFlow(flow)"
              >
                <span class="i-lucide-rocket size-3.5" aria-hidden="true" />
              </button>
              <button
                v-if="flow.status !== 'published'"
                class="wf-list-icon-btn hover:!text-n-ruby-11"
                :title="t('JABVOX_WA_FLOWS.LIST.ACTIONS.DELETE')"
                @click="askDelete(flow)"
              >
                <span class="i-lucide-trash-2 size-3.5" aria-hidden="true" />
              </button>
            </template>
          </div>
        </article>
      </div>

      <div
        v-if="flows.length"
        class="flex items-center justify-center gap-3 mt-6"
      >
        <button
          class="wf-list-icon-btn"
          :disabled="page <= 1"
          @click="changePage(-1)"
        >
          <span class="i-lucide-chevron-left size-4" aria-hidden="true" />
        </button>
        <span class="text-xs text-n-slate-10">
          {{ page }} / {{ totalPages }}
        </span>
        <button
          class="wf-list-icon-btn"
          :disabled="page >= totalPages"
          @click="changePage(1)"
        >
          <span class="i-lucide-chevron-right size-4" aria-hidden="true" />
        </button>
      </div>
    </div>

    <!-- Metrics drawer (simple modal) -->
    <div
      v-if="metricsOpenFor"
      class="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4"
      @click.self="closeMetrics"
    >
      <div
        class="w-full max-w-md rounded-2xl bg-n-solid-1 border border-n-weak p-5 shadow-xl"
      >
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-sm font-semibold text-n-slate-12">
            {{
              t('JABVOX_WA_FLOWS.LIST.METRICS.TITLE', {
                name: metricsOpenFor.name,
              })
            }}
          </h3>
          <button class="wf-list-icon-btn" @click="closeMetrics">
            <span class="i-lucide-x size-4" aria-hidden="true" />
          </button>
        </div>

        <div v-if="loadingMetrics" class="py-8 text-center">
          <span
            class="i-lucide-loader-2 animate-spin size-5 text-n-slate-9"
            aria-hidden="true"
          />
        </div>

        <div v-else-if="metricsData" class="grid grid-cols-2 gap-3">
          <!-- Solo lo que el backend realmente calcula desde las submissions
               registradas (Meta no expone un contador de "enviados" por Flow
               vía Graph API) — nada inventado. -->
          <div class="rounded-xl border border-n-weak p-3 text-center">
            <p class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_WA_FLOWS.LIST.METRICS.TOTAL_SUBMISSIONS') }}
            </p>
            <p class="text-xl font-semibold text-n-slate-12">
              {{ metricsData.total_submissions ?? 0 }}
            </p>
          </div>
          <div class="rounded-xl border border-n-weak p-3 text-center">
            <p class="text-[11px] text-n-slate-10">
              {{ t('JABVOX_WA_FLOWS.LIST.METRICS.LAST_SUBMISSION') }}
            </p>
            <p class="text-sm font-semibold text-n-slate-12">
              {{
                metricsData.last_submission_at
                  ? new Date(metricsData.last_submission_at).toLocaleString()
                  : t('JABVOX_WA_FLOWS.LIST.METRICS.NONE_YET')
              }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="onConfirm" />
  </div>
</template>

<style scoped>
.wf-list-icon-btn {
  padding: 6px;
  border-radius: 8px;
  color: var(--color-body);
  transition:
    background 0.18s ease,
    color 0.18s ease;
}
.wf-list-icon-btn:hover:not(:disabled) {
  background: var(--color-background);
  color: var(--color-heading);
}
.wf-list-icon-btn:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}
</style>
