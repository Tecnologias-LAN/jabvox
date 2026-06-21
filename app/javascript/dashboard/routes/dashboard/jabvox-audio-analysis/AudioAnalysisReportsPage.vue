<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { audioReportsAPI } from 'dashboard/api/jabvox/audioAnalysis';

const { t } = useI18n();
const router = useRouter();

const loading = ref(false);
const days = ref([]);
const summary = ref(null);
const filterOptions = ref({ pipelines: [], agents: [] });
const filters = ref({
  from: '',
  to: '',
  pipeline_id: '',
  agent_id: '',
  score_op: '',
  score_value: '',
});

// file_key of the result whose transcript is currently expanded
const openTranscript = ref(null);
const toggleTranscript = key => {
  openTranscript.value = openTranscript.value === key ? null : key;
};
const fileName = key => key.split('/').pop();

const apiFilters = () => {
  const f = {};
  Object.entries(filters.value).forEach(([k, v]) => {
    if (v) f[k] = v;
  });
  // Only send the score filter when both operator and value are set.
  if (!(filters.value.score_op && filters.value.score_value !== '')) {
    delete f.score_op;
    delete f.score_value;
  }
  return f;
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await audioReportsAPI.daily(apiFilters());
    days.value = data.days || [];
    summary.value = data.summary || null;
  } catch (e) {
    useAlert(t('JABVOX_AUDIO.REPORTS.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const applyPreset = preset => {
  const today = new Date();
  const toIso = d => d.toISOString().slice(0, 10);
  const from = new Date(today);
  if (preset === '7d') from.setDate(today.getDate() - 7);
  if (preset === '30d') from.setDate(today.getDate() - 30);
  filters.value.from = toIso(from);
  filters.value.to = toIso(today);
  load();
};

onMounted(async () => {
  try {
    const { data } = await audioReportsAPI.myAccess();
    if (!data.can_view_reports) {
      router.replace({ name: 'home' });
      return;
    }
    const { data: opts } = await audioReportsAPI.filterOptions();
    filterOptions.value = opts;
    await load();
  } catch (e) {
    router.replace({ name: 'home' });
  }
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -- emoji/symbols are universal -->
  <div class="flex flex-col flex-1 h-full overflow-auto bg-n-surface-1">
    <header
      class="flex items-center justify-between px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('JABVOX_AUDIO.REPORTS.TITLE') }}
      </h1>
    </header>

    <div class="flex flex-wrap gap-3 items-end px-6 py-4">
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_AUDIO.REPORTS.FROM') }}
        <input
          v-model="filters.from"
          type="date"
          class="reset-base mt-1 text-sm"
        />
      </label>
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_AUDIO.REPORTS.TO') }}
        <input
          v-model="filters.to"
          type="date"
          class="reset-base mt-1 text-sm"
        />
      </label>
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_AUDIO.REPORTS.PIPELINE') }}
        <select v-model="filters.pipeline_id" class="reset-base mt-1 text-sm">
          <option value="">{{ t('JABVOX_AUDIO.REPORTS.ALL') }}</option>
          <option
            v-for="p in filterOptions.pipelines"
            :key="p.id"
            :value="p.id"
          >
            {{ p.name }}
          </option>
        </select>
      </label>
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_AUDIO.REPORTS.AGENT') }}
        <select v-model="filters.agent_id" class="reset-base mt-1 text-sm">
          <option value="">{{ t('JABVOX_AUDIO.REPORTS.ALL') }}</option>
          <option v-for="a in filterOptions.agents" :key="a.id" :value="a.id">
            {{ a.name }}
          </option>
        </select>
      </label>
      <label class="flex flex-col text-xs text-n-slate-11">
        {{ t('JABVOX_AUDIO.REPORTS.SCORE_FILTER') }}
        <div class="flex gap-1 mt-1">
          <select v-model="filters.score_op" class="reset-base text-sm">
            <option value="">{{ t('JABVOX_AUDIO.REPORTS.ALL') }}</option>
            <option value="gte">{{ t('JABVOX_AUDIO.REPORTS.GTE') }}</option>
            <option value="lt">{{ t('JABVOX_AUDIO.REPORTS.LT') }}</option>
          </select>
          <input
            v-model="filters.score_value"
            type="number"
            min="0"
            max="100"
            placeholder="%"
            class="reset-base text-sm w-16"
          />
        </div>
      </label>
      <button
        class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
        @click="load"
      >
        {{ t('JABVOX_AUDIO.REPORTS.APPLY') }}
      </button>
      <button
        class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
        @click="applyPreset('today')"
      >
        {{ t('JABVOX_AUDIO.REPORTS.TODAY') }}
      </button>
      <button
        class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
        @click="applyPreset('7d')"
      >
        7d
      </button>
      <button
        class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
        @click="applyPreset('30d')"
      >
        30d
      </button>
    </div>

    <div v-if="loading" class="px-6 py-10 text-center text-n-slate-11">
      {{ t('JABVOX_AUDIO.REPORTS.LOADING') }}
    </div>

    <div v-else class="px-6 pb-8 space-y-6">
      <!-- Overall summary across the whole filtered range -->
      <div
        v-if="summary && summary.total"
        class="rounded-xl border border-n-weak p-4"
      >
        <p class="text-sm font-medium text-n-slate-12 mb-3">
          {{ t('JABVOX_AUDIO.REPORTS.SUMMARY') }}
        </p>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.TOTAL') }}
            </p>
            <p class="text-xl font-semibold text-n-slate-12">
              {{ summary.total }}
            </p>
          </div>
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.AVG_SCORE') }}
            </p>
            <p class="text-xl font-semibold text-n-brand">
              {{
                summary.average_score != null
                  ? `${summary.average_score}%`
                  : '—'
              }}
            </p>
          </div>
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.PASSED') }}
            </p>
            <p class="text-xl font-semibold text-n-teal-11">
              {{ summary.passed }}
            </p>
          </div>
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.FAILED') }}
            </p>
            <p class="text-xl font-semibold text-n-ruby-11">
              {{ summary.failed }}
            </p>
          </div>
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.SENTIMENT') }}
            </p>
            <p class="text-sm text-n-slate-12 pt-1">
              🙂 {{ summary.positive }} · 😐 {{ summary.neutral }} · 🙁
              {{ summary.negative }}
            </p>
          </div>
        </div>
      </div>

      <div v-for="day in days" :key="day.date">
        <h2 class="text-sm font-medium text-n-slate-12 mb-2">{{ day.date }}</h2>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-3">
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.TOTAL') }}
            </p>
            <p class="text-xl font-semibold text-n-slate-12">
              {{ day.totals.total }}
            </p>
          </div>
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.PASSED') }}
            </p>
            <p class="text-xl font-semibold text-n-teal-11">
              {{ day.totals.passed }}
            </p>
          </div>
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.FAILED') }}
            </p>
            <p class="text-xl font-semibold text-n-ruby-11">
              {{ day.totals.failed }}
            </p>
          </div>
          <div class="p-3 rounded-lg bg-n-alpha-2">
            <p class="text-xs text-n-slate-11">
              {{ t('JABVOX_AUDIO.REPORTS.SENTIMENT') }}
            </p>
            <p class="text-sm text-n-slate-12">
              🙂 {{ day.totals.positive }} · 😐 {{ day.totals.neutral }} · 🙁
              {{ day.totals.negative }}
            </p>
          </div>
        </div>
        <div
          v-for="job in day.jobs"
          :key="job.id"
          class="mb-3 rounded-lg border border-n-weak overflow-hidden"
        >
          <div
            class="flex justify-between p-2 text-sm bg-n-alpha-1 border-b border-n-weak"
          >
            <span class="text-n-slate-12">
              #{{ job.id }} · {{ job.pipeline || '—' }}
            </span>
            <span class="text-n-slate-11">
              {{ job.passed_count }}/{{ job.total_count }} ·
              {{ t('JABVOX_AUDIO.REPORTS.SCORE') }}
              {{ job.average_score ?? '—' }}
            </span>
          </div>

          <!-- Per-audio results -->
          <div class="divide-y divide-n-weak">
            <div v-for="r in job.results" :key="r.id" class="p-3">
              <div class="flex items-center justify-between gap-2 text-sm">
                <span class="text-n-slate-12 truncate">
                  🎵 {{ fileName(r.file_key) }}
                </span>
                <span class="flex items-center gap-2 shrink-0 text-xs">
                  <span v-if="r.assigned_agent_name" class="text-n-slate-11">
                    👤 {{ r.assigned_agent_name }}
                  </span>
                  <span v-if="r.sentiment" class="text-n-slate-11">
                    {{
                      r.sentiment === 'positive'
                        ? '🙂'
                        : r.sentiment === 'negative'
                          ? '🙁'
                          : '😐'
                    }}
                  </span>
                  <span
                    v-if="r.status === 'completed'"
                    class="px-1.5 py-0.5 rounded-full font-medium"
                    :class="
                      r.passed
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'bg-n-ruby-3 text-n-ruby-11'
                    "
                  >
                    {{ r.passed ? '✅' : '❌' }} {{ r.final_score ?? '—' }}
                  </span>
                  <span v-else class="text-n-slate-11">{{ r.status }}</span>
                </span>
              </div>

              <!-- Why it scored that (per stage) -->
              <div
                v-if="r.stages_data && r.stages_data.length"
                class="mt-2 space-y-1.5"
              >
                <div
                  v-for="(st, si) in r.stages_data"
                  :key="si"
                  class="text-xs"
                >
                  <span class="font-medium text-n-slate-12"
                    >{{ st.name }}: {{ st.score ?? '—' }}/{{
                      st.min_score ?? '—'
                    }}</span
                  >
                  <span v-if="st.reasoning" class="text-n-slate-11">
                    — {{ st.reasoning }}</span
                  >
                </div>
              </div>

              <!-- Transcript (collapsible) -->
              <div v-if="r.transcript" class="mt-2">
                <button
                  class="text-xs text-n-brand hover:underline"
                  @click="toggleTranscript(r.file_key)"
                >
                  {{
                    openTranscript === r.file_key
                      ? t('JABVOX_AUDIO.REPORTS.HIDE_TRANSCRIPT')
                      : t('JABVOX_AUDIO.REPORTS.SHOW_TRANSCRIPT')
                  }}
                </button>
                <pre
                  v-if="openTranscript === r.file_key"
                  class="mt-1 p-2 rounded bg-n-alpha-1 text-xs text-n-slate-12 whitespace-pre-wrap break-words max-h-64 overflow-y-auto"
                  >{{ r.transcript }}</pre
                >
              </div>
            </div>
            <p
              v-if="!job.results || !job.results.length"
              class="p-3 text-xs text-n-slate-11"
            >
              {{ t('JABVOX_AUDIO.REPORTS.NO_RESULTS') }}
            </p>
          </div>
        </div>
      </div>
      <p v-if="!days.length" class="text-center text-n-slate-11 py-10">
        {{ t('JABVOX_AUDIO.REPORTS.EMPTY') }}
      </p>
    </div>
  </div>
</template>
