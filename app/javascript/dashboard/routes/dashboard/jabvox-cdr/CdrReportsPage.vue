<script setup>
import { ref, onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { cdrReportsAPI } from 'dashboard/api/jabvox/cdr';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
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

const dispositionOptions = computed(() => [
  { value: '', label: t('JABVOX_CDR.REPORTS.FILTERS.ALL') },
  ...DISPOSITIONS.map(d => ({ value: d, label: d })),
]);

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

const resetFilters = () => {
  filters.value = { from: '', to: '', extension: '', disposition: '' };
  applyFilters();
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

// Reflect a manual typification on the matching row without reloading the page.
const onTypified = ({ uniqueid, typification }) => {
  const row = records.value.find(r => r.uniqueid === uniqueid);
  if (row) row.typification = typification;
  if (selectedCall.value?.uniqueid === uniqueid) {
    selectedCall.value.typification = typification;
  }
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
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-6xl flex flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header + view tabs -->
      <div
        class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex items-start gap-3 min-w-0">
          <span
            class="i-lucide-phone-call size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
          />
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
              {{ t('JABVOX_CDR.REPORTS.TITLE') }}
            </h1>
            <p class="mt-1 max-w-2xl text-sm leading-relaxed text-n-slate-11">
              {{ t('JABVOX_CDR.REPORTS.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <div
          class="inline-flex shrink-0 rounded-lg border border-n-weak bg-n-solid-1 p-1"
        >
          <button
            class="px-3 py-1.5 text-sm font-medium rounded-md transition-colors"
            :class="
              activeView === 'summary'
                ? 'bg-n-brand text-white'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="switchView('summary')"
          >
            {{ t('JABVOX_CDR.REPORTS.VIEW_SUMMARY') }}
          </button>
          <button
            class="px-3 py-1.5 text-sm font-medium rounded-md transition-colors"
            :class="
              activeView === 'records'
                ? 'bg-n-brand text-white'
                : 'text-n-slate-11 hover:bg-n-alpha-1'
            "
            @click="switchView('records')"
          >
            {{ t('JABVOX_CDR.REPORTS.VIEW_RECORDS') }}
          </button>
        </div>
      </div>

      <!-- Not configured banner -->
      <div
        v-if="!access.configured"
        class="flex items-center gap-2 rounded-xl border border-n-amber-6 bg-n-amber-3 px-4 py-3 text-sm text-n-amber-11"
      >
        <span class="i-lucide-triangle-alert size-4 shrink-0" />
        {{ t('JABVOX_CDR.REPORTS.NOT_CONFIGURED') }}
      </div>

      <!-- Filters -->
      <div
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm flex flex-col gap-4"
      >
        <div class="flex items-center gap-2">
          <span class="i-lucide-sliders-horizontal size-4 text-n-slate-11" />
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_CDR.REPORTS.FILTERS.TITLE') }}
          </span>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <Input
            v-model="filters.from"
            type="datetime-local"
            :label="t('JABVOX_CDR.REPORTS.FILTERS.FROM')"
          />
          <Input
            v-model="filters.to"
            type="datetime-local"
            :label="t('JABVOX_CDR.REPORTS.FILTERS.TO')"
          />
          <Input
            v-model="filters.extension"
            :label="t('JABVOX_CDR.REPORTS.FILTERS.EXTENSION')"
            :placeholder="t('JABVOX_CDR.REPORTS.FILTERS.EXTENSION_PLACEHOLDER')"
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_CDR.REPORTS.FILTERS.DISPOSITION') }}
            </label>
            <Select
              v-model="filters.disposition"
              :options="dispositionOptions"
            />
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <Button
            :label="t('JABVOX_CDR.REPORTS.FILTERS.APPLY')"
            icon="i-lucide-search"
            size="sm"
            @click="applyFilters"
          />
          <Button
            :label="t('JABVOX_CDR.REPORTS.FILTERS.RESET')"
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            @click="resetFilters"
          />
        </div>
      </div>

      <!-- Loading -->
      <div
        v-if="loading"
        class="flex items-center justify-center gap-2 py-16 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_CDR.REPORTS.LOADING') }}
      </div>

      <!-- Summary view -->
      <template v-else-if="activeView === 'summary'">
        <!-- KPIs -->
        <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
          <div
            class="p-4 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
          >
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_CDR.REPORTS.KPI.TOTAL') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ kpis.total }}
            </p>
          </div>
          <div
            class="p-4 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
          >
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_CDR.REPORTS.KPI.ANSWERED') }}
            </p>
            <p class="text-2xl font-semibold text-n-teal-11">
              {{ kpis.answered }}
            </p>
          </div>
          <div
            class="p-4 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
          >
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_CDR.REPORTS.KPI.NO_ANSWER') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ kpis.no_answer }}
            </p>
          </div>
          <div
            class="p-4 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
          >
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_CDR.REPORTS.KPI.TALK_TIME') }}
            </p>
            <p class="text-2xl font-semibold text-n-slate-12">
              {{ formatDuration(kpis.talk_seconds) }}
            </p>
          </div>
          <div
            class="p-4 rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm"
          >
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_CDR.REPORTS.KPI.ANSWER_RATE') }}
            </p>
            <p class="text-2xl font-semibold text-n-brand">
              {{ `${answerRate}%` }}
            </p>
          </div>
        </div>

        <!-- Summary table -->
        <div
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
        >
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="text-left text-n-slate-10 bg-n-alpha-1 border-b border-n-weak"
                >
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.AGENT') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.KPI.TOTAL') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.KPI.ANSWERED') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.KPI.NO_ANSWER') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.BUSY') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.FAILED') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.KPI.TALK_TIME') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.KPI.ANSWER_RATE') }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="row in summary"
                  :key="row.agent"
                  class="hover:bg-n-alpha-1 transition-colors"
                >
                  <td class="px-4 py-2.5 text-n-slate-12">
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
                  <td class="px-4 py-2.5 text-n-slate-12">{{ row.total }}</td>
                  <td class="px-4 py-2.5 text-n-teal-11">{{ row.answered }}</td>
                  <td class="px-4 py-2.5 text-n-slate-12">
                    {{ row.no_answer }}
                  </td>
                  <td class="px-4 py-2.5 text-n-slate-12">{{ row.busy }}</td>
                  <td class="px-4 py-2.5 text-n-slate-12">{{ row.failed }}</td>
                  <td class="px-4 py-2.5 text-n-slate-12">
                    {{ formatDuration(row.talk_seconds) }}
                  </td>
                  <td class="px-4 py-2.5 text-n-slate-12">
                    {{ `${row.answer_rate}%` }}
                  </td>
                </tr>
                <tr v-if="!summary.length">
                  <td colspan="8" class="py-10 text-center text-n-slate-11">
                    {{ t('JABVOX_CDR.REPORTS.EMPTY') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>

      <!-- Records view -->
      <template v-else>
        <div
          class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
        >
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr
                  class="text-left text-n-slate-10 bg-n-alpha-1 border-b border-n-weak"
                >
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.DATE') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.ORIGIN') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.DESTINATION') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.ORIGIN_CHANNEL') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.MEDIUM') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.STATUS') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.TYPIFICATION') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.DURATION') }}
                  </th>
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('JABVOX_CDR.REPORTS.TABLE.SCORE') }}
                  </th>
                  <th class="px-4 py-2.5" />
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="call in records"
                  :key="call.uniqueid"
                  class="hover:bg-n-alpha-1 transition-colors"
                >
                  <td class="px-4 py-2.5 text-n-slate-12 whitespace-nowrap">
                    {{ call.calldate }}
                  </td>
                  <td class="px-4 py-2.5 text-n-slate-12">
                    {{ call.origin || t('JABVOX_CDR.REPORTS.NO_SCORE') }}
                  </td>
                  <td class="px-4 py-2.5 text-n-slate-12">
                    {{ call.destination || t('JABVOX_CDR.REPORTS.NO_SCORE') }}
                  </td>
                  <td class="px-4 py-2.5 text-n-slate-12">
                    {{
                      call.origin_channel || t('JABVOX_CDR.REPORTS.NO_SCORE')
                    }}
                  </td>
                  <td class="px-4 py-2.5">
                    <span
                      class="rounded-full px-2 py-0.5 text-xs font-medium"
                      :class="mediumClass(call.medium)"
                    >
                      {{ mediumLabel(call.medium) }}
                    </span>
                  </td>
                  <td class="px-4 py-2.5 text-n-slate-12">
                    {{ call.disposition }}
                  </td>
                  <td class="px-4 py-2.5">
                    <span
                      v-if="call.typification"
                      class="rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-12"
                    >
                      {{ call.typification }}
                    </span>
                    <span v-else class="text-n-slate-10">{{
                      t('JABVOX_CDR.REPORTS.NO_SCORE')
                    }}</span>
                  </td>
                  <td class="px-4 py-2.5 text-n-slate-12 whitespace-nowrap">
                    {{ formatDuration(call.billsec) }}
                  </td>
                  <td class="px-4 py-2.5">
                    <span
                      v-if="scoreFor(call.uniqueid) != null"
                      class="font-semibold text-n-brand"
                    >
                      {{ scoreFor(call.uniqueid) }}
                    </span>
                    <span v-else class="text-n-slate-10">{{
                      t('JABVOX_CDR.REPORTS.NO_SCORE')
                    }}</span>
                  </td>
                  <td class="px-4 py-2.5 text-right">
                    <Button
                      v-tooltip="t('JABVOX_CDR.REPORTS.ANALYZE')"
                      icon="i-lucide-mic"
                      variant="ghost"
                      color="slate"
                      size="sm"
                      @click="openAnalysis(call)"
                    />
                  </td>
                </tr>
                <tr v-if="!records.length">
                  <td colspan="10" class="py-10 text-center text-n-slate-11">
                    {{ t('JABVOX_CDR.REPORTS.EMPTY') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Pagination -->
        <div
          v-if="records.length"
          class="flex items-center justify-center gap-4 text-sm text-n-slate-11"
        >
          <Button
            :label="t('JABVOX_CDR.REPORTS.PREV')"
            icon="i-lucide-chevron-left"
            variant="outline"
            color="slate"
            size="sm"
            :disabled="page <= 1"
            @click="changePage(-1)"
          />
          <span>{{
            t('JABVOX_CDR.REPORTS.PAGE_OF', { page, total: totalPages })
          }}</span>
          <Button
            :label="t('JABVOX_CDR.REPORTS.NEXT')"
            icon="i-lucide-chevron-right"
            variant="outline"
            color="slate"
            size="sm"
            trailing-icon
            :disabled="page >= totalPages"
            @click="changePage(1)"
          />
        </div>
      </template>
    </div>

    <CdrAnalysisModal
      v-if="selectedCall"
      :call="selectedCall"
      :existing="analyses[selectedCall.uniqueid]"
      @close="selectedCall = null"
      @updated="onAnalysisUpdated"
      @typified="onTypified"
    />
  </div>
</template>
