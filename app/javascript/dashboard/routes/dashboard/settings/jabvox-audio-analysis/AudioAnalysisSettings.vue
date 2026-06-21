<script setup>
/* eslint-disable no-underscore-dangle */
// _destroy is the Rails accepts_nested_attributes_for convention.
import { ref, onMounted, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import {
  audioStoragesAPI,
  audioPipelinesAPI,
  audioJobsAPI,
  audioAccessAPI,
  audioReportsAPI,
} from 'dashboard/api/jabvox/audioAnalysis';
import { aiChatModelsAPI } from 'dashboard/api/jabvox/aiChat';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';

const { t } = useI18n();
const store = useStore();
const { markDirty, markClean } = useUnsavedChanges();

// Team agents (for assigning analyzed audios to a responsible agent).
const agents = useMapGetter('agents/getAgents');

// Editor refs (declared up top so setEditorClean can resolve them by key).
const editingStorage = ref(null);
const editingPipeline = ref(null);
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

const access = ref({ is_admin: false, can_access: false });
const activeTab = ref('analyzer');

const baseTabs = [
  {
    key: 'storages',
    label: () => t('JABVOX_AUDIO.TABS.STORAGES'),
    adminOnly: true,
  },
  {
    key: 'pipelines',
    label: () => t('JABVOX_AUDIO.TABS.PIPELINES'),
    adminOnly: true,
  },
  {
    key: 'analyzer',
    label: () => t('JABVOX_AUDIO.TABS.ANALYZER'),
    adminOnly: false,
  },
  { key: 'jobs', label: () => t('JABVOX_AUDIO.TABS.JOBS'), adminOnly: false },
  {
    key: 'access',
    label: () => t('JABVOX_AUDIO.TABS.ACCESS'),
    adminOnly: true,
  },
];
const tabs = computed(() =>
  baseTabs.filter(tab => !tab.adminOnly || access.value.is_admin)
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
const deleteStorage = async id => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('JABVOX_AUDIO.CONFIRM_DELETE'))) return;
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
  stages: [],
});
const deletePipeline = async id => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('JABVOX_AUDIO.CONFIRM_DELETE'))) return;
  await audioPipelinesAPI.destroy(id);
  await loadPipelines();
};
const addStage = () => {
  editingPipeline.value.stages.push({ name: '', prompt: '', min_score: 60 });
};
const removeStage = index => {
  const stage = editingPipeline.value.stages[index];
  if (stage.id) stage._destroy = true;
  else editingPipeline.value.stages.splice(index, 1);
};
const savePipeline = async () => {
  if (!editingPipeline.value.name)
    return useAlert(t('JABVOX_AUDIO.PIPELINE.NAME_REQUIRED'));
  if (!editingPipeline.value.stages.filter(s => !s._destroy).length)
    return useAlert(t('JABVOX_AUDIO.PIPELINE.STAGES_REQUIRED'));
  const payload = {
    name: editingPipeline.value.name,
    transcription_model_id: editingPipeline.value.transcription_model_id,
    typification_id: editingPipeline.value.typification_id,
    transcription_prompt: editingPipeline.value.transcription_prompt,
    is_default: editingPipeline.value.is_default,
    stages_attributes: editingPipeline.value.stages.map((s, i) => ({
      id: s.id,
      name: s.name,
      prompt: s.prompt,
      min_score: s.min_score,
      llm_model_id: s.llm_model_id,
      position: i,
      _destroy: s._destroy,
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
const browser = ref({ folders: [], files: [], next_token: null });
const selectedKeys = ref(new Set());
const browsing = ref(false);

const browse = async (newPrefix = '') => {
  if (!selectedStorageId.value) return;
  browsing.value = true;
  prefix.value = newPrefix;
  try {
    const { data } = await audioStoragesAPI.objects(selectedStorageId.value, {
      prefix: newPrefix,
    });
    browser.value = data;
  } catch (e) {
    useAlert(t('JABVOX_AUDIO.ANALYZER.BROWSE_ERROR'));
  } finally {
    browsing.value = false;
  }
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
// Optional agent the selected audios get assigned to (responsible advisor).
const assignedAgentId = ref(null);

// Bulk selection: pick the first N audio files currently listed (or all).
const selectAudios = count => {
  const keys = browser.value.files.map(f => f.key);
  const picked = count === 'all' ? keys : keys.slice(0, count);
  selectedKeys.value = new Set(picked);
};
const clearSelection = () => {
  selectedKeys.value = new Set();
};
const SELECT_PRESETS = [10, 25, 50, 100];

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
      assigned_agent_id: assignedAgentId.value || null,
    });
    activeJob.value = data;
    selectedKeys.value = new Set();
    pollTimer = setInterval(pollJob, 2000);
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.ANALYZER.LAUNCH_ERROR'));
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

const fileName = key => key.split('/').pop();

// ---------- Access ----------
const users = ref([]);
const loadUsers = async () => {
  const { data } = await audioAccessAPI.users();
  users.value = data.users || [];
};
const updateUser = async user => {
  try {
    await audioAccessAPI.updateUser({
      user_id: user.user_id,
      can_access: user.can_access,
      can_view_reports: user.can_view_reports,
    });
  } catch (e) {
    useAlert(apiErrorMessage(e, 'JABVOX_AUDIO.SAVE_ERROR'));
  }
};

const switchTab = async key => {
  activeTab.value = key;
  if (key === 'storages' && !storages.value.length) await loadStorages();
  if (key === 'pipelines' && !pipelines.value.length) await loadPipelines();
  if (key === 'jobs') await loadJobs();
  if (key === 'access' && !users.value.length) await loadUsers();
  if (key === 'analyzer') {
    if (!storages.value.length) await loadStorages();
    if (!pipelines.value.length) await loadPipelines();
  }
};

onMounted(async () => {
  store.dispatch('agents/get');
  const { data } = await audioReportsAPI.myAccess();
  access.value = data;
  await switchTab('analyzer');
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -- symbols/region defaults are universal -->
  <div class="flex flex-col flex-1 overflow-auto p-6">
    <h1 class="text-xl font-medium text-n-slate-12 mb-1">
      {{ t('JABVOX_AUDIO.TITLE') }}
    </h1>
    <p class="text-sm text-n-slate-11 mb-4">{{ t('JABVOX_AUDIO.SUBTITLE') }}</p>

    <div class="flex gap-2 mb-6 border-b border-n-weak">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        class="px-4 py-2 text-sm -mb-px border-b-2"
        :class="
          activeTab === tab.key
            ? 'border-n-brand text-n-brand'
            : 'border-transparent text-n-slate-11'
        "
        @click="switchTab(tab.key)"
      >
        {{ tab.label() }}
      </button>
    </div>

    <!-- Storages tab -->
    <section v-if="activeTab === 'storages'" class="max-w-2xl">
      <div v-if="!editingStorage">
        <button
          class="mb-4 px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
          @click="setEditorClean('storage', newStorage())"
        >
          {{ t('JABVOX_AUDIO.STORAGE.NEW') }}
        </button>
        <div
          v-for="s in storages"
          :key="s.id"
          class="flex items-center justify-between p-3 mb-2 rounded-lg bg-n-alpha-2"
        >
          <div>
            <span class="font-medium text-n-slate-12">{{ s.name }}</span>
            <span class="ml-2 text-xs text-n-slate-11">
              {{
                s.use_documents_config
                  ? t('JABVOX_AUDIO.STORAGE.USES_DOCS')
                  : s.bucket_name
              }}
            </span>
          </div>
          <div class="flex gap-2">
            <button
              class="text-sm text-n-slate-11"
              @click="setEditorClean('storage', { ...s, secret_key: '' })"
            >
              {{ t('JABVOX_AUDIO.EDIT') }}
            </button>
            <button class="text-sm text-n-ruby-11" @click="deleteStorage(s.id)">
              {{ t('JABVOX_AUDIO.DELETE') }}
            </button>
          </div>
        </div>
        <p v-if="!storages.length" class="text-sm text-n-slate-11">
          {{ t('JABVOX_AUDIO.STORAGE.EMPTY') }}
        </p>
      </div>

      <div v-else class="space-y-3">
        <input
          v-model="editingStorage.name"
          class="reset-base text-sm w-full"
          :placeholder="t('JABVOX_AUDIO.STORAGE.NAME')"
        />
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          <input
            v-model="editingStorage.use_documents_config"
            type="checkbox"
          />
          {{ t('JABVOX_AUDIO.STORAGE.USE_DOCS') }}
        </label>
        <template v-if="!editingStorage.use_documents_config">
          <div class="grid grid-cols-2 gap-3">
            <input
              v-model="editingStorage.bucket_name"
              class="reset-base text-sm"
              :placeholder="t('JABVOX_AUDIO.STORAGE.BUCKET')"
            />
            <input
              v-model="editingStorage.bucket_region"
              class="reset-base text-sm"
              placeholder="us-east-1"
            />
            <input
              v-model="editingStorage.endpoint"
              class="reset-base text-sm col-span-2"
              :placeholder="t('JABVOX_AUDIO.STORAGE.ENDPOINT')"
            />
            <input
              v-model="editingStorage.access_key"
              class="reset-base text-sm"
              :placeholder="t('JABVOX_AUDIO.STORAGE.ACCESS_KEY')"
            />
            <input
              v-model="editingStorage.secret_key"
              type="password"
              class="reset-base text-sm"
              :placeholder="t('JABVOX_AUDIO.STORAGE.SECRET_KEY')"
            />
          </div>
        </template>
        <input
          v-model="editingStorage.path_prefix"
          class="reset-base text-sm w-full"
          :placeholder="t('JABVOX_AUDIO.STORAGE.PATH_PREFIX')"
        />
        <div class="flex gap-3">
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
            @click="saveStorage"
          >
            {{ t('JABVOX_AUDIO.SAVE') }}
          </button>
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
            @click="testStorage"
          >
            {{ t('JABVOX_AUDIO.TEST') }}
          </button>
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
            @click="setEditorClean('storage', null)"
          >
            {{ t('JABVOX_AUDIO.CANCEL') }}
          </button>
        </div>
      </div>
    </section>

    <!-- Pipelines tab -->
    <section v-else-if="activeTab === 'pipelines'" class="max-w-3xl">
      <div v-if="!editingPipeline">
        <button
          class="mb-4 px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
          @click="setEditorClean('pipeline', newPipeline())"
        >
          {{ t('JABVOX_AUDIO.PIPELINE.NEW') }}
        </button>
        <div
          v-for="p in pipelines"
          :key="p.id"
          class="flex items-center justify-between p-3 mb-2 rounded-lg bg-n-alpha-2"
        >
          <div>
            <span class="font-medium text-n-slate-12">{{ p.name }}</span>
            <span v-if="p.is_default" class="ml-2 text-xs text-n-brand">{{
              t('JABVOX_AUDIO.PIPELINE.DEFAULT')
            }}</span>
          </div>
          <div class="flex gap-2">
            <button
              class="text-sm text-n-slate-11"
              @click="setEditorClean('pipeline', JSON.parse(JSON.stringify(p)))"
            >
              {{ t('JABVOX_AUDIO.EDIT') }}
            </button>
            <button
              class="text-sm text-n-ruby-11"
              @click="deletePipeline(p.id)"
            >
              {{ t('JABVOX_AUDIO.DELETE') }}
            </button>
          </div>
        </div>
      </div>
      <div v-else class="space-y-3">
        <input
          v-model="editingPipeline.name"
          class="reset-base text-sm w-full"
          :placeholder="t('JABVOX_AUDIO.PIPELINE.NAME')"
        />
        <label class="flex flex-col text-xs text-n-slate-11">
          {{ t('JABVOX_AUDIO.PIPELINE.TRANSCRIPTION_MODEL') }}
          <select
            v-model="editingPipeline.transcription_model_id"
            class="reset-base mt-1 text-sm"
          >
            <option :value="null">
              {{ t('JABVOX_AUDIO.PIPELINE.NO_TRANSCRIPTION') }}
            </option>
            <option v-for="m in aiModels" :key="m.id" :value="m.id">
              {{ m.name_jabvox }}
            </option>
          </select>
        </label>
        <label class="flex flex-col text-xs text-n-slate-11">
          {{ t('JABVOX_AUDIO.PIPELINE.TYPIFICATION') }}
          <select
            v-model="editingPipeline.typification_id"
            class="reset-base mt-1 text-sm"
          >
            <option :value="null">
              {{ t('JABVOX_AUDIO.PIPELINE.NO_TYPIFICATION') }}
            </option>
            <option v-for="tp in typifications" :key="tp.id" :value="tp.id">
              {{ tp.name }}
            </option>
          </select>
        </label>
        <textarea
          v-model="editingPipeline.transcription_prompt"
          rows="2"
          class="reset-base text-sm w-full"
          :placeholder="t('JABVOX_AUDIO.PIPELINE.TRANSCRIPTION_PROMPT')"
        />
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          <input v-model="editingPipeline.is_default" type="checkbox" />
          {{ t('JABVOX_AUDIO.PIPELINE.SET_DEFAULT') }}
        </label>
        <div
          v-for="(stage, index) in editingPipeline.stages"
          v-show="!stage._destroy"
          :key="index"
          class="p-3 rounded-lg bg-n-alpha-1 space-y-2"
        >
          <div class="flex items-center gap-2">
            <input
              v-model="stage.name"
              class="reset-base text-sm flex-1"
              :placeholder="t('JABVOX_AUDIO.PIPELINE.STAGE_NAME')"
            />
            <input
              v-model.number="stage.min_score"
              type="number"
              min="0"
              max="100"
              class="reset-base text-sm w-20"
              :placeholder="t('JABVOX_AUDIO.PIPELINE.MIN_SCORE')"
            />
            <button class="text-n-ruby-11" @click="removeStage(index)">
              <span class="i-lucide-trash-2" />
            </button>
          </div>
          <textarea
            v-model="stage.prompt"
            rows="3"
            class="reset-base text-sm w-full"
            :placeholder="t('JABVOX_AUDIO.PIPELINE.PROMPT')"
          />
          <label class="flex flex-col text-xs text-n-slate-11">
            {{ t('JABVOX_AUDIO.PIPELINE.LLM_MODEL') }}
            <select
              v-model="stage.llm_model_id"
              class="reset-base mt-1 text-sm"
            >
              <option :value="null">
                {{ t('JABVOX_AUDIO.PIPELINE.DEFAULT_MODEL') }}
              </option>
              <option v-for="m in aiModels" :key="m.id" :value="m.id">
                {{ m.name_jabvox }}
              </option>
            </select>
          </label>
        </div>
        <button class="text-sm text-n-brand" @click="addStage">
          + {{ t('JABVOX_AUDIO.PIPELINE.ADD_STAGE') }}
        </button>
        <div class="flex gap-3">
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
            @click="savePipeline"
          >
            {{ t('JABVOX_AUDIO.SAVE') }}
          </button>
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
            @click="setEditorClean('pipeline', null)"
          >
            {{ t('JABVOX_AUDIO.CANCEL') }}
          </button>
        </div>
      </div>
    </section>

    <!-- Analyzer tab -->
    <section v-else-if="activeTab === 'analyzer'" class="max-w-4xl space-y-4">
      <div class="flex flex-wrap gap-3 items-end">
        <label class="flex flex-col text-xs text-n-slate-11">
          {{ t('JABVOX_AUDIO.ANALYZER.STORAGE') }}
          <select
            v-model="selectedStorageId"
            class="reset-base mt-1 text-sm"
            @change="browse('')"
          >
            <option :value="null">—</option>
            <option v-for="s in storages" :key="s.id" :value="s.id">
              {{ s.name }}
            </option>
          </select>
        </label>
        <label class="flex flex-col text-xs text-n-slate-11">
          {{ t('JABVOX_AUDIO.ANALYZER.PIPELINE') }}
          <select v-model="selectedPipelineId" class="reset-base mt-1 text-sm">
            <option :value="null">—</option>
            <option v-for="p in pipelines" :key="p.id" :value="p.id">
              {{ p.name }}
            </option>
          </select>
        </label>
        <label class="flex flex-col text-xs text-n-slate-11">
          {{ t('JABVOX_AUDIO.ANALYZER.ASSIGN_AGENT') }}
          <select v-model="assignedAgentId" class="reset-base mt-1 text-sm">
            <option :value="null">
              {{ t('JABVOX_AUDIO.ANALYZER.NO_AGENT') }}
            </option>
            <option v-for="a in agents" :key="a.id" :value="a.id">
              {{ a.name }}
            </option>
          </select>
        </label>
        <button
          class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
          :disabled="!selectedKeys.size || !selectedPipelineId"
          @click="launchJob"
        >
          {{ t('JABVOX_AUDIO.ANALYZER.LAUNCH') }} ({{ selectedKeys.size }})
        </button>
      </div>

      <!-- Bulk selection of the listed audio files -->
      <div
        v-if="browser.files.length"
        class="flex flex-wrap items-center gap-2 text-xs"
      >
        <span class="text-n-slate-11">{{
          t('JABVOX_AUDIO.ANALYZER.SELECT')
        }}</span>
        <button
          v-for="n in SELECT_PRESETS"
          :key="n"
          class="px-2.5 py-1 rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 disabled:opacity-40"
          :disabled="browser.files.length < n"
          @click="selectAudios(n)"
        >
          {{ n }}
        </button>
        <button
          class="px-2.5 py-1 rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3"
          @click="selectAudios('all')"
        >
          {{ t('JABVOX_AUDIO.ANALYZER.SELECT_ALL') }} ({{
            browser.files.length
          }})
        </button>
        <button
          v-if="selectedKeys.size"
          class="px-2.5 py-1 rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
          @click="clearSelection"
        >
          {{ t('JABVOX_AUDIO.ANALYZER.CLEAR') }}
        </button>
      </div>

      <div v-if="activeJob" class="p-4 rounded-lg bg-n-alpha-2">
        <div class="flex justify-between text-sm text-n-slate-11 mb-1">
          <span>
            {{ t('JABVOX_AUDIO.ANALYZER.PROGRESS') }} ({{ activeJob.status }})
          </span>
          <span>
            {{ activeJob.processed_count }} / {{ activeJob.total_count }}
          </span>
        </div>
        <div class="h-2 rounded-full bg-n-alpha-1 overflow-hidden">
          <div
            class="h-full bg-n-brand"
            :style="{
              width: `${activeJob.total_count ? (activeJob.processed_count / activeJob.total_count) * 100 : 0}%`,
            }"
          />
        </div>
      </div>

      <div v-if="browsing" class="text-sm text-n-slate-11">
        {{ t('JABVOX_AUDIO.ANALYZER.LOADING') }}
      </div>
      <div
        v-else
        class="border border-n-weak rounded-lg divide-y divide-n-weak"
      >
        <button
          v-if="prefix"
          class="block w-full text-left px-3 py-2 text-sm text-n-slate-11"
          @click="
            browse(
              prefix.split('/').slice(0, -2).join('/') +
                (prefix.split('/').length > 2 ? '/' : '')
            )
          "
        >
          ⬆ ..
        </button>
        <button
          v-for="folder in browser.folders"
          :key="folder"
          class="block w-full text-left px-3 py-2 text-sm text-n-slate-12"
          @click="browse(folder)"
        >
          📁 {{ folder }}
        </button>
        <label
          v-for="file in browser.files"
          :key="file.key"
          class="flex items-center gap-2 px-3 py-2 text-sm text-n-slate-12 cursor-pointer"
        >
          <input
            type="checkbox"
            :checked="selectedKeys.has(file.key)"
            @change="toggleKey(file.key)"
          />
          🎵 {{ file.key.split('/').pop() }}
        </label>
        <p
          v-if="!browser.folders.length && !browser.files.length"
          class="px-3 py-6 text-center text-sm text-n-slate-11"
        >
          {{ t('JABVOX_AUDIO.ANALYZER.EMPTY') }}
        </p>
      </div>
    </section>

    <!-- Jobs tab -->
    <section v-else-if="activeTab === 'jobs'" class="max-w-3xl">
      <div
        v-for="job in jobs"
        :key="job.id"
        class="mb-2 rounded-lg bg-n-alpha-2 overflow-hidden"
      >
        <!-- Job summary (click to expand per-audio detail) -->
        <button
          class="w-full text-left p-3 hover:bg-n-alpha-1"
          @click="toggleJob(job)"
        >
          <div class="flex justify-between text-sm items-center">
            <span class="text-n-slate-12 flex items-center gap-1">
              <span
                class="i-lucide-chevron-right size-4 transition-transform"
                :class="expandedJobId === job.id ? 'rotate-90' : ''"
              />
              #{{ job.id }} · {{ job.status }}
            </span>
            <span class="text-n-slate-11">
              {{ job.processed_count }}/{{ job.total_count }} ·
              {{ t('JABVOX_AUDIO.JOBS.SCORE') }} {{ job.average_score ?? '—' }}
            </span>
          </div>
          <div class="text-xs text-n-slate-11 mt-1 pl-5">
            ✅ {{ job.passed_count }} · ❌ {{ job.failed_count }} · 🙂
            {{ job.positive_count }} · 😐 {{ job.neutral_count }} · 🙁
            {{ job.negative_count }}
          </div>
        </button>

        <!-- Per-audio results -->
        <div
          v-if="expandedJobId === job.id"
          class="border-t border-n-weak divide-y divide-n-weak"
        >
          <p
            v-if="loadingResults && !jobResults[job.id]"
            class="p-3 text-sm text-n-slate-11"
          >
            {{ t('JABVOX_AUDIO.JOBS.LOADING_RESULTS') }}
          </p>
          <div
            v-for="r in jobResults[job.id] || []"
            :key="r.id"
            class="p-3 bg-n-solid-1"
          >
            <div class="flex items-center justify-between gap-2 text-sm">
              <span class="text-n-slate-12 truncate flex items-center gap-1.5">
                🎵 {{ fileName(r.file_key) }}
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
                  {{
                    r.sentiment === 'positive'
                      ? '🙂'
                      : r.sentiment === 'negative'
                        ? '🙁'
                        : '😐'
                  }}
                </span>
                <span v-if="r.status !== 'completed'" class="text-n-slate-11">
                  {{ r.status }}
                </span>
              </span>
            </div>

            <!-- Stage-by-stage detail: score + why it scored that -->
            <div
              v-if="r.stages_data && r.stages_data.length"
              class="mt-2 pl-5 space-y-2"
            >
              <div
                v-for="(st, si) in r.stages_data"
                :key="si"
                class="rounded-lg bg-n-alpha-1 p-2"
              >
                <div class="flex items-center gap-2 text-xs">
                  <span
                    class="font-medium px-1.5 py-0.5 rounded"
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
                <!-- Why it scored that -->
                <p
                  v-if="st.reasoning"
                  class="text-xs text-n-slate-11 mt-1 whitespace-pre-wrap break-words"
                >
                  {{ st.reasoning }}
                </p>
                <!-- Highlights -->
                <ul
                  v-if="st.highlights && st.highlights.length"
                  class="reset-base mt-1 space-y-0.5"
                >
                  <li
                    v-for="(h, hi) in st.highlights"
                    :key="`h${hi}`"
                    class="text-xs text-n-teal-11"
                  >
                    ✓ {{ h }}
                  </li>
                </ul>
                <!-- Issues -->
                <ul
                  v-if="st.issues && st.issues.length"
                  class="reset-base mt-0.5 space-y-0.5"
                >
                  <li
                    v-for="(iss, ii) in st.issues"
                    :key="`i${ii}`"
                    class="text-xs text-n-ruby-11"
                  >
                    ✗ {{ iss }}
                  </li>
                </ul>
              </div>
            </div>

            <!-- Error (if the audio failed to process) -->
            <p v-if="r.error_message" class="text-xs text-n-ruby-11 mt-1 pl-5">
              {{ r.error_message }}
            </p>

            <!-- Transcript (collapsible) -->
            <div v-if="r.transcript" class="mt-2 pl-5">
              <button
                class="text-xs text-n-brand hover:underline"
                @click="toggleTranscript(r.file_key)"
              >
                {{
                  expandedResultKey === r.file_key
                    ? t('JABVOX_AUDIO.JOBS.HIDE_TRANSCRIPT')
                    : t('JABVOX_AUDIO.JOBS.SHOW_TRANSCRIPT')
                }}
              </button>
              <pre
                v-if="expandedResultKey === r.file_key"
                class="mt-1 p-2 rounded bg-n-alpha-1 text-xs text-n-slate-12 whitespace-pre-wrap break-words max-h-64 overflow-y-auto"
                >{{ r.transcript }}</pre
              >
            </div>
          </div>
          <p
            v-if="
              jobResults[job.id] &&
              !jobResults[job.id].length &&
              !loadingResults
            "
            class="p-3 text-sm text-n-slate-11"
          >
            {{ t('JABVOX_AUDIO.JOBS.NO_RESULTS') }}
          </p>
        </div>
      </div>
      <p v-if="!jobs.length" class="text-sm text-n-slate-11">
        {{ t('JABVOX_AUDIO.JOBS.EMPTY') }}
      </p>
    </section>

    <!-- Access tab -->
    <section v-else-if="activeTab === 'access'" class="max-w-2xl">
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="py-2">{{ t('JABVOX_AUDIO.ACCESS.USER') }}</th>
            <th class="py-2">{{ t('JABVOX_AUDIO.ACCESS.CAN_ACCESS') }}</th>
            <th class="py-2">
              {{ t('JABVOX_AUDIO.ACCESS.CAN_VIEW_REPORTS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="u in users"
            :key="u.user_id"
            class="border-b border-n-weak"
          >
            <td class="py-2 text-n-slate-12">{{ u.name }}</td>
            <td class="py-2">
              <input
                v-model="u.can_access"
                type="checkbox"
                @change="updateUser(u)"
              />
            </td>
            <td class="py-2">
              <input
                v-model="u.can_view_reports"
                type="checkbox"
                @change="updateUser(u)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </section>
  </div>
</template>
