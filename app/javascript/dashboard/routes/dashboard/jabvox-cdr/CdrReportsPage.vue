<script setup>
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { cdrReportsAPI } from 'dashboard/api/jabvox/cdr';
import CdrAnalysisModal from './CdrAnalysisModal.vue';

const { t } = useI18n();
const router = useRouter();

const PER_PAGE = 50;
// PBX disposition values are technical constants, not translatable copy.
const DISPOSITIONS = ['ANSWERED', 'NO ANSWER', 'BUSY', 'FAILED'];

const activeView = ref('summary');
const loading = ref(false);
const access = ref({ can_view: false, configured: false });

const filters = ref({ from: '', to: '', extension: '', disposition: '' });

const summary = ref([]);
const records = ref([]);
const totalRecords = ref(0);
const page = ref(1);

const analyses = ref({}); // uniqueid -> analysis
const selectedCall = ref(null);

const totalPages = computed(
  () => Math.ceil(totalRecords.value / PER_PAGE) || 1
);

const kpis = computed(() => {
  return summary.value.reduce(
    (acc, row) => {
      acc.total += row.total;
      acc.answered += row.answered;
      acc.no_answer += row.no_answer;
      acc.busy += row.busy;
      acc.failed += row.failed;
      acc.talk_seconds += row.talk_seconds;
      return acc;
    },
    { total: 0, answered: 0, no_answer: 0, busy: 0, failed: 0, talk_seconds: 0 }
  );
});

const answerRate = computed(() =>
  kpis.value.total
    ? ((kpis.value.answered / kpis.value.total) * 100).toFixed(1)
    : '0'
);

const formatDuration = seconds => {
  const s = Number(seconds) || 0;
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}m ${r}s`;
};

// How the call was placed. Backend sends click_to_call | dialer | manual.
// Labels resolved with static literal keys so the template binds plain strings.
const mediumLabels = computed(() => ({
  click_to_call: t('JABVOX_CDR.REPORTS.MEDIUM_TYPES.CLICK_TO_CALL'),
  dialer: t('JABVOX_CDR.REPORTS.MEDIUM_TYPES.DIALER'),
  manual: t('JABVOX_CDR.REPORTS.MEDIUM_TYPES.MANUAL'),
}));
const mediumLabel = medium =>
  mediumLabels.value[medium] || mediumLabels.value.manual;
const mediumClass = medium => {
  if (medium === 'dialer') return 'bg-n-teal-3 text-n-teal-11';
  if (medium === 'click_to_call') return 'bg-n-blue-3 text-n-blue-11';
  return 'bg-n-alpha-2 text-n-slate-11';
};

const apiFilters = () => {
  const f = {};
  Object.entries(filters.value).forEach(([k, v]) => {
    if (v) f[k] = v;
  });
  return f;
};

const loadSummary = async () => {
  loading.value = true;
  try {
    const { data } = await cdrReportsAPI.summary(apiFilters());
    summary.value = data.summary || [];
  } catch (error) {
    useAlert(t('JABVOX_CDR.REPORTS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const loadAnalysesFor = async rows => {
  const ids = rows.map(r => r.uniqueid).filter(Boolean);
  if (!ids.length) return;
  try {
    const { data } = await cdrReportsAPI.analysesBatch(ids);
    (data.analyses || []).forEach(a => {
      analyses.value[a.uniqueid] = a;
    });
  } catch (error) {
    // non-blocking; the table still renders without scores
  }
};

const loadRecords = async () => {
  loading.value = true;
  try {
    const { data } = await cdrReportsAPI.records({
      ...apiFilters(),
      page: page.value,
      per_page: PER_PAGE,
    });
    records.value = data.records || [];
    totalRecords.value = data.total || 0;
    await loadAnalysesFor(records.value);
  } catch (error) {
    useAlert(t('JABVOX_CDR.REPORTS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const applyFilters = () => {
  page.value = 1;
  if (activeView.value === 'summary') loadSummary();
  else loadRecords();
};

const switchView = view => {
  activeView.value = view;
  applyFilters();
};

const changePage = delta => {
  const next = page.value + delta;
  if (next < 1 || next > totalPages.value) return;
  page.value = next;
  loadRecords();
};

const openAnalysis = call => {
  selectedCall.value = call;
};

const onAnalysisUpdated = analysis => {
  if (analysis?.uniqueid) analyses.value[analysis.uniqueid] = analysis;
};

const scoreFor = uniqueid => analyses.value[uniqueid]?.final_score;

onMounted(async () => {
  try {
    const { data } = await cdrReportsAPI.myAccess();
    access.value = data;
    if (!data.can_view) {
      router.replace({ name: 'home' });
      return;
    }
    loadSummary();
  } catch (error) {
    router.replace({ name: 'home' });
  }
});
</script>

<template>
  <div
    class="flex flex-col flex-1 h-full w-full min-h-0 overflow-auto bg-n-surface-1"
  >
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('JABVOX_CDR.REPORTS.TITLE') }}
      </h1>
      <div class="flex gap-2">
        <button
          class="px-3 py-1.5 text-sm rounded-lg"
          :class="
            activeView === 'summary'
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          @click="switchView('summary')"
        >
          {{ t('JABVOX_CDR.REPORTS.VIEW_SUMMARY') }}
        </button>
        <button
          class="px-3 py-1.5 text-sm rounded-lg"
          :class="
            activeView === 'records'
              ? 'bg-n-brand text-white'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          @click="switchView('records')"
        >
          {{ t('JABVOX_CDR.REPORTS.VIEW_RECORDS') }}
        </button>
      </div>
    </header>

    <div
      v-if="!access.configured"
      class="m-6 p-4 rounded-lg bg-n-amber-3 text-n-amber-11 text-sm"
    >
      {{ t('JABVOX_CDR.REPORTS.NOT_CONFIGURED') }}
    </div>

    <!-- Filters -->
    <div class="flex flex-wrap gap-3 items-end px-6 py-4">
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_CDR.REPORTS.FILTERS.FROM') }}
        <input
          v-model="filters.from"
          type="datetime-local"
          class="reset-base mt-1 text-sm"
        />
      </label>
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_CDR.REPORTS.FILTERS.TO') }}
        <input
          v-model="filters.to"
          type="datetime-local"
          class="reset-base mt-1 text-sm"
        />
      </label>
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_CDR.REPORTS.FILTERS.EXTENSION') }}
        <input
          v-model="filters.extension"
          type="text"
          class="reset-base mt-1 text-sm"
        />
      </label>
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_CDR.REPORTS.FILTERS.DISPOSITION') }}
        <select v-model="filters.disposition" class="reset-base mt-1 text-sm">
          <option value="">{{ t('JABVOX_CDR.REPORTS.FILTERS.ALL') }}</option>
          <option v-for="d in DISPOSITIONS" :key="d" :value="d">{{ d }}</option>
        </select>
      </label>
      <button
        class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
        @click="applyFilters"
      >
        {{ t('JABVOX_CDR.REPORTS.FILTERS.APPLY') }}
      </button>
    </div>

    <div v-if="loading" class="px-6 py-10 text-center text-n-slate-11">
      {{ t('JABVOX_CDR.REPORTS.LOADING') }}
    </div>

    <!-- Summary view -->
    <template v-else-if="activeView === 'summary'">
      <div class="grid grid-cols-2 md:grid-cols-5 gap-3 px-6 pb-4">
        <div class="p-4 rounded-lg bg-n-alpha-2">
          <p class="text-xs text-n-slate-11">
            {{ t('JABVOX_CDR.REPORTS.KPI.TOTAL') }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12">{{ kpis.total }}</p>
        </div>
        <div class="p-4 rounded-lg bg-n-alpha-2">
          <p class="text-xs text-n-slate-11">
            {{ t('JABVOX_CDR.REPORTS.KPI.ANSWERED') }}
          </p>
          <p class="text-2xl font-semibold text-n-teal-11">
            {{ kpis.answered }}
          </p>
        </div>
        <div class="p-4 rounded-lg bg-n-alpha-2">
          <p class="text-xs text-n-slate-11">
            {{ t('JABVOX_CDR.REPORTS.KPI.NO_ANSWER') }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12">
            {{ kpis.no_answer }}
          </p>
        </div>
        <div class="p-4 rounded-lg bg-n-alpha-2">
          <p class="text-xs text-n-slate-11">
            {{ t('JABVOX_CDR.REPORTS.KPI.TALK_TIME') }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12">
            {{ formatDuration(kpis.talk_seconds) }}
          </p>
        </div>
        <div class="p-4 rounded-lg bg-n-alpha-2">
          <p class="text-xs text-n-slate-11">
            {{ t('JABVOX_CDR.REPORTS.KPI.ANSWER_RATE') }}
          </p>
          <p class="text-2xl font-semibold text-n-brand">
            {{ `${answerRate}%` }}
          </p>
        </div>
      </div>

      <div class="px-6 pb-8">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.AGENT') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.KPI.TOTAL') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.KPI.ANSWERED') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.KPI.NO_ANSWER') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.BUSY') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.FAILED') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.KPI.TALK_TIME') }}</th>
              <th class="py-2">
                {{ t('JABVOX_CDR.REPORTS.KPI.ANSWER_RATE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in summary"
              :key="row.agent"
              class="border-b border-n-weak"
            >
              <td class="py-2 text-n-slate-12">
                {{ row.agent }}
                <span
                  v-if="
                    row.agent_extension && row.agent !== row.agent_extension
                  "
                  class="text-n-slate-10"
                >
                  {{ `(${row.agent_extension})` }}
                </span>
              </td>
              <td class="py-2">{{ row.total }}</td>
              <td class="py-2 text-n-teal-11">{{ row.answered }}</td>
              <td class="py-2">{{ row.no_answer }}</td>
              <td class="py-2">{{ row.busy }}</td>
              <td class="py-2">{{ row.failed }}</td>
              <td class="py-2">{{ formatDuration(row.talk_seconds) }}</td>
              <td class="py-2">{{ `${row.answer_rate}%` }}</td>
            </tr>
            <tr v-if="!summary.length">
              <td colspan="8" class="py-6 text-center text-n-slate-11">
                {{ t('JABVOX_CDR.REPORTS.EMPTY') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <!-- Records view -->
    <template v-else>
      <div class="px-6 pb-4">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.DATE') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.ORIGIN') }}</th>
              <th class="py-2">
                {{ t('JABVOX_CDR.REPORTS.TABLE.DESTINATION') }}
              </th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.MEDIUM') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.STATUS') }}</th>
              <th class="py-2">
                {{ t('JABVOX_CDR.REPORTS.TABLE.TYPIFICATION') }}
              </th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.DURATION') }}</th>
              <th class="py-2">{{ t('JABVOX_CDR.REPORTS.TABLE.SCORE') }}</th>
              <th class="py-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="call in records"
              :key="call.uniqueid"
              class="border-b border-n-weak"
            >
              <td class="py-2 text-n-slate-12">{{ call.calldate }}</td>
              <td class="py-2 text-n-slate-12">
                {{ call.origin || t('JABVOX_CDR.REPORTS.NO_SCORE') }}
              </td>
              <td class="py-2 text-n-slate-12">
                {{ call.destination || t('JABVOX_CDR.REPORTS.NO_SCORE') }}
              </td>
              <td class="py-2">
                <span
                  class="rounded px-1.5 py-0.5 text-xs"
                  :class="mediumClass(call.medium)"
                >
                  {{ mediumLabel(call.medium) }}
                </span>
              </td>
              <td class="py-2">{{ call.disposition }}</td>
              <td class="py-2">
                <span
                  v-if="call.typification"
                  class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs text-n-slate-12"
                >
                  {{ call.typification }}
                </span>
                <span v-else class="text-n-slate-10">{{
                  t('JABVOX_CDR.REPORTS.NO_SCORE')
                }}</span>
              </td>
              <td class="py-2">{{ formatDuration(call.billsec) }}</td>
              <td class="py-2">
                <span
                  v-if="scoreFor(call.uniqueid) != null"
                  class="font-medium text-n-brand"
                >
                  {{ scoreFor(call.uniqueid) }}
                </span>
                <span v-else class="text-n-slate-10">{{
                  t('JABVOX_CDR.REPORTS.NO_SCORE')
                }}</span>
              </td>
              <td class="py-2 text-right">
                <button
                  v-tooltip="t('JABVOX_CDR.REPORTS.ANALYZE')"
                  class="p-1.5 rounded-lg hover:bg-n-alpha-2"
                  @click="openAnalysis(call)"
                >
                  <span class="i-lucide-mic text-base text-n-slate-11" />
                </button>
              </td>
            </tr>
            <tr v-if="!records.length">
              <td colspan="9" class="py-6 text-center text-n-slate-11">
                {{ t('JABVOX_CDR.REPORTS.EMPTY') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        class="flex items-center justify-center gap-4 pb-8 text-sm text-n-slate-11"
      >
        <button
          class="px-3 py-1 rounded-lg bg-n-alpha-2 disabled:opacity-50"
          :disabled="page <= 1"
          @click="changePage(-1)"
        >
          {{ t('JABVOX_CDR.REPORTS.PREV') }}
        </button>
        <span>{{
          t('JABVOX_CDR.REPORTS.PAGE_OF', { page, total: totalPages })
        }}</span>
        <button
          class="px-3 py-1 rounded-lg bg-n-alpha-2 disabled:opacity-50"
          :disabled="page >= totalPages"
          @click="changePage(1)"
        >
          {{ t('JABVOX_CDR.REPORTS.NEXT') }}
        </button>
      </div>
    </template>

    <CdrAnalysisModal
      v-if="selectedCall"
      :call="selectedCall"
      :existing="analyses[selectedCall.uniqueid]"
      @close="selectedCall = null"
      @updated="onAnalysisUpdated"
    />
  </div>
</template>
