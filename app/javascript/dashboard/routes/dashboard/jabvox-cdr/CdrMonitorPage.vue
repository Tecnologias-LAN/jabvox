<script setup>
import { ref, onMounted, onBeforeUnmount, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { cdrReportsAPI } from 'dashboard/api/jabvox/cdr';

const router = useRouter();
const { t } = useI18n();
const state = ref(null);
const loading = ref(false);
const errored = ref(false);
const REFRESH_MS = 15000;
let timer = null;

const load = async () => {
  loading.value = true;
  try {
    const { data } = await cdrReportsAPI.monitor();
    state.value = data;
    errored.value = false;
  } catch (e) {
    if (e?.response?.status === 403) {
      router.replace({ name: 'home' });
      return;
    }
    errored.value = true;
  } finally {
    loading.value = false;
  }
};

const DASH = '—';
const fmtDate = v => {
  if (!v) return DASH;
  return new Date(v).toLocaleString('es-CO', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
};
const fmtMs = ms => (ms == null ? DASH : `${(ms / 1000).toFixed(2)} s`);

const pbxLabel = computed(() => {
  if (state.value?.pbx_connected === true)
    return t('JABVOX_CDR.MONITOR.PBX_CONNECTED');
  if (state.value?.pbx_connected === false)
    return t('JABVOX_CDR.MONITOR.PBX_DISCONNECTED');
  return t('JABVOX_CDR.MONITOR.PBX_UNKNOWN');
});
const pbxClass = computed(() => {
  if (state.value?.pbx_connected === true) return 'text-n-teal-11 bg-n-teal-3';
  if (state.value?.pbx_connected === false) return 'text-n-ruby-11 bg-n-ruby-3';
  return 'text-n-slate-11 bg-n-alpha-2';
});
const statusClass = s => {
  if (s === 'ok') return 'text-n-teal-11 bg-n-teal-3';
  if (s === 'unreachable') return 'text-n-amber-11 bg-n-amber-3';
  if (s === 'error') return 'text-n-ruby-11 bg-n-ruby-3';
  return 'text-n-slate-11 bg-n-alpha-2';
};

onMounted(() => {
  load();
  timer = setInterval(load, REFRESH_MS);
});
onBeforeUnmount(() => clearInterval(timer));
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background p-6">
    <div class="max-w-5xl mx-auto flex flex-col gap-5">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ t('JABVOX_CDR.MONITOR.TITLE') }}
          </h1>
          <p class="text-sm text-n-slate-11">
            {{ t('JABVOX_CDR.MONITOR.SUBTITLE') }}
          </p>
        </div>
        <button
          class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 inline-flex items-center gap-1.5"
          :disabled="loading"
          @click="load"
        >
          <span
            class="i-lucide-refresh-cw size-3.5"
            :class="loading ? 'animate-spin' : ''"
          />
          {{ t('JABVOX_CDR.MONITOR.REFRESH') }}
        </button>
      </div>

      <div
        v-if="errored"
        class="rounded-lg border border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11 px-4 py-3 text-sm"
      >
        {{ t('JABVOX_CDR.MONITOR.LOAD_ERROR') }}
      </div>

      <template v-if="state">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs text-n-slate-10 uppercase tracking-wide">
              {{ t('JABVOX_CDR.MONITOR.PBX') }}
            </p>
            <span
              class="mt-1 inline-flex items-center gap-1 text-sm font-semibold px-2 py-0.5 rounded-full"
              :class="pbxClass"
            >
              <span class="size-2 rounded-full bg-current opacity-70" />
              {{ pbxLabel }}
            </span>
          </div>
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs text-n-slate-10 uppercase tracking-wide">
              {{ t('JABVOX_CDR.MONITOR.SYNCED_TODAY') }}
            </p>
            <p class="mt-1 text-2xl font-bold text-n-slate-12 tabular-nums">
              {{ state.synced_today }}
            </p>
          </div>
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs text-n-slate-10 uppercase tracking-wide">
              {{ t('JABVOX_CDR.MONITOR.AVG_DURATION') }}
            </p>
            <p class="mt-1 text-2xl font-bold text-n-slate-12 tabular-nums">
              {{ fmtMs(state.avg_duration_ms) }}
            </p>
          </div>
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs text-n-slate-10 uppercase tracking-wide">
              {{ t('JABVOX_CDR.MONITOR.LOCAL_RECORDS') }}
            </p>
            <p class="mt-1 text-2xl font-bold text-n-slate-12 tabular-nums">
              {{ state.total_local_records }}
            </p>
          </div>
        </div>

        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <dl class="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-2 text-sm">
            <div class="flex justify-between gap-4">
              <dt class="text-n-slate-10">
                {{ t('JABVOX_CDR.MONITOR.LAST_RUN') }}
              </dt>
              <dd class="text-n-slate-12">{{ fmtDate(state.last_run_at) }}</dd>
            </div>
            <div class="flex justify-between gap-4">
              <dt class="text-n-slate-10">
                {{ t('JABVOX_CDR.MONITOR.LAST_RUN_STATUS') }}
              </dt>
              <dd>
                <span
                  class="text-xs font-semibold px-2 py-0.5 rounded-full"
                  :class="statusClass(state.last_run_status)"
                >
                  {{ state.last_run_status || DASH }}
                </span>
              </dd>
            </div>
            <div class="flex justify-between gap-4">
              <dt class="text-n-slate-10">
                {{ t('JABVOX_CDR.MONITOR.LAST_RUN_DURATION') }}
              </dt>
              <dd class="text-n-slate-12">
                {{ fmtMs(state.last_run_duration_ms) }}
              </dd>
            </div>
            <div class="flex justify-between gap-4">
              <dt class="text-n-slate-10">
                {{ t('JABVOX_CDR.MONITOR.LAST_CURSOR') }}
              </dt>
              <dd class="text-n-slate-12">{{ fmtDate(state.last_cursor) }}</dd>
            </div>
            <div class="flex justify-between gap-4">
              <dt class="text-n-slate-10">
                {{ t('JABVOX_CDR.MONITOR.RUNS_TODAY') }}
              </dt>
              <dd class="text-n-slate-12 tabular-nums">
                {{ state.runs_today }}
              </dd>
            </div>
            <div class="flex justify-between gap-4">
              <dt class="text-n-slate-10">
                {{ t('JABVOX_CDR.MONITOR.ERRORS_TODAY') }}
              </dt>
              <dd
                class="tabular-nums"
                :class="
                  state.errors_today > 0 ? 'text-n-ruby-11' : 'text-n-slate-12'
                "
              >
                {{ state.errors_today }}
              </dd>
            </div>
          </dl>
          <div
            v-if="state.last_error"
            class="mt-3 pt-3 border-t border-n-weak text-sm"
          >
            <p class="text-n-slate-10 mb-1">
              {{ t('JABVOX_CDR.MONITOR.LAST_ERROR') }} ({{
                fmtDate(state.last_error_at)
              }})
            </p>
            <p
              class="font-mono text-xs text-n-ruby-11 bg-n-ruby-3/40 rounded p-2 break-words"
            >
              {{ state.last_error }}
            </p>
          </div>
        </div>

        <div
          class="rounded-xl border border-n-weak bg-n-solid-1 overflow-hidden"
        >
          <h2
            class="text-sm font-semibold text-n-slate-12 px-4 py-3 border-b border-n-weak"
          >
            {{ t('JABVOX_CDR.MONITOR.RECENT_RUNS') }}
          </h2>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="text-left text-xs text-n-slate-10 border-b border-n-weak"
                >
                  <th class="px-4 py-2 font-medium">
                    {{ t('JABVOX_CDR.MONITOR.COL_START') }}
                  </th>
                  <th class="px-4 py-2 font-medium">
                    {{ t('JABVOX_CDR.MONITOR.COL_STATUS') }}
                  </th>
                  <th class="px-4 py-2 font-medium text-right">
                    {{ t('JABVOX_CDR.MONITOR.COL_DURATION') }}
                  </th>
                  <th class="px-4 py-2 font-medium text-right">
                    {{ t('JABVOX_CDR.MONITOR.COL_FETCHED') }}
                  </th>
                  <th class="px-4 py-2 font-medium text-right">
                    {{ t('JABVOX_CDR.MONITOR.COL_INSERTED') }}
                  </th>
                  <th class="px-4 py-2 font-medium text-right">
                    {{ t('JABVOX_CDR.MONITOR.COL_UPDATED') }}
                  </th>
                  <th class="px-4 py-2 font-medium text-right">
                    {{ t('JABVOX_CDR.MONITOR.COL_SKIPPED') }}
                  </th>
                  <th class="px-4 py-2 font-medium text-right">
                    {{ t('JABVOX_CDR.MONITOR.COL_ERRORS') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(run, i) in state.recent_runs"
                  :key="i"
                  class="border-b border-n-weak last:border-0"
                >
                  <td class="px-4 py-2 text-n-slate-11 whitespace-nowrap">
                    {{ fmtDate(run.started_at) }}
                  </td>
                  <td class="px-4 py-2">
                    <span
                      class="text-xs font-semibold px-2 py-0.5 rounded-full"
                      :class="statusClass(run.status)"
                    >
                      {{ run.status }}
                    </span>
                  </td>
                  <td class="px-4 py-2 text-right tabular-nums text-n-slate-11">
                    {{ fmtMs(run.duration_ms) }}
                  </td>
                  <td class="px-4 py-2 text-right tabular-nums text-n-slate-11">
                    {{ run.fetched }}
                  </td>
                  <td class="px-4 py-2 text-right tabular-nums text-n-teal-11">
                    {{ run.inserted }}
                  </td>
                  <td class="px-4 py-2 text-right tabular-nums text-n-slate-11">
                    {{ run.updated }}
                  </td>
                  <td class="px-4 py-2 text-right tabular-nums text-n-slate-11">
                    {{ run.skipped }}
                  </td>
                  <td
                    class="px-4 py-2 text-right tabular-nums"
                    :class="
                      run.errors > 0 ? 'text-n-ruby-11' : 'text-n-slate-11'
                    "
                  >
                    {{ run.errors }}
                  </td>
                </tr>
                <tr v-if="!state.recent_runs || !state.recent_runs.length">
                  <td colspan="8" class="px-4 py-6 text-center text-n-slate-10">
                    {{ t('JABVOX_CDR.MONITOR.NO_RUNS') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
