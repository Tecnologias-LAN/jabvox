<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { cdrReportsAPI } from 'dashboard/api/jabvox/cdr';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TranscriptViewer from '../jabvox-audio-analysis/components/TranscriptViewer.vue';

const props = defineProps({
  call: { type: Object, required: true },
  existing: { type: Object, default: null },
});

const emit = defineEmits(['close', 'updated', 'typified']);

const { t } = useI18n();

// ── Typification (manual, per call) ─────────────────────────────────────────
const typifications = ref([]);
const selectedTypificationId = ref(props.call.typification_id || '');
const savingTypification = ref(false);

const loadTypifications = async () => {
  try {
    const { data } = await typificationsAPI.getAll(true);
    typifications.value = data.typifications || [];
  } catch {
    typifications.value = [];
  }
};

const saveTypification = async () => {
  savingTypification.value = true;
  try {
    const { data } = await cdrReportsAPI.typify(
      props.call.uniqueid,
      selectedTypificationId.value || null
    );
    emit('typified', {
      uniqueid: props.call.uniqueid,
      typification_id: data.typification_id,
      typification: data.typification,
    });
    useAlert(t('JABVOX_CDR.ANALYSIS.TYPIFY_SAVED'));
  } catch {
    useAlert(t('JABVOX_CDR.ANALYSIS.TYPIFY_ERROR'));
  } finally {
    savingTypification.value = false;
  }
};

// Decorative separator between source and destination numbers.
const ARROW = '→';

const analysis = ref(props.existing || null);
const loading = ref(false);

// Recording playback: fetched once as a local blob URL. The PBX path/credentials
// never reach the client and no public/presigned URL is created.
const recordingUrl = ref(null);
const loadingRecording = ref(false);
const loadRecording = async () => {
  if (recordingUrl.value || loadingRecording.value) return;
  loadingRecording.value = true;
  try {
    recordingUrl.value = await cdrReportsAPI.recordingObjectUrl(
      props.call.uniqueid
    );
  } catch {
    recordingUrl.value = null;
  } finally {
    loadingRecording.value = false;
  }
};

const close = () => {
  if (recordingUrl.value) URL.revokeObjectURL(recordingUrl.value);
  emit('close');
};

const runAnalysis = async (force = false) => {
  loading.value = true;
  try {
    const { data } = await cdrReportsAPI.analyze({
      uniqueid: props.call.uniqueid,
      force,
    });
    analysis.value = data;
    emit('updated', data);
  } catch (error) {
    analysis.value = { status: 'error', error_message: error?.message };
  } finally {
    loading.value = false;
  }
};

// Auto-run on open only when there is no analyzed result yet.
// (Correctly triggered from onMounted — not from a useState initializer.)
onMounted(() => {
  loadTypifications();
  if (!analysis.value || analysis.value.status !== 'analyzed') {
    runAnalysis(false);
  }
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black2 p-4"
    @click.self="close"
  >
    <div
      class="w-full max-w-2xl max-h-[85vh] overflow-auto rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
    >
      <div class="flex items-start justify-between mb-4 gap-3">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ t('JABVOX_CDR.ANALYSIS.TITLE') }}
          </h2>
          <p class="text-sm text-n-slate-11 truncate">
            {{ call.src }} {{ ARROW }} {{ call.dst }}
          </p>
          <p
            v-if="call.origin_channel"
            class="text-xs text-n-slate-10 truncate mt-0.5"
          >
            {{ t('JABVOX_CDR.REPORTS.TABLE.ORIGIN_CHANNEL') }}:
            {{ call.origin_channel }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          size="sm"
          @click="close"
        />
      </div>

      <!-- Recording playback: available whenever the call has a recording,
           independent of the AI analysis status. -->
      <div
        v-if="call.recording_file"
        class="rounded-xl border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2 mb-4"
      >
        <div class="flex items-center gap-2">
          <span class="i-lucide-music-2 size-4 text-n-brand" />
          <span class="text-sm font-medium text-n-slate-11">
            {{ t('JABVOX_CDR.ANALYSIS.RECORDING') }}
          </span>
          <Button
            v-if="!recordingUrl"
            class="ml-auto"
            size="sm"
            variant="outline"
            color="slate"
            icon="i-lucide-play"
            :is-loading="loadingRecording"
            :label="t('JABVOX_CDR.ANALYSIS.LISTEN')"
            @click="loadRecording"
          />
        </div>
        <audio v-if="recordingUrl" :src="recordingUrl" controls class="w-full">
          <track kind="captions" />
        </audio>
      </div>

      <!-- Manual typification: available for any call, independent of AI. -->
      <div
        class="rounded-xl border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2 mb-4"
      >
        <span class="text-sm font-medium text-n-slate-11">
          {{ t('JABVOX_CDR.REPORTS.TABLE.TYPIFICATION') }}
        </span>
        <div class="flex items-center gap-2">
          <select
            v-model="selectedTypificationId"
            class="reset-base flex-1 text-sm rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12"
          >
            <option value="">
              {{ t('JABVOX_CDR.ANALYSIS.TYPIFY_NONE') }}
            </option>
            <option v-for="tp in typifications" :key="tp.id" :value="tp.id">
              {{ tp.name }}
            </option>
          </select>
          <Button
            size="sm"
            color="brand"
            icon="i-lucide-check"
            :is-loading="savingTypification"
            :label="t('JABVOX_CDR.ANALYSIS.TYPIFY_SAVE')"
            @click="saveTypification"
          />
        </div>
      </div>

      <div
        v-if="loading"
        class="flex items-center justify-center gap-2 py-10 text-sm text-n-slate-11"
      >
        <Spinner :size="18" />
        {{ t('JABVOX_CDR.ANALYSIS.RUNNING') }}
      </div>

      <div
        v-else-if="analysis?.status === 'error'"
        class="p-4 rounded-xl border border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11 text-sm"
      >
        {{ analysis.error_message || t('JABVOX_CDR.ANALYSIS.ERROR') }}
        <div class="mt-3">
          <Button
            :label="t('JABVOX_CDR.ANALYSIS.RETRY')"
            icon="i-lucide-rotate-cw"
            color="ruby"
            size="sm"
            @click="runAnalysis(true)"
          />
        </div>
      </div>

      <div v-else-if="analysis?.status === 'analyzed'" class="space-y-4">
        <!-- Final score -->
        <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4">
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-sm text-n-slate-11">{{
              t('JABVOX_CDR.ANALYSIS.FINAL_SCORE')
            }}</span>
            <span class="text-lg font-semibold text-n-brand">{{
              analysis.final_score ?? '—'
            }}</span>
          </div>
          <div class="h-2 rounded-full bg-n-alpha-3 overflow-hidden">
            <div
              class="h-full bg-n-brand rounded-full transition-all"
              :style="{ width: `${analysis.final_score || 0}%` }"
            />
          </div>
        </div>

        <!-- Stages -->
        <div
          v-for="stage in analysis.stages_data"
          :key="stage.stage_id"
          class="p-3 rounded-xl border border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="font-medium text-n-slate-12">{{ stage.name }}</span>
            <span
              class="text-xs px-2 py-0.5 rounded-full font-medium"
              :class="
                stage.passed
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-ruby-3 text-n-ruby-11'
              "
            >
              {{ stage.score ?? '—' }} / {{ stage.min_score }}
            </span>
          </div>
          <p v-if="stage.reasoning" class="mt-1 text-sm text-n-slate-11">
            {{ stage.reasoning }}
          </p>
          <ul
            v-if="stage.highlights?.length"
            class="mt-2 text-xs text-n-teal-11 list-disc list-inside space-y-0.5"
          >
            <li v-for="(h, i) in stage.highlights" :key="`h${i}`">{{ h }}</li>
          </ul>
          <ul
            v-if="stage.issues?.length"
            class="mt-1 text-xs text-n-ruby-11 list-disc list-inside space-y-0.5"
          >
            <li v-for="(iss, i) in stage.issues" :key="`i${i}`">{{ iss }}</li>
          </ul>
        </div>

        <!-- Searchable transcript (by word, or by time when timestamped). -->
        <details class="rounded-xl border border-n-weak bg-n-alpha-1 p-3" open>
          <summary
            class="cursor-pointer text-sm font-medium text-n-slate-11 select-none mb-2"
          >
            {{ t('JABVOX_CDR.ANALYSIS.TRANSCRIPT') }}
          </summary>
          <TranscriptViewer
            :words="analysis.transcript_words || []"
            :text="analysis.transcript || ''"
          />
        </details>

        <div class="flex justify-end">
          <Button
            :label="t('JABVOX_CDR.ANALYSIS.REANALYZE')"
            icon="i-lucide-rotate-cw"
            variant="outline"
            color="slate"
            size="sm"
            @click="runAnalysis(true)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
