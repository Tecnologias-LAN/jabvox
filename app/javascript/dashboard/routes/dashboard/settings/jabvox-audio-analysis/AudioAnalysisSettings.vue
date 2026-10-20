<script setup>
import { ref, onMounted, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import {
  audioStoragesAPI,
  audioPipelinesAPI,
  audioJobsAPI,
  audioReportsAPI,
} from 'dashboard/api/jabvox/audioAnalysis';
import { aiChatModelsAPI } from 'dashboard/api/jabvox/aiChat';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';
import { DESTROY_KEY } from 'dashboard/helper/jabvox/nestedAttributes';

import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import StoragesTab from './components/StoragesTab.vue';
import PipelinesTab from './components/PipelinesTab.vue';
import AnalyzerTab from './components/AnalyzerTab.vue';
import JobsTab from './components/JobsTab.vue';
import ConfigTab from './components/ConfigTab.vue';
import StatusRow from './components/StatusRow.vue';
import ConfirmDialog from './components/ConfirmDialog.vue';

const { t } = useI18n();
const store = useStore();
const { markDirty, markClean } = useUnsavedChanges();

// Team agents (for assigning analyzed audios to a responsible agent).
const agents = useMapGetter('agents/getAgents');

// Editor refs (declared up top so setEditorClean can resolve them by key).
const editingStorage = ref(null);
const editingPipeline = ref(null);
const confirmDialog = ref(null);
watch(editingStorage, () => markDirty(), { deep: true });
watch(editingPipeline, () => markDirty(), { deep: true });

// Sets an editor ref without flagging the form dirty (used when opening an
// editor or resetting it after save/cancel). The deep watchers above only mark
// the form dirty on subsequent user edits.
//
// Takes the editor KEY ('storage' | 'pipeline'), not the ref itself: in the
// template, refs auto-unwrap, so passing `editingStorage` would hand this
// function `null` (the unwrapped value) instead of the ref object — breaking
// `ref.value = ...`. Resolving the ref by key here avoids that.
const setEditorClean = async (editorKey, value) => {
  const editorRef = editorKey === 'storage' ? editingStorage : editingPipeline;
  editorRef.value = value;
  await nextTick();
  markClean();
};

// Surfaces the backend's validation message (e.g. a 422 "Name can't be blank")
// instead of a generic error, falling back to the provided i18n key.
const apiErrorMessage = (error, fallbackKey) =>
  error?.response?.data?.error || t(fallbackKey);

const access = ref({ is_admin: false, can_access: false, can_manage: false });
const activeTab = ref('analyzer');

const baseTabs = [
  {
    key: 'analyzer',
    label: () => t('JABVOX_AUDIO.TABS.ANALYZER'),
    icon: 'i-lucide-audio-lines',
    adminOnly: false,
  },
  {
    key: 'jobs',
    label: () => t('JABVOX_AUDIO.TABS.JOBS'),
    icon: 'i-lucide-list-checks',
    adminOnly: false,
  },
  {
    key: 'pipelines',
    label: () => t('JABVOX_AUDIO.TABS.PIPELINES'),
    icon: 'i-lucide-workflow',
    manageOnly: true,
  },
  {
    key: 'storages',
    label: () => t('JABVOX_AUDIO.TABS.STORAGES'),
    icon: 'i-lucide-database',
    manageOnly: true,
  },
  {
    key: 'config',
    label: () => t('JABVOX_AUDIO.TABS.CONFIG'),
    icon: 'i-lucide-settings',
    manageOnly: true,
  },
];
// Pipelines/Storages need the manage capability (admins always qualify).
const canManage = computed(
  () => access.value.can_manage || access.value.is_admin
);
const tabs = computed(() =>
  baseTabs.filter(tab => !tab.manageOnly || canManage.value)
);

// ---------- Storages ----------
const storages = ref([]);
const loadStorages = async () => {
  const { data } = await audioStoragesAPI.getAll();
  storages.value = data.storages || [];
};
const newStorage = () => ({
  name: '',
  use_documents_config: false,
  bucket_name: '',
  bucket_region: 'us-east-1',
  endpoint: '',
  access_key: '',
  secret_key: '',
  path_prefix: '',
});
const saveStorage = async () => {
  try {
    if (editingStorage.value.id)
      await audioStoragesAPI.update(
        editingStorage.value.id,
        editingStorage.value
      );
    else await audioStoragesAPI.create(editingStorage.value);
    await setEditorClean('storage', null);
    await loadStorages();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};
const testStorage = async () => {
  try {
    const { data } = await audioStoragesAPI.test(editingStorage.value);
    useAlert(data.message);
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.TEST_ERROR'));
  }
};
const deleteStorage = id => {
  confirmDialog.value?.open({
    title: t('JABVOX_AUDIO.DELETE'),
    description: t('JABVOX_AUDIO.CONFIRM_DELETE'),
    confirmLabel: t('JABVOX_AUDIO.DELETE'),
    cancelLabel: t('JABVOX_AUDIO.CANCEL'),
    data: { kind: 'storage', id },
  });
};

const doDeleteStorage = async id => {
  await audioStoragesAPI.destroy(id);
  await loadStorages();
};

// ---------- Pipelines ----------
const pipelines = ref([]);
// AI models configured under Settings → Jabvox → AI Chat, reused for
// transcription and stage evaluation.
const aiModels = ref([]);
const typifications = ref([]);
const loadAiModels = async () => {
  if (aiModels.value.length) return;
  const { data } = await aiChatModelsAPI.getAll();
  aiModels.value = data || [];
};
const loadTypifications = async () => {
  if (typifications.value.length) return;
  const { data } = await typificationsAPI.getAll(false);
  typifications.value = data.typifications || [];
};
const loadPipelines = async () => {
  await loadAiModels();
  await loadTypifications();
  const { data } = await audioPipelinesAPI.getAll();
  pipelines.value = data.pipelines || [];
};
const newPipeline = () => ({
  name: '',
  transcription_prompt: '',
  is_default: false,
  timestamp_mode_jabvox: 'none',
  segment_seconds_jabvox: 30,
  stages: [],
});
const deletePipeline = id => {
  confirmDialog.value?.open({
    title: t('JABVOX_AUDIO.DELETE'),
    description: t('JABVOX_AUDIO.CONFIRM_DELETE'),
    confirmLabel: t('JABVOX_AUDIO.DELETE'),
    cancelLabel: t('JABVOX_AUDIO.CANCEL'),
    data: { kind: 'pipeline', id },
  });
};

const doDeletePipeline = async id => {
  await audioPipelinesAPI.destroy(id);
  await loadPipelines();
};

const onConfirmDelete = ({ kind, id }) => {
  if (kind === 'storage') doDeleteStorage(id);
  else if (kind === 'pipeline') doDeletePipeline(id);
};
const addStage = () => {
  editingPipeline.value.stages.push({ name: '', prompt: '', min_score: 60 });
};
const removeStage = index => {
  const stage = editingPipeline.value.stages[index];
  if (stage.id) stage[DESTROY_KEY] = true;
  else editingPipeline.value.stages.splice(index, 1);
};
const savePipeline = async () => {
  if (!editingPipeline.value.name)
    return useAlert(t('JABVOX_AUDIO.PIPELINE.NAME_REQUIRED'));
  if (!editingPipeline.value.stages.filter(s => !s[DESTROY_KEY]).length)
    return useAlert(t('JABVOX_AUDIO.PIPELINE.STAGES_REQUIRED'));
  const payload = {
    name: editingPipeline.value.name,
    transcription_model_id: editingPipeline.value.transcription_model_id,
    typification_id: editingPipeline.value.typification_id,
    transcription_prompt: editingPipeline.value.transcription_prompt,
    is_default: editingPipeline.value.is_default,
    timestamp_mode_jabvox:
      editingPipeline.value.timestamp_mode_jabvox || 'none',
    segment_seconds_jabvox: editingPipeline.value.segment_seconds_jabvox || 30,
    stages_attributes: editingPipeline.value.stages.map((s, i) => ({
      id: s.id,
      name: s.name,
      prompt: s.prompt,
      min_score: s.min_score,
      llm_model_id: s.llm_model_id,
      position: i,
      [DESTROY_KEY]: s[DESTROY_KEY],
    })),
  };
  try {
    if (editingPipeline.value.id)
      await audioPipelinesAPI.update(editingPipeline.value.id, payload);
    else await audioPipelinesAPI.create(payload);
    await setEditorClean('pipeline', null);
    await loadPipelines();
    useAlert(t('JABVOX_AUDIO.SAVED'));
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
  return null;
};

// ---------- Analyzer ----------
const selectedStorageId = ref(null);
const selectedPipelineId = ref(null);
const prefix = ref('');
const search = ref('');
const browser = ref({ folders: [], files: [], next_token: null });
const selectedKeys = ref(new Set());
const browsing = ref(false);

// `browse` lists a folder; an optional search filters files by name within it
// (e.g. "1000532535_" → 1000532535_1, _2, …).
const browse = async (newPrefix = '') => {
  if (!selectedStorageId.value) return;
  browsing.value = true;
  prefix.value = newPrefix;
  try {
    const { data } = await audioStoragesAPI.objects(selectedStorageId.value, {
      prefix: newPrefix,
      search: search.value || undefined,
    });
    browser.value = data;
  } catch (e) {
    useAlert(t('JABVOX_AUDIO.ANALYZER.BROWSE_ERROR'));
  } finally {
    browsing.value = false;
  }
};

// Re-run the listing with the current search term against the current folder.
const runSearch = newSearch => {
  search.value = newSearch;
  browse(prefix.value);
};
const toggleKey = key => {
  if (selectedKeys.value.has(key)) selectedKeys.value.delete(key);
  else selectedKeys.value.add(key);
  selectedKeys.value = new Set(selectedKeys.value);
};

const activeJob = ref(null);
let pollTimer = null;
const pollJob = async () => {
  if (!activeJob.value) return;
  const { data } = await audioJobsAPI.get(activeJob.value.id);
  activeJob.value = data;
  if (data.status === 'completed' || data.status === 'failed') {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};
// Selection is computed in AnalyzerTab (it knows the current page + the
// include-verified toggle); it emits the exact set of keys to select.
const setSelection = keys => {
  selectedKeys.value = new Set(keys);
};
const clearSelection = () => {
  selectedKeys.value = new Set();
};

const launchJob = async () => {
  if (!selectedPipelineId.value || !selectedKeys.value.size) {
    useAlert(t('JABVOX_AUDIO.ANALYZER.SELECT_REQUIRED'));
    return;
  }
  try {
    const { data } = await audioJobsAPI.create({
      pipeline_id: selectedPipelineId.value,
      storage_id: selectedStorageId.value,
      file_keys: Array.from(selectedKeys.value),
    });
    activeJob.value = data;
    selectedKeys.value = new Set();
    pollTimer = setInterval(pollJob, 2000);
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.ANALYZER.LAUNCH_ERROR'));
  }
};

// Assigns typification/agent to the selected audios without analyzing them,
// then refreshes the listing so the table reflects the new assignment.
const assignSelected = async ({ typificationId, agentId }) => {
  if (!selectedKeys.value.size) {
    useAlert(t('JABVOX_AUDIO.ANALYZER.SELECT_REQUIRED'));
    return;
  }
  try {
    await audioStoragesAPI.assign(selectedStorageId.value, {
      file_keys: Array.from(selectedKeys.value),
      typification_id: typificationId || null,
      agent_id: agentId || null,
    });
    useAlert(t('JABVOX_AUDIO.ANALYZER.ASSIGNED'));
    selectedKeys.value = new Set();
    await browse(prefix.value);
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.ANALYZER.ASSIGN_ERROR'));
  }
};

// Audio playback: resolves a short-lived presigned URL on demand and plays it
// in a small floating player. The URL is never stored or listed elsewhere.
const playingUrl = ref(null);
const playingName = ref('');
const playFile = async fileKey => {
  if (!selectedStorageId.value) return;
  try {
    const { data } = await audioStoragesAPI.playback(
      selectedStorageId.value,
      fileKey
    );
    playingUrl.value = data.url;
    playingName.value = fileKey.split('/').pop();
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.ANALYZER.PLAY_ERROR'));
  }
};
const stopPlaying = () => {
  playingUrl.value = null;
  playingName.value = '';
};

// Per-file assignment from the inline row selectors: sets a single file's
// typification/agent without touching the multi-selection.
const assignOne = async ({ fileKey, typificationId, agentId }) => {
  try {
    await audioStoragesAPI.assign(selectedStorageId.value, {
      assignments: [
        {
          file_key: fileKey,
          typification_id: typificationId || null,
          agent_id: agentId || null,
        },
      ],
    });
    await browse(prefix.value);
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.ANALYZER.ASSIGN_ERROR'));
  }
};

// ---------- Jobs history ----------
const jobs = ref([]);
const loadJobs = async () => {
  const { data } = await audioJobsAPI.getAll();
  jobs.value = data.jobs || [];
};

// Per-audio results, loaded lazily when a job row is expanded.
const expandedJobId = ref(null);
const jobResults = ref({}); // { [jobId]: [result, ...] }
const loadingResults = ref(false);
const expandedResultKey = ref(null); // file_key of the result whose transcript is open

const toggleJob = async job => {
  if (expandedJobId.value === job.id) {
    expandedJobId.value = null;
    return;
  }
  expandedJobId.value = job.id;
  expandedResultKey.value = null;
  if (!jobResults.value[job.id]) {
    loadingResults.value = true;
    try {
      const { data } = await audioJobsAPI.results(job.id);
      jobResults.value = { ...jobResults.value, [job.id]: data.results || [] };
    } catch (e) {
      useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.JOBS.RESULTS_ERROR'));
    } finally {
      loadingResults.value = false;
    }
  }
};

const toggleTranscript = key => {
  expandedResultKey.value = expandedResultKey.value === key ? null : key;
};

const switchTab = async key => {
  activeTab.value = key;
  if (key === 'storages' && !storages.value.length) await loadStorages();
  if (key === 'pipelines' && !pipelines.value.length) await loadPipelines();
  if (key === 'jobs') await loadJobs();
  if (key === 'analyzer') {
    if (!storages.value.length) await loadStorages();
    if (!pipelines.value.length) await loadPipelines();
  }
};

// ---------- Header / sidebar (presentational, derived from real state) ----------
const breadcrumbItems = computed(() => [
  { label: t('JABVOX_AUDIO.BREADCRUMB.SETTINGS') },
  { label: 'Jabvox' },
  { label: t('JABVOX_AUDIO.BREADCRUMB.AUDIO') },
]);

// System status derived from what's actually configured — no fabricated metrics.
const aiReady = computed(() => aiModels.value.length > 0);
const storageReady = computed(() => storages.value.length > 0);
const jobsRunning = computed(() =>
  jobs.value.some(j => j.status === 'processing' || j.status === 'pending')
);

const statusEngine = computed(() =>
  aiReady.value
    ? t('JABVOX_AUDIO.SIDEBAR.ENGINE_ON')
    : t('JABVOX_AUDIO.SIDEBAR.ENGINE_OFF')
);
const statusProcessing = computed(() => {
  if (activeJob.value)
    return `${activeJob.value.processed_count}/${activeJob.value.total_count}`;
  return jobsRunning.value
    ? t('JABVOX_AUDIO.SIDEBAR.PROCESSING_ACTIVE')
    : t('JABVOX_AUDIO.SIDEBAR.PROCESSING_IDLE');
});

onMounted(async () => {
  store.dispatch('agents/get');
  try {
    const { data } = await audioReportsAPI.myAccess();
    access.value = data;
  } catch (e) {
    // Don't let an access-check failure blank the management tabs silently.
    useAlert(e?.response?.data?.error || t('JABVOX_AUDIO.ERROR'));
  }
  await switchTab('analyzer');
});
</script>

<template>
  <div class="flex flex-col flex-1 overflow-auto bg-n-background">
    <div class="w-full max-w-[1400px] mx-auto px-6 lg:px-8 py-8">
      <!-- Header -->
      <header class="mb-8">
        <Breadcrumb :items="breadcrumbItems" class="mb-3" />
        <div class="flex items-start gap-4">
          <span
            class="flex items-center justify-center size-12 rounded-2xl bg-n-brand/10 text-n-brand shrink-0"
          >
            <span class="i-lucide-audio-lines size-6" />
          </span>
          <div class="min-w-0">
            <h1 class="text-2xl font-semibold text-n-slate-12 tracking-tight">
              {{ t('JABVOX_AUDIO.TITLE') }}
            </h1>
            <p class="text-sm text-n-slate-11 mt-1 max-w-2xl">
              {{ t('JABVOX_AUDIO.SUBTITLE') }}
            </p>
          </div>
        </div>
      </header>

      <!-- Tabs -->
      <nav
        class="flex items-center gap-1 mb-6 border-b border-n-weak overflow-x-auto"
      >
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="flex items-center gap-2 px-3.5 py-2.5 text-sm font-medium -mb-px border-b-2 whitespace-nowrap transition-colors"
          :class="
            activeTab === tab.key
              ? 'border-n-brand text-n-brand'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="switchTab(tab.key)"
        >
          <span :class="tab.icon" class="size-4" />
          {{ tab.label() }}
        </button>
      </nav>

      <!-- Layout: main 70% + sidebar 30% -->
      <div class="grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-6 items-start">
        <main class="min-w-0">
          <AnalyzerTab
            v-if="activeTab === 'analyzer'"
            v-model:selected-storage-id="selectedStorageId"
            v-model:selected-pipeline-id="selectedPipelineId"
            :storages="storages"
            :pipelines="pipelines"
            :agents="agents"
            :typifications="typifications"
            :prefix="prefix"
            :browser="browser"
            :browsing="browsing"
            :selected-keys="selectedKeys"
            :active-job="activeJob"
            @browse="browse"
            @search="runSearch"
            @toggle-key="toggleKey"
            @set-selection="setSelection"
            @clear-selection="clearSelection"
            @launch="launchJob"
            @assign="assignSelected"
            @assign-one="assignOne"
            @dismiss-job="activeJob = null"
            @play="playFile"
          />

          <JobsTab
            v-else-if="activeTab === 'jobs'"
            :jobs="jobs"
            :expanded-job-id="expandedJobId"
            :job-results="jobResults"
            :loading-results="loadingResults"
            :expanded-result-key="expandedResultKey"
            @toggle-job="toggleJob"
            @toggle-transcript="toggleTranscript"
          />

          <PipelinesTab
            v-else-if="activeTab === 'pipelines'"
            v-model:editing="editingPipeline"
            :pipelines="pipelines"
            :ai-models="aiModels"
            :typifications="typifications"
            @new="setEditorClean('pipeline', newPipeline())"
            @edit="
              setEditorClean('pipeline', JSON.parse(JSON.stringify($event)))
            "
            @delete="deletePipeline"
            @save="savePipeline"
            @cancel="setEditorClean('pipeline', null)"
            @add-stage="addStage"
            @remove-stage="removeStage"
          />

          <StoragesTab
            v-else-if="activeTab === 'storages'"
            v-model:editing="editingStorage"
            :storages="storages"
            @new="setEditorClean('storage', newStorage())"
            @edit="setEditorClean('storage', { ...$event, secret_key: '' })"
            @delete="deleteStorage"
            @save="saveStorage"
            @test="testStorage"
            @cancel="setEditorClean('storage', null)"
          />

          <!-- Configuración QA: asesores, tipificaciones, infaltables,
               cercanía y formatos de archivo (gestiona su propio estado). -->
          <ConfigTab v-else-if="activeTab === 'config'" />
        </main>

        <!-- Sidebar -->
        <aside class="flex flex-col gap-4 lg:sticky lg:top-8">
          <!-- System status -->
          <section
            class="rounded-2xl bg-n-solid-2 outline outline-1 outline-n-weak shadow-sm px-5 py-4"
          >
            <h3
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-1"
            >
              {{ t('JABVOX_AUDIO.SIDEBAR.STATUS_TITLE') }}
            </h3>
            <div class="divide-y divide-n-weak">
              <StatusRow
                :label="t('JABVOX_AUDIO.SIDEBAR.AI')"
                :value="
                  aiReady
                    ? t('JABVOX_AUDIO.SIDEBAR.CONNECTED')
                    : t('JABVOX_AUDIO.SIDEBAR.DISCONNECTED')
                "
                :tone="aiReady ? 'ok' : 'warn'"
                dot
              />
              <StatusRow
                :label="t('JABVOX_AUDIO.SIDEBAR.ENGINE')"
                :value="statusEngine"
                :tone="aiReady ? 'ok' : 'idle'"
                dot
              />
              <StatusRow
                :label="t('JABVOX_AUDIO.SIDEBAR.STORAGE')"
                :value="
                  storageReady
                    ? t('JABVOX_AUDIO.SIDEBAR.CONFIGURED')
                    : t('JABVOX_AUDIO.SIDEBAR.NOT_CONFIGURED')
                "
                :tone="storageReady ? 'ok' : 'warn'"
                dot
              />
              <StatusRow
                :label="t('JABVOX_AUDIO.SIDEBAR.PROCESSING')"
                :value="statusProcessing"
                :tone="jobsRunning || activeJob ? 'warn' : 'idle'"
                dot
              />
            </div>
          </section>

          <!-- Quick stats (real, derived) -->
          <section class="grid grid-cols-2 gap-3">
            <div
              class="rounded-2xl bg-n-solid-2 outline outline-1 outline-n-weak px-4 py-3"
            >
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.SIDEBAR.MODELS') }}
              </p>
              <p class="text-xl font-semibold text-n-slate-12 mt-0.5">
                {{ aiModels.length }}
              </p>
            </div>
            <div
              class="rounded-2xl bg-n-solid-2 outline outline-1 outline-n-weak px-4 py-3"
            >
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.SIDEBAR.PIPELINES') }}
              </p>
              <p class="text-xl font-semibold text-n-slate-12 mt-0.5">
                {{ pipelines.length }}
              </p>
            </div>
            <div
              class="rounded-2xl bg-n-solid-2 outline outline-1 outline-n-weak px-4 py-3"
            >
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.SIDEBAR.STORAGES') }}
              </p>
              <p class="text-xl font-semibold text-n-slate-12 mt-0.5">
                {{ storages.length }}
              </p>
            </div>
            <div
              class="rounded-2xl bg-n-solid-2 outline outline-1 outline-n-weak px-4 py-3"
            >
              <p class="text-xs text-n-slate-11">
                {{ t('JABVOX_AUDIO.SIDEBAR.JOBS') }}
              </p>
              <p class="text-xl font-semibold text-n-slate-12 mt-0.5">
                {{ jobs.length }}
              </p>
            </div>
          </section>

          <!-- Help -->
          <section
            class="rounded-2xl bg-n-brand/5 outline outline-1 outline-n-brand/20 px-5 py-4"
          >
            <p class="flex items-start gap-2 text-sm text-n-slate-11">
              <span class="i-lucide-info size-4 text-n-brand shrink-0 mt-0.5" />
              {{ t('JABVOX_AUDIO.SIDEBAR.HELP') }}
            </p>
          </section>
        </aside>
      </div>
    </div>

    <!-- Floating audio player (presigned URL, expires shortly) -->
    <div
      v-if="playingUrl"
      class="fixed bottom-4 right-4 z-50 w-80 max-w-[calc(100vw-2rem)] rounded-xl bg-n-solid-1 border border-n-weak shadow-xl p-3 flex flex-col gap-2"
    >
      <div class="flex items-center gap-2">
        <span class="i-lucide-music-2 size-4 text-n-brand shrink-0" />
        <span class="flex-1 min-w-0 truncate text-sm text-n-slate-12">
          {{ playingName }}
        </span>
        <button
          type="button"
          class="p-0.5 rounded text-n-slate-10 hover:text-n-slate-12"
          @click="stopPlaying"
        >
          <span class="i-lucide-x size-4" aria-hidden="true" />
        </button>
      </div>
      <audio :src="playingUrl" controls autoplay class="w-full">
        <track kind="captions" />
      </audio>
    </div>

    <ConfirmDialog ref="confirmDialog" @confirm="onConfirmDelete" />
  </div>
</template>
