<script setup>
import { ref, computed, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import voiceBroadcastAPI from 'dashboard/api/jabvox/voiceBroadcast';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Detalle operativo de una campaña de voz: subir audio, arrancar/pausar/reanudar/
// detener, monitor en vivo (poll mientras corre) y reporte final con export CSV.
const emit = defineEmits(['changed']);
const { t } = useI18n();

const POLL_MS = 4000;

const show = ref(false);
const loading = ref(false);
const busy = ref(false);
const uploading = ref(false);
const broadcast = ref(null);
const monitor = ref(null);
const report = ref(null);
const fileInput = ref(null);
let pollTimer = null;

const isRunning = computed(() => broadcast.value?.status === 'running');
const isPaused = computed(() => broadcast.value?.status === 'paused');
const audioReady = computed(() => broadcast.value?.audio_ready === true);
const counts = computed(
  () => monitor.value?.counts || broadcast.value?.counts || {}
);

const audioDuration = computed(() => {
  const ms = broadcast.value?.audio_duration_ms;
  if (!ms) return null;
  return `${Math.round(ms / 100) / 10}s`;
});

const stopPolling = () => {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
};

const refreshMonitor = async () => {
  if (!broadcast.value) return;
  try {
    const { data } = await voiceBroadcastAPI.liveMonitor(broadcast.value.id);
    monitor.value = data;
    if (broadcast.value.status !== data.status) {
      broadcast.value = { ...broadcast.value, status: data.status };
      emit('changed');
    }
    if (data.status !== 'running') stopPolling();
  } catch (e) {
    // silencioso: el poll reintenta
  }
};

const startPolling = () => {
  stopPolling();
  if (isRunning.value) pollTimer = setInterval(refreshMonitor, POLL_MS);
};

const loadReport = async () => {
  if (!broadcast.value) return;
  try {
    const { data } = await voiceBroadcastAPI.report(broadcast.value.id);
    report.value = data;
  } catch (e) {
    report.value = null;
  }
};

const open = async row => {
  show.value = true;
  loading.value = true;
  monitor.value = null;
  report.value = null;
  try {
    const { data } = await voiceBroadcastAPI.show(row.id);
    broadcast.value = data;
    await Promise.all([refreshMonitor(), loadReport()]);
    startPolling();
  } catch (e) {
    useAlert(t('JABVOX_VOICE_BROADCAST.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
};

const close = () => {
  show.value = false;
  stopPolling();
  broadcast.value = null;
};

const control = async action => {
  if (!broadcast.value || busy.value) return;
  busy.value = true;
  try {
    const { data } = await voiceBroadcastAPI[action](broadcast.value.id);
    broadcast.value = { ...broadcast.value, ...data };
    emit('changed');
    await Promise.all([refreshMonitor(), loadReport()]);
    startPolling();
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('JABVOX_VOICE_BROADCAST.CONTROL_ERROR')
    );
  } finally {
    busy.value = false;
  }
};

const pickAudio = () => fileInput.value?.click();

const onAudioSelected = async event => {
  const file = event.target.files?.[0];
  event.target.value = '';
  if (!file || !broadcast.value) return;
  uploading.value = true;
  try {
    const { data } = await voiceBroadcastAPI.uploadAudio(
      broadcast.value.id,
      file
    );
    broadcast.value = {
      ...broadcast.value,
      audio_ready: data.audio_ready,
      audio_duration_ms: data.duration_ms,
      audio_original_name: file.name,
    };
    useAlert(
      data.deployed
        ? t('JABVOX_VOICE_BROADCAST.AUDIO_DEPLOYED')
        : t('JABVOX_VOICE_BROADCAST.AUDIO_UPLOADED_NOT_DEPLOYED')
    );
    emit('changed');
  } catch (e) {
    useAlert(
      e?.response?.data?.error || t('JABVOX_VOICE_BROADCAST.AUDIO_ERROR')
    );
  } finally {
    uploading.value = false;
  }
};

const exportCsv = () => {
  if (!broadcast.value) return;
  window.open(voiceBroadcastAPI.reportCsvUrl(broadcast.value.id), '_blank');
};

onUnmounted(stopPolling);

defineExpose({ open });
</script>

<template>
  <teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-n-alpha-black2 backdrop-blur-sm"
      @click.self="close"
    >
      <div
        class="flex flex-col w-full max-w-3xl max-h-[90vh] rounded-2xl bg-n-solid-1 border border-n-weak shadow-lg overflow-hidden"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-n-weak"
        >
          <div class="min-w-0">
            <h3 class="text-base font-semibold text-n-slate-12 truncate">
              {{ broadcast?.name }}
            </h3>
            <p class="text-xs text-n-slate-11 mt-0.5">
              {{
                t('JABVOX_VOICE_BROADCAST.DETAIL.STATUS_LINE', {
                  status: t(
                    `JABVOX_VOICE_BROADCAST.STATUS.${(broadcast?.status || 'draft').toUpperCase()}`
                  ),
                })
              }}
              <span v-if="monitor" class="ml-2">
                <span
                  :class="
                    monitor.pbx_reachable ? 'text-n-teal-11' : 'text-n-ruby-11'
                  "
                >
                  {{
                    monitor.pbx_reachable
                      ? t('JABVOX_VOICE_BROADCAST.DETAIL.PBX_OK')
                      : t('JABVOX_VOICE_BROADCAST.DETAIL.PBX_DOWN')
                  }}
                </span>
              </span>
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

        <div v-if="loading" class="flex items-center justify-center py-16">
          <Spinner :size="24" />
        </div>

        <div
          v-else
          class="flex-1 overflow-y-auto px-5 py-4 flex flex-col gap-5"
        >
          <!-- Audio -->
          <section class="rounded-lg border border-n-weak p-4">
            <div class="flex items-center justify-between">
              <div>
                <h4 class="text-sm font-medium text-n-slate-12">
                  {{ t('JABVOX_VOICE_BROADCAST.DETAIL.AUDIO_TITLE') }}
                </h4>
                <p class="text-xs text-n-slate-11 mt-0.5">
                  <span v-if="audioReady" class="text-n-teal-11">
                    {{ broadcast?.audio_original_name }}
                    <span v-if="audioDuration">{{ `· ${audioDuration}` }}</span>
                  </span>
                  <span v-else>
                    {{ t('JABVOX_VOICE_BROADCAST.DETAIL.AUDIO_NONE') }}
                  </span>
                </p>
              </div>
              <Button
                :label="t('JABVOX_VOICE_BROADCAST.DETAIL.UPLOAD_AUDIO')"
                icon="i-lucide-upload"
                size="sm"
                variant="outline"
                color="slate"
                :is-loading="uploading"
                :disabled="isRunning || uploading"
                @click="pickAudio"
              />
              <input
                ref="fileInput"
                type="file"
                accept="audio/*"
                class="hidden"
                @change="onAudioSelected"
              />
            </div>
          </section>

          <!-- Controles -->
          <section class="flex flex-wrap items-center gap-2">
            <Button
              v-if="!isRunning && !isPaused"
              :label="t('JABVOX_VOICE_BROADCAST.DETAIL.START')"
              icon="i-lucide-play"
              size="sm"
              :disabled="!audioReady || busy"
              @click="control('start')"
            />
            <Button
              v-if="isRunning"
              :label="t('JABVOX_VOICE_BROADCAST.DETAIL.PAUSE')"
              icon="i-lucide-pause"
              size="sm"
              variant="outline"
              color="amber"
              :disabled="busy"
              @click="control('pause')"
            />
            <Button
              v-if="isPaused"
              :label="t('JABVOX_VOICE_BROADCAST.DETAIL.RESUME')"
              icon="i-lucide-play"
              size="sm"
              :disabled="busy"
              @click="control('resume')"
            />
            <Button
              v-if="isRunning || isPaused"
              :label="t('JABVOX_VOICE_BROADCAST.DETAIL.STOP')"
              icon="i-lucide-square"
              size="sm"
              variant="outline"
              color="ruby"
              :disabled="busy"
              @click="control('stop')"
            />
            <span v-if="!audioReady" class="text-xs text-n-amber-11 ml-1">
              {{ t('JABVOX_VOICE_BROADCAST.DETAIL.NEED_AUDIO') }}
            </span>
          </section>

          <!-- Contadores en vivo -->
          <section class="grid grid-cols-2 md:grid-cols-3 gap-3">
            <div
              v-for="metric in [
                { k: 'total', l: 'TOTAL' },
                { k: 'dialed', l: 'DIALED' },
                { k: 'answered_human', l: 'ANSWERED_HUMAN' },
                { k: 'answered_machine', l: 'ANSWERED_MACHINE' },
                { k: 'played_complete', l: 'PLAYED_COMPLETE' },
                { k: 'failed', l: 'FAILED' },
              ]"
              :key="metric.k"
              class="rounded-lg border border-n-weak px-3 py-2"
            >
              <div class="text-xs text-n-slate-11">
                {{ t(`JABVOX_VOICE_BROADCAST.COUNTS.${metric.l}`) }}
              </div>
              <div class="text-lg font-semibold text-n-slate-12">
                {{ counts[metric.k] ?? 0 }}
              </div>
            </div>
          </section>

          <!-- Reporte -->
          <section v-if="report" class="rounded-lg border border-n-weak p-4">
            <div class="flex items-center justify-between mb-3">
              <h4 class="text-sm font-medium text-n-slate-12">
                {{ t('JABVOX_VOICE_BROADCAST.DETAIL.REPORT_TITLE') }}
              </h4>
              <Button
                :label="t('JABVOX_VOICE_BROADCAST.DETAIL.EXPORT_CSV')"
                icon="i-lucide-download"
                size="xs"
                variant="outline"
                color="slate"
                @click="exportCsv"
              />
            </div>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
              <div>
                <div class="text-xs text-n-slate-11">
                  {{ t('JABVOX_VOICE_BROADCAST.REPORT.ANSWER_RATE') }}
                </div>
                <div class="font-semibold text-n-slate-12">
                  {{ `${report.answer_rate}%` }}
                </div>
              </div>
              <div>
                <div class="text-xs text-n-slate-11">
                  {{ t('JABVOX_VOICE_BROADCAST.REPORT.PLAYED_RATE') }}
                </div>
                <div class="font-semibold text-n-slate-12">
                  {{ `${report.played_complete_rate}%` }}
                </div>
              </div>
              <div>
                <div class="text-xs text-n-slate-11">
                  {{ t('JABVOX_VOICE_BROADCAST.REPORT.ANSWERED_HUMAN') }}
                </div>
                <div class="font-semibold text-n-slate-12">
                  {{ report.answered_human }}
                </div>
              </div>
              <div>
                <div class="text-xs text-n-slate-11">
                  {{ t('JABVOX_VOICE_BROADCAST.REPORT.ANSWERED_MACHINE') }}
                </div>
                <div class="font-semibold text-n-slate-12">
                  {{ report.answered_machine }}
                </div>
              </div>
            </div>
          </section>
        </div>
      </div>
    </div>
  </teleport>
</template>
