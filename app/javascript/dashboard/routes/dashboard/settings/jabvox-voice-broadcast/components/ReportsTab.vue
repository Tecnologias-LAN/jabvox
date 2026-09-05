<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import voiceBroadcastAPI from 'dashboard/api/jabvox/voiceBroadcast';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Reportes globales (cross-campaña): métricas agregadas en un rango de fechas —
// cuántas llamadas, si llegó y reprodujo el audio, contestó humano/máquina, no
// contestó, falló, y el desglose por desenlace/AMD. Con export CSV.
const { t } = useI18n();

const OUTCOME_LABELS = {
  answered_human: 'Contestó (humano)',
  answered_machine: 'Buzón/máquina',
  no_answer: 'No contestó',
  busy: 'Ocupado',
  congestion: 'Congestión',
  failed: 'Falló',
  played_complete: 'Escuchó completo',
  hung_up_early: 'Colgó antes',
  opted_out: 'Se dio de baja',
};

const data = ref(null);
const loading = ref(false);
const from = ref('');
const to = ref('');

const load = async () => {
  loading.value = true;
  try {
    const res = await voiceBroadcastAPI.analytics({
      from: from.value || undefined,
      to: to.value || undefined,
    });
    data.value = res.data;
  } catch (e) {
    data.value = null;
  } finally {
    loading.value = false;
  }
};

const exportCsv = () => {
  const params = new URLSearchParams();
  if (from.value) params.append('from', from.value);
  if (to.value) params.append('to', to.value);
  const qs = params.toString();
  window.open(
    `${voiceBroadcastAPI.analyticsCsvUrl()}${qs ? `?${qs}` : ''}`,
    '_blank'
  );
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-5">
    <!-- Filtros -->
    <div class="flex flex-wrap items-end gap-3">
      <div class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_VOICE_BROADCAST.HISTORY.FROM') }}
        </span>
        <input
          v-model="from"
          type="date"
          class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12"
          @change="load"
        />
      </div>
      <div class="flex flex-col gap-1.5">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('JABVOX_VOICE_BROADCAST.HISTORY.TO') }}
        </span>
        <input
          v-model="to"
          type="date"
          class="reset-base text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12"
          @change="load"
        />
      </div>
      <Button
        :label="t('JABVOX_VOICE_BROADCAST.DETAIL.EXPORT_CSV')"
        icon="i-lucide-download"
        size="sm"
        variant="outline"
        color="slate"
        class="ml-auto"
        @click="exportCsv"
      />
    </div>

    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 py-10 text-sm text-n-slate-11"
    >
      <Spinner :size="18" />
    </div>

    <template v-else-if="data">
      <!-- KPIs -->
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        <div
          v-for="kpi in [
            { k: 'campaigns', l: 'CAMPAIGNS', c: 'text-n-slate-12' },
            { k: 'dialed', l: 'DIALED_KPI', c: 'text-n-slate-12' },
            { k: 'answered_human', l: 'ANSWERED_HUMAN', c: 'text-n-teal-11' },
            {
              k: 'answered_machine',
              l: 'ANSWERED_MACHINE',
              c: 'text-n-amber-11',
            },
            { k: 'played_complete', l: 'PLAYED_COMPLETE', c: 'text-n-blue-11' },
            { k: 'failed', l: 'FAILED', c: 'text-n-ruby-11' },
          ]"
          :key="kpi.k"
          class="rounded-xl border border-n-weak bg-n-alpha-1 p-3 text-center"
        >
          <p class="text-xl font-bold tabular-nums" :class="kpi.c">
            {{ data[kpi.k] ?? 0 }}
          </p>
          <p class="text-xs text-n-slate-10 mt-0.5">
            {{ t(`JABVOX_VOICE_BROADCAST.REPORTS.${kpi.l}`) }}
          </p>
        </div>
      </div>

      <!-- Tasas -->
      <div class="grid grid-cols-2 gap-3">
        <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
          <p class="text-xs text-n-slate-10">
            {{ t('JABVOX_VOICE_BROADCAST.REPORT.ANSWER_RATE') }}
          </p>
          <p class="text-2xl font-bold text-n-teal-11 tabular-nums">
            {{ data.answer_rate }}%
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
          <p class="text-xs text-n-slate-10">
            {{ t('JABVOX_VOICE_BROADCAST.REPORT.PLAYED_RATE') }}
          </p>
          <p class="text-2xl font-bold text-n-blue-11 tabular-nums">
            {{ data.played_rate }}%
          </p>
        </div>
      </div>

      <!-- Desglose de desenlaces -->
      <div
        v-if="data.outcomes && Object.keys(data.outcomes).length"
        class="rounded-xl border border-n-weak p-4"
      >
        <h3 class="text-sm font-semibold text-n-slate-12 mb-3">
          {{ t('JABVOX_VOICE_BROADCAST.REPORTS.OUTCOMES') }}
        </h3>
        <div class="flex flex-wrap gap-2">
          <span
            v-for="(n, key) in data.outcomes"
            :key="key"
            class="inline-flex items-center gap-1.5 rounded-lg bg-n-alpha-2 px-2.5 py-1 text-xs"
          >
            <span class="text-n-slate-11">{{
              OUTCOME_LABELS[key] || key
            }}</span>
            <span class="font-semibold text-n-slate-12 tabular-nums">{{
              n
            }}</span>
          </span>
        </div>
      </div>
    </template>

    <div
      v-else
      class="rounded-xl border border-dashed border-n-weak py-10 text-center text-sm text-n-slate-11"
    >
      {{ t('JABVOX_VOICE_BROADCAST.REPORTS.EMPTY') }}
    </div>
  </div>
</template>
