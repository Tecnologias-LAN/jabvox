<script setup>
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import SettingsCard from './SettingsCard.vue';
import TranscriptViewer from '../../../jabvox-audio-analysis/components/TranscriptViewer.vue';

defineProps({
  jobs: { type: Array, default: () => [] },
  expandedJobId: { type: [Number, String], default: null },
  jobResults: { type: Object, default: () => ({}) },
  loadingResults: { type: Boolean, default: false },
  expandedResultKey: { type: String, default: null },
});

const emit = defineEmits(['toggle-job', 'toggle-transcript']);

const { t } = useI18n();

// Decorative sentiment/status glyphs (not user-facing prose).
const EMOJI_POSITIVE = '🙂';
const EMOJI_NEUTRAL = '😐';
const EMOJI_NEGATIVE = '🙁';
const EMOJI_AUDIO = '🎵';
const CHECK = '✓';
const CROSS = '✗';

const fileName = key => key.split('/').pop();

const SENTIMENT_EMOJI = { positive: '🙂', negative: '🙁', neutral: '😐' };
const sentimentEmoji = s => SENTIMENT_EMOJI[s] || '😐';

const STATUS_TONE = {
  completed: 'teal',
  processing: 'amber',
  pending: 'slate',
  failed: 'ruby',
};
</script>

<template>
  <SettingsCard
    :title="t('JABVOX_AUDIO.JOBS.TITLE')"
    :description="t('JABVOX_AUDIO.JOBS.SUBTITLE')"
    icon="i-lucide-list-checks"
  >
    <div v-if="jobs.length" class="flex flex-col gap-2">
      <div
        v-for="job in jobs"
        :key="job.id"
        class="rounded-xl border border-n-weak overflow-hidden"
      >
        <!-- Summary row -->
        <button
          class="w-full text-left px-4 py-3 transition-colors hover:bg-n-alpha-1"
          @click="emit('toggle-job', job)"
        >
          <div class="flex items-center justify-between gap-3">
            <span class="flex items-center gap-2 text-sm text-n-slate-12">
              <span
                class="i-lucide-chevron-right size-4 text-n-slate-10 transition-transform"
                :class="expandedJobId === job.id ? 'rotate-90' : ''"
              />
              <span class="font-medium">#{{ job.id }}</span>
              <span
                class="text-xs px-2 py-0.5 rounded-full capitalize"
                :class="{
                  'bg-n-teal-3 text-n-teal-11':
                    STATUS_TONE[job.status] === 'teal',
                  'bg-n-amber-3 text-n-amber-11':
                    STATUS_TONE[job.status] === 'amber',
                  'bg-n-ruby-3 text-n-ruby-11':
                    STATUS_TONE[job.status] === 'ruby',
                  'bg-n-alpha-2 text-n-slate-11':
                    !STATUS_TONE[job.status] ||
                    STATUS_TONE[job.status] === 'slate',
                }"
              >
                {{ job.status }}
              </span>
            </span>
            <span class="text-sm text-n-slate-11 shrink-0">
              {{ job.processed_count }}/{{ job.total_count }} ·
              {{ t('JABVOX_AUDIO.JOBS.SCORE') }}
              <span class="font-medium text-n-slate-12">{{
                job.average_score ?? '—'
              }}</span>
            </span>
          </div>
          <div
            class="flex items-center gap-3 mt-2 pl-6 text-xs text-n-slate-11"
          >
            <span class="text-n-teal-11">✅ {{ job.passed_count }}</span>
            <span class="text-n-ruby-11">❌ {{ job.failed_count }}</span>
            <span class="ml-auto flex items-center gap-2">
              <span>{{ EMOJI_POSITIVE }} {{ job.positive_count }}</span>
              <span>{{ EMOJI_NEUTRAL }} {{ job.neutral_count }}</span>
              <span>{{ EMOJI_NEGATIVE }} {{ job.negative_count }}</span>
            </span>
          </div>
        </button>

        <!-- Expanded per-audio results -->
        <div
          v-if="expandedJobId === job.id"
          class="border-t border-n-weak bg-n-alpha-black1"
        >
          <div
            v-if="loadingResults && !jobResults[job.id]"
            class="flex items-center gap-2 p-4 text-sm text-n-slate-11"
          >
            <Spinner :size="16" />
            {{ t('JABVOX_AUDIO.JOBS.LOADING_RESULTS') }}
          </div>

          <div
            v-for="r in jobResults[job.id] || []"
            :key="r.id"
            class="px-4 py-3 border-t border-n-weak first:border-t-0"
          >
            <div class="flex items-center justify-between gap-2">
              <span
                class="text-sm text-n-slate-12 truncate flex items-center gap-1.5 min-w-0"
              >
                {{ EMOJI_AUDIO }} {{ fileName(r.file_key) }}
              </span>
              <span class="flex items-center gap-2 shrink-0 text-xs">
                <span
                  v-if="r.status === 'completed'"
                  class="px-1.5 py-0.5 rounded-full"
                  :class="
                    r.passed
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-ruby-3 text-n-ruby-11'
                  "
                >
                  {{ r.passed ? '✅' : '❌' }} {{ r.final_score ?? '—' }}
                </span>
                <span v-if="r.sentiment" class="text-n-slate-11">
                  {{ sentimentEmoji(r.sentiment) }}
                </span>
                <span v-if="r.status !== 'completed'" class="text-n-slate-11">
                  {{ r.status }}
                </span>
              </span>
            </div>

            <!-- Stage detail -->
            <div
              v-if="r.stages_data && r.stages_data.length"
              class="mt-2 pl-5 space-y-2"
            >
              <div
                v-for="(st, si) in r.stages_data"
                :key="si"
                class="rounded-lg bg-n-solid-2 border border-n-weak p-2.5"
              >
                <div class="flex items-center gap-2 text-xs">
                  <span
                    class="font-semibold px-1.5 py-0.5 rounded"
                    :class="
                      st.passed
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'bg-n-amber-3 text-n-amber-11'
                    "
                  >
                    {{ st.score ?? '—' }}/{{ st.min_score ?? '—' }}
                  </span>
                  <span class="font-medium text-n-slate-12">{{ st.name }}</span>
                  <span
                    v-if="st.escalated"
                    class="text-[10px] px-1 py-0.5 rounded bg-n-amber-3 text-n-amber-11"
                  >
                    {{ t('JABVOX_AUDIO.JOBS.ESCALATED') }}
                  </span>
                </div>
                <p
                  v-if="st.reasoning"
                  class="text-xs text-n-slate-11 mt-1 whitespace-pre-wrap break-words"
                >
                  {{ st.reasoning }}
                </p>
                <ul
                  v-if="st.highlights && st.highlights.length"
                  class="reset-base mt-1 space-y-0.5"
                >
                  <li
                    v-for="(h, hi) in st.highlights"
                    :key="`h${hi}`"
                    class="text-xs text-n-teal-11"
                  >
                    {{ CHECK }} {{ h }}
                  </li>
                </ul>
                <ul
                  v-if="st.issues && st.issues.length"
                  class="reset-base mt-0.5 space-y-0.5"
                >
                  <li
                    v-for="(iss, ii) in st.issues"
                    :key="`i${ii}`"
                    class="text-xs text-n-ruby-11"
                  >
                    {{ CROSS }} {{ iss }}
                  </li>
                </ul>
              </div>
            </div>

            <p v-if="r.error_message" class="text-xs text-n-ruby-11 mt-1 pl-5">
              {{ r.error_message }}
            </p>

            <!-- Transcript (collapsible) -->
            <div
              v-if="r.transcript || r.transcript_words?.length"
              class="mt-2 pl-5"
            >
              <button
                class="text-xs text-n-brand hover:underline"
                @click="emit('toggle-transcript', r.file_key)"
              >
                {{
                  expandedResultKey === r.file_key
                    ? t('JABVOX_AUDIO.JOBS.HIDE_TRANSCRIPT')
                    : t('JABVOX_AUDIO.JOBS.SHOW_TRANSCRIPT')
                }}
              </button>
              <!-- Searchable transcript (by word, or by time when timestamped). -->
              <TranscriptViewer
                v-if="expandedResultKey === r.file_key"
                class="mt-1"
                :words="r.transcript_words || []"
                :text="r.transcript || ''"
              />
            </div>
          </div>

          <p
            v-if="
              jobResults[job.id] &&
              !jobResults[job.id].length &&
              !loadingResults
            "
            class="p-4 text-sm text-n-slate-11"
          >
            {{ t('JABVOX_AUDIO.JOBS.NO_RESULTS') }}
          </p>
        </div>
      </div>
    </div>

    <EmptyStateLayout
      v-else
      :title="t('JABVOX_AUDIO.JOBS.EMPTY_TITLE')"
      :subtitle="t('JABVOX_AUDIO.JOBS.EMPTY')"
      :show-backdrop="false"
    />
  </SettingsCard>
</template>
