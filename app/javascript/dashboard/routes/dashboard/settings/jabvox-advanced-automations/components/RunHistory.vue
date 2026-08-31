<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { flowsAPI, runsAPI } from 'dashboard/api/jabvox/flows';
import {
  runStatusStyle,
  formatDuration,
  formatDateTime,
} from '../composables/useFlowDesign';

// Historial de ejecuciones del flujo, con el detalle por paso al desplegar.
const props = defineProps({
  flowId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const runs = ref([]);
const detail = ref(null);
const openId = ref(null);
const loading = ref(true);
const loadingDetail = ref(false);
const collapsed = ref(false);

async function load() {
  loading.value = true;
  try {
    const { data } = await flowsAPI.listRuns(props.flowId, 15);
    runs.value = data;
  } finally {
    loading.value = false;
  }
}

async function toggle(runId) {
  if (openId.value === runId) {
    openId.value = null;
    return;
  }
  openId.value = runId;
  detail.value = null;
  loadingDetail.value = true;
  try {
    const { data } = await runsAPI.get(runId);
    detail.value = data;
  } finally {
    loadingDetail.value = false;
  }
}

onMounted(load);
watch(() => props.flowId, load);
defineExpose({ load });
</script>

<template>
  <section class="shrink-0 border-t border-n-weak bg-n-solid-1">
    <div class="flex items-center gap-2 px-4 py-2.5">
      <button
        type="button"
        class="flex min-w-0 flex-1 items-center gap-2 text-left"
        @click="collapsed = !collapsed"
      >
        <span
          class="i-lucide-chevron-up size-4 shrink-0 text-n-slate-10 transition-transform"
          :class="{ 'rotate-180': collapsed }"
        />
        <span class="i-lucide-history size-4 shrink-0 text-n-slate-11" />
        <h4
          class="text-xs font-semibold uppercase tracking-wide text-n-slate-11"
        >
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.RUNS.TITLE') }}
        </h4>
        <span
          v-if="runs.length"
          class="rounded-md bg-n-alpha-2 px-1.5 py-0.5 text-[10px] tabular-nums text-n-slate-11"
        >
          {{ runs.length }}
        </span>
      </button>
      <button
        type="button"
        class="flex size-7 items-center justify-center rounded-lg text-n-slate-11 transition-colors hover:bg-n-alpha-2"
        :title="t('JABVOX_ADVANCED_AUTOMATIONS.RUNS.REFRESH')"
        @click="load"
      >
        <span
          class="i-lucide-refresh-cw size-3.5"
          :class="{ 'animate-spin': loading }"
        />
      </button>
    </div>

    <div v-if="!collapsed" class="max-h-[230px] overflow-y-auto px-2 pb-2">
      <div v-if="loading" class="flex flex-col gap-1.5 p-2" aria-hidden="true">
        <div
          v-for="i in 3"
          :key="i"
          class="h-9 animate-pulse rounded-lg bg-n-alpha-2"
        />
      </div>

      <div
        v-else-if="!runs.length"
        class="flex flex-col items-center gap-2 px-4 py-6 text-center"
      >
        <span class="i-lucide-history size-5 text-n-slate-10" />
        <p class="text-sm text-n-slate-11">
          {{ t('JABVOX_ADVANCED_AUTOMATIONS.RUNS.EMPTY') }}
        </p>
      </div>

      <template v-else>
        <div v-for="run in runs" :key="run.id">
          <button
            type="button"
            class="flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors hover:bg-n-alpha-2"
            @click="toggle(run.id)"
          >
            <span
              class="inline-flex shrink-0 items-center gap-1 rounded-md px-1.5 py-0.5 text-[10px] font-medium"
              :class="runStatusStyle(run.status).chip"
            >
              <span
                :class="[
                  runStatusStyle(run.status).icon,
                  { 'animate-spin': runStatusStyle(run.status).spin },
                ]"
                class="size-3"
              />
              {{ t(`JABVOX_ADVANCED_AUTOMATIONS.RUNS.STATUS.${run.status}`) }}
            </span>
            <span class="min-w-0 flex-1 truncate text-xs text-n-slate-11">
              {{ formatDateTime(run.startedAt || run.createdAt) }}
            </span>
            <span class="shrink-0 text-xs tabular-nums text-n-slate-11">
              {{ formatDuration(run.durationMs) }}
            </span>
            <span
              v-if="run.error"
              class="i-lucide-circle-alert size-3.5 shrink-0 text-n-ruby-11"
              :title="run.error"
            />
            <span
              class="i-lucide-chevron-down size-3.5 shrink-0 text-n-slate-10 transition-transform"
              :class="{ 'rotate-180': openId === run.id }"
            />
          </button>

          <div v-if="openId === run.id" class="mb-1 ml-2 pl-4">
            <p
              v-if="loadingDetail"
              class="flex items-center gap-1.5 py-2 text-xs text-n-slate-11"
            >
              <span class="i-lucide-loader-circle size-3.5 animate-spin" />
              {{ t('JABVOX_ADVANCED_AUTOMATIONS.RUNS.LOADING_DETAIL') }}
            </p>
            <ul
              v-else-if="detail"
              class="flex flex-col gap-1 border-l border-n-weak py-1 pl-3"
            >
              <li
                v-for="step in detail.steps"
                :key="step.id"
                class="flex items-center gap-2 text-xs"
              >
                <span
                  :class="[
                    runStatusStyle(step.status).icon,
                    runStatusStyle(step.status).text,
                  ]"
                  class="size-3 shrink-0"
                />
                <span class="min-w-0 flex-1 truncate text-n-slate-12">
                  {{ step.label || step.nodeId }}
                </span>
                <span class="shrink-0 tabular-nums text-n-slate-11">
                  {{ formatDuration(step.durationMs) }}
                </span>
              </li>
            </ul>
            <p
              v-if="detail && run.error"
              class="mt-1 rounded-lg bg-n-ruby-3 px-2 py-1.5 text-xs text-n-ruby-11"
            >
              {{ run.error }}
            </p>
          </div>
        </div>
      </template>
    </div>
  </section>
</template>
