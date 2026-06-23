<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { audioReportsAPI } from 'dashboard/api/jabvox/audioAnalysis';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

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

const resetFilters = () => {
  filters.value = {
    from: '',
    to: '',
    pipeline_id: '',
    agent_id: '',
    score_op: '',
    score_value: '',
  };
  load();
};

const pipelineOptions = () => [
  { value: '', label: t('JABVOX_AUDIO.REPORTS.ALL') },
  ...filterOptions.value.pipelines.map(p => ({ value: p.id, label: p.name })),
];
const agentOptions = () => [
  { value: '', label: t('JABVOX_AUDIO.REPORTS.ALL') },
  ...filterOptions.value.agents.map(a => ({ value: a.id, label: a.name })),
];
const scoreOpOptions = () => [
  { value: '', label: t('JABVOX_AUDIO.REPORTS.ALL') },
  { value: 'gte', label: t('JABVOX_AUDIO.REPORTS.GTE') },
  { value: 'lt', label: t('JABVOX_AUDIO.REPORTS.LT') },
];

const SENTIMENT_EMOJI = { positive: '🙂', negative: '🙁' };
const sentimentEmoji = s => SENTIMENT_EMOJI[s] || '😐';

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
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      class="mx-auto w-full max-w-5xl flex flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8 lg:px-8"
    >
      <!-- Header -->
      <div class="flex items-start gap-3 min-w-0">
        <span
          class="i-lucide-audio-lines size-9 shrink-0 rounded-xl bg-n-alpha-2 p-2 text-n-brand"
        />
        <div class="min-w-0">
          <h1 class="text-xl font-semibold tracking-tight text-n-slate-12">
            {{ t('JABVOX_AUDIO.REPORTS.TITLE') }}
          </h1>
          <p class="mt-1 max-w-2xl text-sm leading-relaxed text-n-slate-11">
            {{ t('JABVOX_AUDIO.REPORTS.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <!-- Filters -->
      <div
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm flex flex-col gap-4"
      >
        <div class="flex items-center gap-2">
          <span class="i-lucide-sliders-horizontal size-4 text-n-slate-11" />
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('JABVOX_AUDIO.REPORTS.FILTERS') }}
          </span>
        </div>

        <div
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 items-end"
        >
          <Input
            v-model="filters.from"
            type="date"
            :label="t('JABVOX_AUDIO.REPORTS.FROM')"
          />
          <Input
            v-model="filters.to"
            type="date"
            :label="t('JABVOX_AUDIO.REPORTS.TO')"
          />
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AUDIO.REPORTS.PIPELINE') }}
            </label>
            <Select
              v-model="filters.pipeline_id"
              :options="pipelineOptions()"
            />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AUDIO.REPORTS.AGENT') }}
            </label>
            <Select v-model="filters.agent_id" :options="agentOptions()" />
          </div>
          <div class="flex flex-col gap-1.5">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('JABVOX_AUDIO.REPORTS.SCORE_FILTER') }}
            </label>
            <div class="flex gap-2">
              <div class="flex-1">
                <Select
                  v-model="filters.score_op"
                  :options="scoreOpOptions()"
                />
              </div>
              <div class="w-20">
                <Input
                  v-model="filters.score_value"
                  type="number"
                  min="0"
                  max="100"
                  :placeholder="t('JABVOX_AUDIO.REPORTS.SCORE_PLACEHOLDER')"
                />
              </div>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2 pt-1">
          <Button
            :label="t('JABVOX_AUDIO.REPORTS.APPLY')"
            icon="i-lucide-search"
            size="sm"
            @click="load"
          />
          <Button
            :label="t('JABVOX_AUDIO.REPORTS.TODAY')"
            variant="outline"
            color="slate"
            size="sm"
            @click="applyPreset('today')"
          />
          <Button
            :label="t('JABVOX_AUDIO.REPORTS.LAST_7D')"
            variant="outline"
            color="slate"
            size="sm"
            @click="applyPreset('7d')"
          />
          <Button
            :label="t('JABVOX_AUDIO.REPORTS.LAST_30D')"
            variant="outline"
            color="slate"
            size="sm"
            @click="applyPreset('30d')"
          />
          <div class="flex-1" />
          <Button
            :label="t('JABVOX_AUDIO.REPORTS.RESET')"
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
        {{ t('JABVOX_AUDIO.REPORTS.LOADING') }}
      </div>

      <template v-else>
        <!-- Overall summary across the whole filtered range -->
        <div
          v-if="summary && summary.total"
          class="rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
        >
          <p class="text-sm font-medium text-n-slate-12 mb-3">
            {{ t('JABVOX_AUDIO.REPORTS.SUMMARY') }}
          </p>
          <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
            <div class="p-3 rounded-xl bg-n-alpha-1">
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.REPORTS.TOTAL') }}
              </p>
              <p class="text-xl font-semibold text-n-slate-12">
                {{ summary.total }}
              </p>
            </div>
            <div class="p-3 rounded-xl bg-n-alpha-1">
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
            <div class="p-3 rounded-xl bg-n-alpha-1">
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.REPORTS.PASSED') }}
              </p>
              <p class="text-xl font-semibold text-n-teal-11">
                {{ summary.passed }}
              </p>
            </div>
            <div class="p-3 rounded-xl bg-n-alpha-1">
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.REPORTS.FAILED') }}
              </p>
              <p class="text-xl font-semibold text-n-ruby-11">
                {{ summary.failed }}
              </p>
            </div>
            <div class="p-3 rounded-xl bg-n-alpha-1">
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

        <!-- Days -->
        <div v-for="day in days" :key="day.date" class="flex flex-col gap-3">
          <h2
            class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
          >
            <span class="i-lucide-calendar size-4 text-n-slate-10" />
            {{ day.date }}
          </h2>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <div class="p-3 rounded-xl border border-n-weak bg-n-solid-1">
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.REPORTS.TOTAL') }}
              </p>
              <p class="text-xl font-semibold text-n-slate-12">
                {{ day.totals.total }}
              </p>
            </div>
            <div class="p-3 rounded-xl border border-n-weak bg-n-solid-1">
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.REPORTS.PASSED') }}
              </p>
              <p class="text-xl font-semibold text-n-teal-11">
                {{ day.totals.passed }}
              </p>
            </div>
            <div class="p-3 rounded-xl border border-n-weak bg-n-solid-1">
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.REPORTS.FAILED') }}
              </p>
              <p class="text-xl font-semibold text-n-ruby-11">
                {{ day.totals.failed }}
              </p>
            </div>
            <div class="p-3 rounded-xl border border-n-weak bg-n-solid-1">
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.REPORTS.SENTIMENT') }}
              </p>
              <p class="text-sm text-n-slate-12">
                🙂 {{ day.totals.positive }} · 😐 {{ day.totals.neutral }} · 🙁
                {{ day.totals.negative }}
              </p>
            </div>
          </div>

          <!-- Jobs -->
          <div
            v-for="job in day.jobs"
            :key="job.id"
            class="rounded-2xl border border-n-weak bg-n-solid-1 shadow-sm overflow-hidden"
          >
            <div
              class="flex flex-wrap justify-between gap-2 px-4 py-2.5 text-sm bg-n-alpha-1 border-b border-n-weak"
            >
              <span class="font-medium text-n-slate-12">
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
              <div
                v-for="r in job.results"
                :key="r.id"
                class="p-3 hover:bg-n-alpha-1 transition-colors"
              >
                <div class="flex items-center justify-between gap-2 text-sm">
                  <span
                    class="text-n-slate-12 truncate flex items-center gap-1.5"
                  >
                    <span
                      class="i-lucide-music size-3.5 text-n-slate-10 shrink-0"
                    />
                    {{ fileName(r.file_key) }}
                  </span>
                  <span class="flex items-center gap-2 shrink-0 text-xs">
                    <span
                      v-if="r.assigned_agent_name"
                      class="text-n-slate-11 flex items-center gap-1"
                    >
                      <span class="i-lucide-user size-3" />
                      {{ r.assigned_agent_name }}
                    </span>
                    <span v-if="r.sentiment" class="text-n-slate-11">
                      {{ sentimentEmoji(r.sentiment) }}
                    </span>
                    <span
                      v-if="r.status === 'completed'"
                      class="px-2 py-0.5 rounded-full font-medium"
                      :class="
                        r.passed
                          ? 'bg-n-teal-3 text-n-teal-11'
                          : 'bg-n-ruby-3 text-n-ruby-11'
                      "
                    >
                      {{ r.passed ? '✅' : '❌' }} {{ r.final_score ?? '—' }}
                    </span>
                    <span
                      v-else
                      class="px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11"
                      >{{ r.status }}</span
                    >
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
                    class="text-xs text-n-brand hover:underline inline-flex items-center gap-1"
                    @click="toggleTranscript(r.file_key)"
                  >
                    <span
                      class="size-3"
                      :class="
                        openTranscript === r.file_key
                          ? 'i-lucide-chevron-up'
                          : 'i-lucide-chevron-down'
                      "
                    />
                    {{
                      openTranscript === r.file_key
                        ? t('JABVOX_AUDIO.REPORTS.HIDE_TRANSCRIPT')
                        : t('JABVOX_AUDIO.REPORTS.SHOW_TRANSCRIPT')
                    }}
                  </button>
                  <pre
                    v-if="openTranscript === r.file_key"
                    class="mt-1 p-3 rounded-xl bg-n-alpha-1 text-xs text-n-slate-12 whitespace-pre-wrap break-words max-h-64 overflow-y-auto"
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

        <!-- Empty -->
        <EmptyStateLayout
          v-if="!days.length"
          :title="t('JABVOX_AUDIO.REPORTS.EMPTY_TITLE')"
          :subtitle="t('JABVOX_AUDIO.REPORTS.EMPTY')"
        />
      </template>
    </div>
  </div>
</template>
