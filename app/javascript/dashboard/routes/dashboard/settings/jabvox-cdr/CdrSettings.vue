<script setup>
/* eslint-disable no-underscore-dangle */
// _destroy is the Rails accepts_nested_attributes_for convention for removing rows.
import { ref, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useUnsavedChanges } from 'dashboard/composables/jabvox/useUnsavedChanges';
import {
  cdrConfigAPI,
  cdrPipelinesAPI,
  cdrPermissionsAPI,
} from 'dashboard/api/jabvox/cdr';
import { aiChatModelsAPI } from 'dashboard/api/jabvox/aiChat';
import { typificationsAPI } from 'dashboard/api/jabvox/clickToCall';

const { t } = useI18n();

// Warn before reload/close if there are unsaved changes in any form on this screen.
const { markDirty, markClean } = useUnsavedChanges();
// Re-arm dirty tracking after programmatic loads/saves (skip the change they cause).
const trackChanges = source => watch(source, () => markDirty(), { deep: true });

const activeTab = ref('connection');
const tabs = [
  { key: 'connection', label: () => t('JABVOX_CDR.SETTINGS.TABS.CONNECTION') },
  { key: 'pipelines', label: () => t('JABVOX_CDR.SETTINGS.TABS.PIPELINES') },
  {
    key: 'permissions',
    label: () => t('JABVOX_CDR.SETTINGS.TABS.PERMISSIONS'),
  },
];

// ---- Connection ----
const config = ref({
  mysql_host: '',
  mysql_port: 3306,
  mysql_username: '',
  mysql_password: '',
  mysql_database: 'asteriskcdrdb',
  mysql_table: 'cdr',
  ssh_host: '',
  ssh_port: 22,
  ssh_username: '',
  ssh_password: '',
  recordings_path: '/var/spool/asterisk/monitor',
  analysis_mode: 'manual',
  min_duration_seconds: 30,
  default_pipeline_id: null,
});
const savingConfig = ref(false);
const testingMysql = ref(false);
const testingSsh = ref(false);
// null = never tested, true = ok, false = failed
const mysqlStatus = ref(null);
const sshStatus = ref(null);

const loadConfig = async () => {
  const { data } = await cdrConfigAPI.get();
  config.value = {
    ...config.value,
    ...data,
    mysql_password: '',
    ssh_password: '',
  };
  // The programmatic update above triggers the deep watch; clear it next tick.
  await nextTick();
  markClean();
};

const saveConfig = async () => {
  savingConfig.value = true;
  try {
    await cdrConfigAPI.update(config.value);
    useAlert(t('JABVOX_CDR.SETTINGS.SAVED'));
    await loadConfig();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('JABVOX_CDR.SETTINGS.SAVE_ERROR')
    );
  } finally {
    savingConfig.value = false;
  }
};

const testMysql = async () => {
  testingMysql.value = true;
  try {
    const { data } = await cdrConfigAPI.test(config.value);
    mysqlStatus.value = data.success;
    useAlert(data.message);
  } catch {
    mysqlStatus.value = false;
    useAlert(t('JABVOX_CDR.SETTINGS.TEST_ERROR'));
  } finally {
    testingMysql.value = false;
  }
};

const testSsh = async () => {
  testingSsh.value = true;
  try {
    const { data } = await cdrConfigAPI.testSsh(config.value);
    sshStatus.value = data.success;
    useAlert(data.message);
  } catch {
    sshStatus.value = false;
    useAlert(t('JABVOX_CDR.SETTINGS.TEST_ERROR'));
  } finally {
    testingSsh.value = false;
  }
};

// ---- Pipelines ----
const pipelines = ref([]);
// AI models configured under Settings → Jabvox → AI Chat.
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
  const { data } = await cdrPipelinesAPI.getAll();
  pipelines.value = data.pipelines || [];
};

const newPipeline = () => ({
  name: '',
  is_default: false,
  stages: [],
});
const editing = ref(null);

const startCreate = () => {
  editing.value = newPipeline();
};
const startEdit = pipeline => {
  editing.value = JSON.parse(JSON.stringify(pipeline));
};
const addStage = () => {
  editing.value.stages.push({
    name: '',
    prompt: '',
    min_score: 50,
    position: editing.value.stages.length,
  });
};
const removeStage = index => {
  const stage = editing.value.stages[index];
  if (stage.id) stage._destroy = true;
  else editing.value.stages.splice(index, 1);
};

const savePipeline = async () => {
  if (!editing.value.name) {
    useAlert(t('JABVOX_CDR.SETTINGS.PIPELINE.NAME_REQUIRED'));
    return;
  }
  const visibleStages = editing.value.stages.filter(s => !s._destroy);
  if (!visibleStages.length) {
    useAlert(t('JABVOX_CDR.SETTINGS.PIPELINE.STAGES_REQUIRED'));
    return;
  }
  const payload = {
    name: editing.value.name,
    is_default: editing.value.is_default,
    transcription_model_id: editing.value.transcription_model_id,
    typification_id: editing.value.typification_id,
    stages_attributes: editing.value.stages.map((s, i) => ({
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
    if (editing.value.id)
      await cdrPipelinesAPI.update(editing.value.id, payload);
    else await cdrPipelinesAPI.create(payload);
    editing.value = null;
    await loadPipelines();
    await nextTick();
    markClean();
    useAlert(t('JABVOX_CDR.SETTINGS.SAVED'));
  } catch (error) {
    useAlert(t('JABVOX_CDR.SETTINGS.SAVE_ERROR'));
  }
};

const deletePipeline = async id => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('JABVOX_CDR.SETTINGS.PIPELINE.CONFIRM_DELETE'))) return;
  await cdrPipelinesAPI.destroy(id);
  await loadPipelines();
};

// ---- Permissions ----
const permissions = ref([]);
const loadPermissions = async () => {
  const { data } = await cdrPermissionsAPI.getAll();
  permissions.value = data.permissions || [];
};
const savePermissions = async () => {
  const ids = permissions.value.filter(p => p.can_view).map(p => p.user_id);
  try {
    await cdrPermissionsAPI.bulk(ids);
    await nextTick();
    markClean();
    useAlert(t('JABVOX_CDR.SETTINGS.SAVED'));
  } catch (error) {
    useAlert(t('JABVOX_CDR.SETTINGS.SAVE_ERROR'));
  }
};

const switchTab = async key => {
  activeTab.value = key;
  if (key === 'pipelines' && !pipelines.value.length) await loadPipelines();
  if (key === 'permissions' && !permissions.value.length)
    await loadPermissions();
};

onMounted(async () => {
  await loadConfig();
  // Track edits across the connection form, the pipeline editor and permissions.
  trackChanges(config);
  trackChanges(editing);
  trackChanges(permissions);
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -- numeric port placeholders are universal -->
  <div class="flex flex-col flex-1 overflow-auto p-6">
    <h1 class="text-xl font-medium text-n-slate-12 mb-1">
      {{ t('JABVOX_CDR.SETTINGS.TITLE') }}
    </h1>
    <p class="text-sm text-n-slate-11 mb-4">
      {{ t('JABVOX_CDR.SETTINGS.SUBTITLE') }}
    </p>

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

    <!-- Connection tab -->
    <section v-if="activeTab === 'connection'" class="max-w-2xl space-y-4">

      <!-- PBX card -->
      <div class="rounded-xl border border-n-weak bg-n-surface-1 overflow-hidden">
        <div class="flex items-center justify-between px-4 py-3 border-b border-n-weak bg-n-alpha-1">
          <div class="flex items-center gap-2">
            <span class="i-lucide-database size-4 text-n-slate-11" />
            <span class="text-sm font-medium text-n-slate-12">{{ t('JABVOX_CDR.SETTINGS.MYSQL') }}</span>
          </div>
          <span
            v-if="mysqlStatus !== null"
            class="inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full"
            :class="mysqlStatus
              ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
              : 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400'"
          >
            <span
              class="size-1.5 rounded-full"
              :class="mysqlStatus ? 'bg-green-500' : 'bg-red-500'"
            />
            {{ mysqlStatus ? t('JABVOX_CDR.SETTINGS.STATUS_OK') : t('JABVOX_CDR.SETTINGS.STATUS_ERROR') }}
          </span>
        </div>
        <div class="p-4 grid grid-cols-2 gap-3">
          <input
            v-model="config.mysql_host"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.HOST')"
          />
          <input
            v-model.number="config.mysql_port"
            type="number"
            class="reset-base text-sm"
            placeholder="3306"
          />
          <input
            v-model="config.mysql_username"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.USER')"
          />
          <input
            v-model="config.mysql_password"
            type="password"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.PASSWORD')"
          />
          <input
            v-model="config.mysql_database"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.DATABASE')"
          />
          <input
            v-model="config.mysql_table"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.TABLE')"
          />
        </div>
        <div class="px-4 pb-4">
          <button
            class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 disabled:opacity-50 transition-colors"
            :disabled="testingMysql"
            @click="testMysql"
          >
            <span v-if="testingMysql" class="i-lucide-loader-2 size-3.5 animate-spin mr-1" />
            {{ t('JABVOX_CDR.SETTINGS.TEST') }}
          </button>
        </div>
      </div>

      <!-- SSH/SFTP card -->
      <div class="rounded-xl border border-n-weak bg-n-surface-1 overflow-hidden">
        <div class="flex items-center justify-between px-4 py-3 border-b border-n-weak bg-n-alpha-1">
          <div class="flex items-center gap-2">
            <span class="i-lucide-hard-drive size-4 text-n-slate-11" />
            <span class="text-sm font-medium text-n-slate-12">{{ t('JABVOX_CDR.SETTINGS.SSH') }}</span>
          </div>
          <span
            v-if="sshStatus !== null"
            class="inline-flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-full"
            :class="sshStatus
              ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
              : 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400'"
          >
            <span
              class="size-1.5 rounded-full"
              :class="sshStatus ? 'bg-green-500' : 'bg-red-500'"
            />
            {{ sshStatus ? t('JABVOX_CDR.SETTINGS.STATUS_OK') : t('JABVOX_CDR.SETTINGS.STATUS_ERROR') }}
          </span>
        </div>
        <div class="p-4 grid grid-cols-2 gap-3">
          <input
            v-model="config.ssh_host"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.HOST')"
          />
          <input
            v-model.number="config.ssh_port"
            type="number"
            class="reset-base text-sm"
            placeholder="22"
          />
          <input
            v-model="config.ssh_username"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.USER')"
          />
          <input
            v-model="config.ssh_password"
            type="password"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.PASSWORD')"
          />
          <input
            v-model="config.recordings_path"
            class="reset-base text-sm col-span-2"
            :placeholder="t('JABVOX_CDR.SETTINGS.RECORDINGS_PATH')"
          />
        </div>
        <div class="px-4 pb-4">
          <button
            class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 disabled:opacity-50 transition-colors"
            :disabled="testingSsh"
            @click="testSsh"
          >
            <span v-if="testingSsh" class="i-lucide-loader-2 size-3.5 animate-spin mr-1" />
            {{ t('JABVOX_CDR.SETTINGS.TEST') }}
          </button>
        </div>
      </div>

      <!-- Analysis -->
      <div class="rounded-xl border border-n-weak bg-n-surface-1 overflow-hidden">
        <div class="flex items-center gap-2 px-4 py-3 border-b border-n-weak bg-n-alpha-1">
          <span class="i-lucide-cpu size-4 text-n-slate-11" />
          <span class="text-sm font-medium text-n-slate-12">{{ t('JABVOX_CDR.SETTINGS.ANALYSIS') }}</span>
        </div>
        <div class="p-4 grid grid-cols-2 gap-3 items-center">
          <select v-model="config.analysis_mode" class="reset-base text-sm">
            <option value="manual">{{ t('JABVOX_CDR.SETTINGS.MODE_MANUAL') }}</option>
            <option value="auto_all">{{ t('JABVOX_CDR.SETTINGS.MODE_AUTO_ALL') }}</option>
            <option value="auto_min_duration">{{ t('JABVOX_CDR.SETTINGS.MODE_AUTO_MIN') }}</option>
          </select>
          <input
            v-if="config.analysis_mode === 'auto_min_duration'"
            v-model.number="config.min_duration_seconds"
            type="number"
            class="reset-base text-sm"
            :placeholder="t('JABVOX_CDR.SETTINGS.MIN_DURATION')"
          />
          <select v-model="config.default_pipeline_id" class="reset-base text-sm">
            <option :value="null">{{ t('JABVOX_CDR.SETTINGS.NO_DEFAULT_PIPELINE') }}</option>
            <option v-for="p in pipelines" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
        </div>
      </div>

      <div class="flex gap-3 pt-1">
        <button
          class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
          :disabled="savingConfig"
          @click="saveConfig"
        >
          {{ t('JABVOX_CDR.SETTINGS.SAVE') }}
        </button>
      </div>
    </section>

    <!-- Pipelines tab -->
    <section v-else-if="activeTab === 'pipelines'" class="max-w-3xl">
      <div v-if="!editing">
        <button
          class="mb-4 px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
          @click="startCreate"
        >
          {{ t('JABVOX_CDR.SETTINGS.PIPELINE.NEW') }}
        </button>
        <div
          v-for="p in pipelines"
          :key="p.id"
          class="flex items-center justify-between p-3 mb-2 rounded-lg bg-n-alpha-2"
        >
          <div>
            <span class="font-medium text-n-slate-12">{{ p.name }}</span>
            <span v-if="p.is_default" class="ml-2 text-xs text-n-brand">{{
              t('JABVOX_CDR.SETTINGS.PIPELINE.DEFAULT')
            }}</span>
            <span class="ml-2 text-xs text-n-slate-11">
              {{ p.stages.length }}
              {{ t('JABVOX_CDR.SETTINGS.PIPELINE.STAGES') }}
            </span>
          </div>
          <div class="flex gap-2">
            <button class="text-sm text-n-slate-11" @click="startEdit(p)">
              {{ t('JABVOX_CDR.SETTINGS.EDIT') }}
            </button>
            <button
              class="text-sm text-n-ruby-11"
              @click="deletePipeline(p.id)"
            >
              {{ t('JABVOX_CDR.SETTINGS.DELETE') }}
            </button>
          </div>
        </div>
        <p v-if="!pipelines.length" class="text-sm text-n-slate-11">
          {{ t('JABVOX_CDR.SETTINGS.PIPELINE.EMPTY') }}
        </p>
      </div>

      <div v-else class="space-y-4">
        <input
          v-model="editing.name"
          class="reset-base text-sm w-full"
          :placeholder="t('JABVOX_CDR.SETTINGS.PIPELINE.NAME')"
        />
        <label class="flex flex-col text-xs text-n-slate-11">
          {{ t('JABVOX_CDR.SETTINGS.PIPELINE.TRANSCRIPTION_MODEL') }}
          <select
            v-model="editing.transcription_model_id"
            class="reset-base mt-1 text-sm"
          >
            <option :value="null">
              {{ t('JABVOX_CDR.SETTINGS.PIPELINE.NO_TRANSCRIPTION') }}
            </option>
            <option v-for="m in aiModels" :key="m.id" :value="m.id">
              {{ m.name_jabvox }}
            </option>
          </select>
        </label>
        <label class="flex flex-col text-xs text-n-slate-11">
          {{ t('JABVOX_CDR.SETTINGS.PIPELINE.TYPIFICATION') }}
          <select
            v-model="editing.typification_id"
            class="reset-base mt-1 text-sm"
          >
            <option :value="null">
              {{ t('JABVOX_CDR.SETTINGS.PIPELINE.NO_TYPIFICATION') }}
            </option>
            <option v-for="tp in typifications" :key="tp.id" :value="tp.id">
              {{ tp.name }}
            </option>
          </select>
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          <input v-model="editing.is_default" type="checkbox" />
          {{ t('JABVOX_CDR.SETTINGS.PIPELINE.SET_DEFAULT') }}
        </label>

        <div
          v-for="(stage, index) in editing.stages"
          v-show="!stage._destroy"
          :key="index"
          class="p-3 rounded-lg bg-n-alpha-1 space-y-2"
        >
          <div class="flex items-center justify-between">
            <input
              v-model="stage.name"
              class="reset-base text-sm flex-1 mr-2"
              :placeholder="t('JABVOX_CDR.SETTINGS.PIPELINE.STAGE_NAME')"
            />
            <input
              v-model.number="stage.min_score"
              type="number"
              min="0"
              max="100"
              class="reset-base text-sm w-20"
              :placeholder="t('JABVOX_CDR.SETTINGS.PIPELINE.MIN_SCORE')"
            />
            <button class="ml-2 text-n-ruby-11" @click="removeStage(index)">
              <span class="i-lucide-trash-2" />
            </button>
          </div>
          <textarea
            v-model="stage.prompt"
            rows="3"
            class="reset-base text-sm w-full"
            :placeholder="t('JABVOX_CDR.SETTINGS.PIPELINE.PROMPT')"
          />
          <label class="flex flex-col text-xs text-n-slate-11">
            {{ t('JABVOX_CDR.SETTINGS.PIPELINE.LLM_MODEL') }}
            <select
              v-model="stage.llm_model_id"
              class="reset-base mt-1 text-sm"
            >
              <option :value="null">
                {{ t('JABVOX_CDR.SETTINGS.PIPELINE.DEFAULT_MODEL') }}
              </option>
              <option v-for="m in aiModels" :key="m.id" :value="m.id">
                {{ m.name_jabvox }}
              </option>
            </select>
          </label>
        </div>

        <button class="text-sm text-n-brand" @click="addStage">
          + {{ t('JABVOX_CDR.SETTINGS.PIPELINE.ADD_STAGE') }}
        </button>

        <div class="flex gap-3">
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
            @click="savePipeline"
          >
            {{ t('JABVOX_CDR.SETTINGS.SAVE') }}
          </button>
          <button
            class="px-4 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
            @click="editing = null"
          >
            {{ t('JABVOX_CDR.SETTINGS.CANCEL') }}
          </button>
        </div>
      </div>
    </section>

    <!-- Permissions tab -->
    <section v-else class="max-w-2xl">
      <div
        v-for="perm in permissions"
        :key="perm.user_id"
        class="flex items-center justify-between p-2 border-b border-n-weak"
      >
        <div>
          <span class="text-n-slate-12">{{ perm.name }}</span>
          <span class="ml-2 text-xs text-n-slate-11">{{ perm.email }}</span>
        </div>
        <input v-model="perm.can_view" type="checkbox" />
      </div>
      <button
        class="mt-4 px-4 py-2 text-sm rounded-lg bg-n-brand text-white"
        @click="savePermissions"
      >
        {{ t('JABVOX_CDR.SETTINGS.SAVE') }}
      </button>
    </section>
  </div>
</template>
